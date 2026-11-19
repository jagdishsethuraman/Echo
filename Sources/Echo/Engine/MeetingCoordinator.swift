import Foundation
import CoreMedia

public final class MeetingAudioLevels: ObservableObject, @unchecked Sendable {
    @Published public var micLevel: Float = 0.0
    @Published public var systemLevel: Float = 0.0

    public init(micLevel: Float = 0.0, systemLevel: Float = 0.0) {
        self.micLevel = micLevel
        self.systemLevel = systemLevel
    }

    public func update(mic: Float, system: Float) {
        self.micLevel = mic
        self.systemLevel = system
    }
}

public final class MeetingCoordinator: ObservableObject, @unchecked Sendable {
    public let dualChannel: DualChannelCoordinator
    public let phononRunner: PhononProcessRunner
    public let micVAD: VoiceActivityDetector
    public let systemVAD: VoiceActivityDetector
    private let database: DatabaseManager
    private let transcriptionService: TranscriptionService
    private let startCapture: @MainActor () async throws -> Void
    private let stopCapture: @MainActor () async -> Void
    
    @MainActor @Published public private(set) var activeSession: MeetingSession?
    public let audioLevels = MeetingAudioLevels()
    @MainActor @Published public var captureError: String? = nil
    
    /// Backward-compatibility forwarding properties (not published to avoid invalidating parent views)
    public var micLevel: Float { audioLevels.micLevel }
    public var systemLevel: Float { audioLevels.systemLevel }
    
    private let callbackLock = NSLock()
    private var _onSessionUpdated: ((MeetingSession) -> Void)?
    
    public var onSessionUpdated: ((MeetingSession) -> Void)? {
        get { callbackLock.withLock { _onSessionUpdated } }
        set { callbackLock.withLock { _onSessionUpdated = newValue } }
    }
    
    private enum Lifecycle {
        case idle
        case starting(Task<SessionWork, Error>)
        case recording
        case finalizing(Task<MeetingSession?, Never>)
    }

    private final class SessionWork: Sendable {
        let id: UUID
        let pending = DispatchGroup()

        init(id: UUID) {
            self.id = id
        }

        func waitUntilPersisted() async {
            await withCheckedContinuation { continuation in
                pending.notify(queue: .global()) { continuation.resume() }
            }
        }
    }

    @MainActor private var lifecycle = Lifecycle.idle
    @MainActor private var sessionWork: SessionWork?
    @MainActor private var failedSegmentCount = 0

    // Audio processing and final flush share a lock. VAD callbacks submit
    // synchronously and reenter the lock to register their segment.
    private let pipelineLock = NSRecursiveLock()
    private var audioSession: SessionWork?
    private var collectingStartupAudio = false
    private var startupAudio: [TaggedAudioSegment] = []
    private var micBufferToken: UUID?
    private var systemBufferToken: UUID?
    private var audioErrorToken: UUID?

    @MainActor
    public convenience init(
        dualChannel: DualChannelCoordinator = DualChannelCoordinator(),
        phononRunner: PhononProcessRunner = PhononProcessRunner(),
        database: DatabaseManager = .shared,
        transcriptionService: TranscriptionService? = nil
    ) {
        self.init(
            dualChannel: dualChannel,
            phononRunner: phononRunner,
            database: database,
            transcriptionService: transcriptionService,
            startCapture: { try await dualChannel.startMeetingCapture() },
            stopCapture: { await dualChannel.stopMeetingCapture() }
        )
    }

    @MainActor
    init(
        dualChannel: DualChannelCoordinator = DualChannelCoordinator(),
        phononRunner: PhononProcessRunner = PhononProcessRunner(),
        database: DatabaseManager,
        transcriptionService: TranscriptionService? = nil,
        startCapture: @escaping @MainActor () async throws -> Void,
        stopCapture: @escaping @MainActor () async -> Void
    ) {
        self.dualChannel = dualChannel
        self.phononRunner = phononRunner
        self.database = database
        self.startCapture = startCapture
        self.stopCapture = stopCapture
        self.transcriptionService = transcriptionService
            ?? TranscriptionService(runner: phononRunner)
        self.micVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        self.systemVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        
        // Retention runs before restore so empty rows left by older builds
        // (including stale open sessions) do not come back as the active stream.
        _ = database.deleteEmptySessions(includingOpen: true)

        // Restore an open session and its utterances from SQLite. Closed or
        // empty sessions from past launches must not be revived, and no empty
        // session is created until the first utterance arrives (DATA-03).
        if var lastSession = database.fetchRecentSessions(limit: 1).first, lastSession.endTime == nil {
            let segments = database.fetchUtterances(sessionId: lastSession.id)
            if !segments.isEmpty {
                lastSession.segments = segments
                self.activeSession = lastSession
                self.sessionWork = SessionWork(id: lastSession.id)
            } else {
                self.activeSession = nil
            }
        } else {
            self.activeSession = nil
        }
        
        setupVADHandlers()
        setupAudioPipelines()
    }
    
    @MainActor
    var recordingSessionID: UUID? {
        guard case .recording = lifecycle else { return nil }
        return sessionWork?.id
    }

    private var audioSessionID: UUID? {
        pipelineLock.withLock { audioSession?.id }
    }

    private func feedAudio(_ detector: VoiceActivityDetector, pcmData: Data, level: Float, sessionID: UUID) {
        pipelineLock.withLock {
            guard audioSession?.id == sessionID else { return }
            detector.processChunk(pcmData: pcmData, rmsEnergy: level)
        }
    }

    private func closeAudioPipeline() {
        pipelineLock.withLock {
            micVAD.flush()
            systemVAD.flush()
            audioSession = nil
        }
    }

    /// Feed the two VADs with canonical 16 kHz mono Int16 PCM.
    private func setupAudioPipelines() {
        // Microphone: `AudioEngineManager` already delivers 16 kHz mono Float32.
        micBufferToken = dualChannel.hub.addMicBufferObserver { [weak self] buffer in
            guard let self, let sessionID = self.audioSessionID else { return }
            guard let pcmData = AudioBufferConverter.int16PCM(from: buffer) else { return }
            let level = AudioBufferConverter.calculateRMS(from: buffer)
            self.feedAudio(self.micVAD, pcmData: pcmData, level: level, sessionID: sessionID)
        }
        
        // System loopback: ScreenCaptureKit hands us raw CMSampleBuffers that
        // must be decoded and resampled before the VAD can slice them.
        systemBufferToken = dualChannel.hub.addSystemBufferObserver { [weak self] sampleBuffer in
            guard let self, let sessionID = self.audioSessionID else { return }
            guard let converted = AudioBufferConverter.pcmBuffer(from: sampleBuffer),
                  let pcmData = AudioBufferConverter.int16PCM(from: converted) else {
                return
            }
            let level = AudioBufferConverter.calculateRMS(from: converted)
            self.feedAudio(self.systemVAD, pcmData: pcmData, level: level, sessionID: sessionID)
        }
        
        audioErrorToken = dualChannel.hub.addErrorObserver { [weak self] error in
            DispatchQueue.main.async {
                self?.captureError = error.localizedDescription
            }
        }
    }
    
    deinit {
        if let micBufferToken { dualChannel.hub.removeObserver(micBufferToken) }
        if let systemBufferToken { dualChannel.hub.removeObserver(systemBufferToken) }
        if let audioErrorToken { dualChannel.hub.removeObserver(audioErrorToken) }
    }
    
    private func setupVADHandlers() {
        dualChannel.onDualLevelsUpdated = { [weak self] mic, sys in
            DispatchQueue.main.async {
                self?.audioLevels.update(mic: mic, system: sys)
            }
        }
        
        micVAD.onSpeechSegmentCompleted = { [weak self] pcmData, duration in
            self?.enqueueSegment(track: .you, pcmData: pcmData, duration: duration)
        }
        
        systemVAD.onSpeechSegmentCompleted = { [weak self] pcmData, duration in
            self?.enqueueSegment(track: .meeting, pcmData: pcmData, duration: duration)
        }
    }
    
    /// Bind a segment to the recording that produced it before the engine runs.
    @discardableResult
    func enqueueSegment(track: SpeakerTrack, pcmData: Data, duration: Double) -> Task<Void, Never>? {
        pipelineLock.withLock {
            guard let work = audioSession else { return nil }
            let segment = TaggedAudioSegment(track: track, pcmData: pcmData, durationSeconds: duration)
            if collectingStartupAudio {
                startupAudio.append(segment)
                return nil
            }
            return submit(segment, for: work)
        }
    }

    private func submit(_ audio: TaggedAudioSegment, for work: SessionWork) -> Task<Void, Never> {
        work.pending.enter()
        return transcriptionService.submitReporting(pcmData: audio.pcmData) { [weak self] result in
            defer { work.pending.leave() }
            guard let self else { return }
            switch result {
            case .success(let text):
                guard !text.isEmpty else { return }
                let segment = TranscriptSegment(
                    speaker: audio.track,
                    timestamp: audio.timestamp,
                    text: WordMemoryEngine.shared.sanitize(text),
                    durationSeconds: audio.durationSeconds
                )
                await self.append(segment, sessionID: work.id, isDictation: false)
            case .failure(let error):
                await self.reportSegmentFailure(error, sessionID: work.id)
            }
        }
    }

    @MainActor
    private func reportSegmentFailure(_ error: Error, sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        failedSegmentCount += 1
        let segments = failedSegmentCount == 1 ? "segment" : "segments"
        captureError = "\(failedSegmentCount) meeting \(segments) could not be transcribed. \(error.localizedDescription)"
    }

    @MainActor
    private func append(_ segment: TranscriptSegment, sessionID: UUID, isDictation: Bool) async {
        guard var session = activeSession, session.id == sessionID, session.endTime == nil else { return }
        session.segments.append(segment)
        activeSession = session
        onSessionUpdated?(session)
        await database.saveSessionAndUtteranceAsync(session, segment: segment, isDictation: isDictation)
    }

    /// Append a completed Quick Dictation utterance into the unified session timeline and SQLite.
    @MainActor
    public func appendDictation(text: String, duration: Double = 1.0) async {
        let segment = TranscriptSegment(speaker: .you, text: text, durationSeconds: duration)
        switch lifecycle {
        case .idle:
            if sessionWork == nil {
                let session = MeetingSession(title: "Echo Speech Stream", startTime: Date())
                sessionWork = SessionWork(id: session.id)
                activeSession = session
            }
        case .recording:
            break
        case .starting, .finalizing:
            await database.saveUtteranceAsync(segment, isDictation: true)
            return
        }

        guard let work = sessionWork else { return }
        work.pending.enter()
        defer { work.pending.leave() }
        await append(segment, sessionID: work.id, isDictation: true)
    }

    /// Delete a stored session (and its utterances via the FK cascade).
    @MainActor
    @discardableResult
    public func deleteSession(id: UUID) async -> Bool {
        if activeSession?.id == id {
            guard case .idle = lifecycle else { return false }
            let work = sessionWork
            activeSession = nil
            sessionWork = nil
            await work?.waitUntilPersisted()
        }
        await database.deleteSessionAsync(id: id)
        return true
    }

    /// Retention: remove empty sessions, protecting an in-progress recording.
    @MainActor
    @discardableResult
    public func deleteEmptySessions() async -> Int {
        await database.deleteEmptySessionsAsync(includingOpen: true, keeping: sessionWork?.id)
    }

    @MainActor
    public func startSession(title: String = "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))") async throws {
        guard case .idle = lifecycle else { return }
        captureError = nil
        failedSegmentCount = 0

        do {
            try transcriptionService.checkReadiness()
        } catch {
            captureError = error.localizedDescription
            throw error
        }

        let startup = Task { () -> SessionWork in
            if let previousWork = sessionWork {
                _ = await persistSessionEnd(previousWork, at: Date())
            }

            let session = MeetingSession(title: title, startTime: Date())
            let work = SessionWork(id: session.id)
            // Microphone samples can arrive while system audio is still starting.
            // Hold their segments until capture succeeds and the parent row exists.
            pipelineLock.withLock {
                micVAD.reset()
                systemVAD.reset()
                audioSession = work
                collectingStartupAudio = true
            }
            do {
                try await startCapture()
            } catch {
                pipelineLock.withLock {
                    audioSession = nil
                    collectingStartupAudio = false
                    startupAudio.removeAll()
                    micVAD.reset()
                    systemVAD.reset()
                }
                captureError = error.localizedDescription
                lifecycle = .idle
                throw error
            }

            sessionWork = work
            activeSession = session
            await database.saveSessionAsync(session)
            pipelineLock.withLock {
                for segment in startupAudio {
                    _ = submit(segment, for: work)
                }
                startupAudio.removeAll()
                collectingStartupAudio = false
            }
            lifecycle = .recording
            onSessionUpdated?(session)
            return work
        }
        lifecycle = .starting(startup)
        _ = try await startup.value
    }

    /// Stop capture, submit buffered speech, and save the final snapshot after all of its writes finish.
    @MainActor
    public func stopSession() async -> MeetingSession? {
        if case .starting(let startup) = lifecycle {
            guard let startedWork = try? await startup.value, startedWork === sessionWork else { return nil }
        }
        if case .finalizing(let finalization) = lifecycle {
            return await finalization.value
        }
        guard let work = sessionWork else { return activeSession }

        let wasRecording = recordingSessionID != nil
        if wasRecording {
            closeAudioPipeline()
        }
        let endTime = Date()
        let finalization = Task { () -> MeetingSession? in
            if wasRecording {
                await stopCapture()
            }
            let session = await persistSessionEnd(work, at: endTime)
            lifecycle = .idle
            return session
        }
        lifecycle = .finalizing(finalization)
        return await finalization.value
    }

    @MainActor
    private func persistSessionEnd(_ work: SessionWork, at endTime: Date) async -> MeetingSession? {
        await work.waitUntilPersisted()
        guard var session = activeSession, session.id == work.id else { return nil }
        session.endTime = endTime
        await database.saveSessionAsync(session)
        activeSession = session
        sessionWork = nil
        return session
    }

    /// Transcribe a segmented chunk and append to the recording's timeline.
    public func processSpeechSegment(track: SpeakerTrack, pcmData: Data, duration: Double) async {
        await enqueueSegment(track: track, pcmData: pcmData, duration: duration)?.value
    }
}
