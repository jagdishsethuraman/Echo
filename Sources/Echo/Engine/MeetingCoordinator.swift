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
    public let noteIndex = IncrementalNotesExtractor()
    public let audioLevels = MeetingAudioLevels()
    @MainActor @Published public var captureError: String? = nil
    
    @MainActor @Published public private(set) var unsavedTranscriptCount = 0
    @MainActor @Published public private(set) var transcriptSaveError: String?
    @MainActor @Published public private(set) var isRetryingTranscriptSaves = false

    public enum SessionDeletionOutcome {
        case deleted
        case notFound
        case busy
        case recording
        case failed(String)
    }

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

    private struct UtteranceSave {
        let segment: TranscriptSegment
        let sessionID: UUID?
        let sessionToCreate: MeetingSession?
        let isDictation: Bool
    }

    private enum TranscriptSave {
        case utterance(UtteranceSave)
        case sessionEnd(MeetingSession)

        var id: UUID {
            switch self {
            case .utterance(let save): return save.segment.id
            case .sessionEnd(let session): return session.id
            }
        }

        var sessionID: UUID? {
            switch self {
            case .utterance(let save): return save.sessionID
            case .sessionEnd(let session): return session.id
            }
        }
    }

    @MainActor private var failedSaves: [UUID: TranscriptSave] = [:]
    @MainActor private var deletingSessionIDs: Set<UUID> = []
    @MainActor private var standalonePurgeCutoff: Date?
    private let transcriptRetryWork = DispatchGroup()

    // Audio processing and final flush share a lock. VAD callbacks submit
    // synchronously and reenter the lock to register their segment.
    private let pipelineLock = NSRecursiveLock()
    private var audioSession: SessionWork?
    private struct StartupAudio {
        var segments: [(TaggedAudioSegment, TranscriptionService.Reservation)] = []
        var rejectedCount = 0
        var lastError: Error?
    }
    private var startupAudio: StartupAudio?
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
        _ = try? database.deleteEmptySessions(includingOpen: true)

        // Restore an open session and its utterances from SQLite. Closed or
        // empty sessions from past launches must not be revived, and no empty
        // session is created until the first utterance arrives (DATA-03).
        if var lastSession = database.fetchRecentSessions(limit: 1).first, lastSession.endTime == nil {
            let segments = database.fetchUtterances(sessionId: lastSession.id)
            if !segments.isEmpty {
                lastSession.segments = segments
                noteIndex.update(segments: segments, for: lastSession.id)
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
        
        // System loopback: ScreenCaptureKit decoded & resampled in a single pass.
        // Uses the converted 16 kHz mono buffer directly without re-running through AVAudioConverter.
        systemBufferToken = dualChannel.hub.addSystemPCMBufferObserver { [weak self] converted, level in
            guard let self, let sessionID = self.audioSessionID else { return }
            guard let pcmData = AudioBufferConverter.int16PCM(from: converted) else { return }
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
        
        micVAD.onSpeechSegmentWithTimestampCompleted = { [weak self] pcmData, duration, timestamp in
            self?.enqueueSegment(track: .you, pcmData: pcmData, duration: duration, timestamp: timestamp)
        }
        
        systemVAD.onSpeechSegmentWithTimestampCompleted = { [weak self] pcmData, duration, timestamp in
            self?.enqueueSegment(track: .meeting, pcmData: pcmData, duration: duration, timestamp: timestamp)
        }
    }
    
    /// Bind a segment to the recording that produced it before the engine runs.
    @discardableResult
    func enqueueSegment(track: SpeakerTrack, pcmData: Data, duration: Double, timestamp: Date = Date()) -> Task<Void, Never>? {
        pipelineLock.withLock {
            guard let work = audioSession else { return nil }
            do {
                let reservation = try transcriptionService.reserveMeetingAudio(bytes: pcmData.count)
                let segment = TaggedAudioSegment(track: track, timestamp: timestamp, pcmData: pcmData, durationSeconds: duration)
                if startupAudio != nil {
                    startupAudio?.segments.append((segment, reservation))
                    return nil
                }
                return submit(segment, reservation: reservation, for: work)
            } catch {
                if startupAudio != nil {
                    startupAudio?.rejectedCount += 1
                    startupAudio?.lastError = error
                    return nil
                }
                work.pending.enter()
                return Task { [weak self] in
                    defer { work.pending.leave() }
                    await self?.reportSegmentFailure(error, sessionID: work.id)
                }
            }
        }
    }

    private func submit(
        _ audio: TaggedAudioSegment,
        reservation: TranscriptionService.Reservation,
        for work: SessionWork
    ) -> Task<Void, Never> {
        work.pending.enter()
        return transcriptionService.submitReserved(pcmData: audio.pcmData, reservation: reservation) {
            [weak self, track = audio.track, timestamp = audio.timestamp, duration = audio.durationSeconds] result in
            defer { work.pending.leave() }
            guard let self else { return }
            switch result {
            case .success(let text):
                guard !text.isEmpty else { return }
                let segment = TranscriptSegment(
                    speaker: track,
                    timestamp: timestamp,
                    text: WordMemoryEngine.shared.sanitize(text),
                    durationSeconds: duration
                )
                await self.append(segment, sessionID: work.id, isDictation: false)
            case .failure(let error):
                await self.reportSegmentFailure(error, sessionID: work.id)
            }
        }
    }

    @MainActor
    private func reportSegmentFailure(_ error: Error, sessionID: UUID, count: Int = 1) {
        guard activeSession?.id == sessionID else { return }
        failedSegmentCount += count
        let segments = failedSegmentCount == 1 ? "segment" : "segments"
        captureError = "\(failedSegmentCount) meeting \(segments) could not be transcribed. \(error.localizedDescription)"
    }

    @MainActor
    private func append(_ segment: TranscriptSegment, sessionID: UUID, isDictation: Bool) async {
        guard var session = activeSession, session.id == sessionID, session.endTime == nil else { return }
        session.segments = []
        await persist(.utterance(UtteranceSave(
            segment: segment,
            sessionID: sessionID,
            sessionToCreate: session,
            isDictation: isDictation
        )))
    }

    @MainActor
    private func shouldKeepStandaloneDictation(_ segment: TranscriptSegment) -> Bool {
        if let cutoff = standalonePurgeCutoff, segment.timestamp < cutoff { return false }
        return EchoSettings.dictationRetention.keepsDictation(at: segment.timestamp)
    }

    @MainActor
    private func persist(_ save: TranscriptSave) async {
        let result: Result<Void, Error>
        switch save {
        case .sessionEnd(let session):
            result = await database.saveSessionAsync(session)
        case .utterance(let utterance):
            if let session = utterance.sessionToCreate {
                result = await database.saveSessionAndUtteranceAsync(
                    session, segment: utterance.segment, isDictation: utterance.isDictation
                )
            } else if utterance.sessionID != nil || shouldKeepStandaloneDictation(utterance.segment) {
                result = await database.saveUtteranceAsync(
                    utterance.segment, sessionId: utterance.sessionID, isDictation: utterance.isDictation
                )
            } else {
                removeFailedSave(save.id)
                return
            }
        }

        switch result {
        case .success:
            removeFailedSave(save.id)
            if case .utterance(let utterance) = save,
               let sessionID = utterance.sessionID,
               var session = activeSession, session.id == sessionID,
               !session.segments.contains(where: { $0.id == utterance.segment.id }) {
                session.segments.append(utterance.segment)
                session.segments.sort { $0.timestamp < $1.timestamp }
                noteIndex.update(segments: [utterance.segment], for: sessionID)
                activeSession = session
                onSessionUpdated?(session)
            }
        case .failure(let error):
            if case .utterance(let utterance) = save, utterance.sessionID == nil,
               !shouldKeepStandaloneDictation(utterance.segment) {
                removeFailedSave(save.id)
                return
            }
            failedSaves[save.id] = save
            transcriptSaveError = error.localizedDescription
            unsavedTranscriptCount = failedSaves.count
        }
    }

    @MainActor
    private func removeFailedSave(_ id: UUID) {
        guard failedSaves.removeValue(forKey: id) != nil else { return }
        unsavedTranscriptCount = failedSaves.count
        if failedSaves.isEmpty { transcriptSaveError = nil }
    }

    @MainActor
    public func retryTranscriptSaves() async {
        guard !isRetryingTranscriptSaves, !failedSaves.isEmpty else { return }
        isRetryingTranscriptSaves = true
        transcriptRetryWork.enter()
        defer {
            isRetryingTranscriptSaves = false
            transcriptRetryWork.leave()
        }
        for save in Array(failedSaves.values) {
            guard let currentSave = failedSaves[save.id],
                  !(currentSave.sessionID.map(deletingSessionIDs.contains) ?? false) else { continue }
            // Avoid racing the close of the current recording with a retry that
            // might need to recreate its parent row.
            let work = currentSave.sessionID == sessionWork?.id ? sessionWork : nil
            if work != nil {
                switch lifecycle {
                case .starting, .finalizing: continue
                case .recording, .idle: break
                }
            }
            work?.pending.enter()
            await persist(currentSave)
            work?.pending.leave()
        }
    }

    func waitForTranscriptRetry() async {
        await withCheckedContinuation { continuation in
            transcriptRetryWork.notify(queue: .global()) { continuation.resume() }
        }
    }

    /// Preserve the recording destination captured when dictation began, even
    /// when inference finishes after that meeting has stopped.
    @MainActor
    public func saveDictation(_ segment: TranscriptSegment, meetingSessionID: UUID?) async {
        if let meetingSessionID, meetingSessionID == recordingSessionID, let work = sessionWork {
            work.pending.enter()
            defer { work.pending.leave() }
            await append(segment, sessionID: meetingSessionID, isDictation: true)
        } else {
            await persist(.utterance(UtteranceSave(
                segment: segment, sessionID: meetingSessionID, sessionToCreate: nil, isDictation: true
            )))
        }
    }

    /// Append a Quick Dictation utterance into the unified session timeline.
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
            await saveDictation(segment, meetingSessionID: nil)
            return
        }

        guard let work = sessionWork, !deletingSessionIDs.contains(work.id) else { return }
        work.pending.enter()
        defer { work.pending.leave() }
        await append(segment, sessionID: work.id, isDictation: true)
    }

    /// Delete a stored session and its utterances. Keep the live snapshot until SQLite confirms deletion.
    @MainActor
    public func deleteSession(id: UUID) async -> SessionDeletionOutcome {
        guard !isRetryingTranscriptSaves, !deletingSessionIDs.contains(id) else { return .busy }
        if activeSession?.id == id {
            guard case .idle = lifecycle else { return .recording }
        }

        deletingSessionIDs.insert(id)
        defer { deletingSessionIDs.remove(id) }
        if sessionWork?.id == id {
            await sessionWork?.waitUntilPersisted()
        }

        do {
            guard try await database.deleteSessionAsync(id: id) else { return .notFound }
            for save in Array(failedSaves.values) where save.sessionID == id {
                removeFailedSave(save.id)
            }
            if activeSession?.id == id {
                activeSession = nil
                sessionWork = nil
            }
            return .deleted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Retention: remove empty sessions, protecting an in-progress recording.
    @MainActor
    public func deleteEmptySessions() async throws -> Int {
        try await database.deleteEmptySessionsAsync(includingOpen: true, keeping: sessionWork?.id)
    }

    @MainActor
    func pruneStandaloneDictations(_ retention: EchoSettings.DictationRetention) async throws {
        guard retention != .forever else { return }
        let cutoff = retention.cutoff(at: Date())
        _ = try await database.deleteStandaloneDictationsAsync(olderThan: cutoff)
        for save in Array(failedSaves.values) {
            guard case .utterance(let utterance) = save, utterance.sessionID == nil,
                  !retention.keepsDictation(at: utterance.segment.timestamp) else { continue }
            removeFailedSave(save.id)
        }
    }

    @MainActor
    func clearStandaloneDictationHistory() async throws -> Int {
        let cutoff = Date()
        let removed = try await database.deleteStandaloneDictationsAsync()
        standalonePurgeCutoff = cutoff
        for save in Array(failedSaves.values) {
            guard case .utterance(let utterance) = save, utterance.sessionID == nil,
                  utterance.segment.timestamp < cutoff else { continue }
            removeFailedSave(save.id)
        }
        return removed
    }

    @MainActor
    public func startSession(title: String = "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))") async throws {
        guard case .idle = lifecycle else { return }
        if let id = activeSession?.id, deletingSessionIDs.contains(id) {
            throw DatabaseManager.DatabaseError.executionFailed("The current meeting is being deleted. Try recording again when deletion finishes.")
        }
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
                startupAudio = StartupAudio()
            }
            var captureStarted = false
            do {
                try await startCapture()
                captureStarted = true
                try await database.saveSessionAsync(session).get()
            } catch {
                pipelineLock.withLock {
                    audioSession = nil
                    startupAudio = nil
                    micVAD.reset()
                    systemVAD.reset()
                }
                if captureStarted { await stopCapture() }
                captureError = error.localizedDescription
                lifecycle = .idle
                throw error
            }

            sessionWork = work
            noteIndex.reset(for: session.id)
            activeSession = session
            let startupFailure: (Error, Int)? = pipelineLock.withLock {
                defer { startupAudio = nil }
                guard let startupAudio else { return nil }
                for (segment, reservation) in startupAudio.segments {
                    _ = submit(segment, reservation: reservation, for: work)
                }
                return startupAudio.lastError.map { ($0, startupAudio.rejectedCount) }
            }
            if let (error, count) = startupFailure {
                reportSegmentFailure(error, sessionID: work.id, count: count)
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
        guard let work = sessionWork, !deletingSessionIDs.contains(work.id) else { return activeSession }

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
        guard var metadata = activeSession, metadata.id == work.id else { return nil }
        metadata.endTime = endTime
        metadata.segments = []
        for save in Array(failedSaves.values) {
            guard case .utterance(let utterance) = save, utterance.sessionID == work.id,
                  utterance.sessionToCreate != nil else { continue }
            failedSaves[save.id] = .utterance(UtteranceSave(
                segment: utterance.segment,
                sessionID: work.id,
                sessionToCreate: metadata,
                isDictation: utterance.isDictation
            ))
        }

        await persist(.sessionEnd(metadata))
        guard var session = activeSession, session.id == work.id else { return nil }
        session.endTime = endTime
        activeSession = session
        sessionWork = nil
        return session
    }

    /// Transcribe a segmented chunk and append to the recording's timeline.
    public func processSpeechSegment(track: SpeakerTrack, pcmData: Data, duration: Double) async {
        await enqueueSegment(track: track, pcmData: pcmData, duration: duration)?.value
    }
}
