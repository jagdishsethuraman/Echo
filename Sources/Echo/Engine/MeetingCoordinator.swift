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
    
    @Published public var activeSession: MeetingSession?
    public let audioLevels = MeetingAudioLevels()
    @Published public var captureError: String? = nil
    
    /// Backward-compatibility forwarding properties (not published to avoid invalidating parent views)
    public var micLevel: Float { audioLevels.micLevel }
    public var systemLevel: Float { audioLevels.systemLevel }
    
    private let callbackLock = NSLock()
    private var _onSessionUpdated: ((MeetingSession) -> Void)?
    
    public var onSessionUpdated: ((MeetingSession) -> Void)? {
        get { callbackLock.withLock { _onSessionUpdated } }
        set { callbackLock.withLock { _onSessionUpdated = newValue } }
    }
    
    private let sessionQueue = DispatchQueue(label: "com.echo.meeting.session")
    
    /// Guards the audio pipeline flag because the callbacks fire on the audio
    /// and ScreenCaptureKit sample queues, while start/stop happen on the main actor.
    private let pipelineLock = NSLock()
    private var audioPipelineActive = false
    private var micBufferToken: UUID?
    private var systemBufferToken: UUID?
    private var audioErrorToken: UUID?
    
    public init(
        dualChannel: DualChannelCoordinator = DualChannelCoordinator(),
        phononRunner: PhononProcessRunner = PhononProcessRunner(),
        database: DatabaseManager = .shared,
        transcriptionService: TranscriptionService? = nil
    ) {
        self.dualChannel = dualChannel
        self.phononRunner = phononRunner
        self.database = database
        self.transcriptionService = transcriptionService
            ?? TranscriptionService(runner: phononRunner)
        self.micVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        self.systemVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        
        // Restore recent session and past utterances from local SQLite database
        // ONLY if the session was actively open (endTime == nil). Closed
        // sessions from past meetings should not be revived as the active recording stream.
        if var lastSession = database.fetchRecentSessions(limit: 1).first, lastSession.endTime == nil {
            lastSession.segments = database.fetchUtterances(sessionId: lastSession.id)
            self.activeSession = lastSession
        } else {
            let initialSession = MeetingSession(title: "Echo Speech Stream", startTime: Date())
            self.activeSession = initialSession
            database.saveSession(initialSession)
        }
        
        setupVADHandlers()
        setupAudioPipelines()
    }
    
    private var isAudioPipelineActive: Bool {
        pipelineLock.lock()
        defer { pipelineLock.unlock() }
        return audioPipelineActive
    }
    
    private func setAudioPipelineActive(_ active: Bool) {
        pipelineLock.lock()
        audioPipelineActive = active
        pipelineLock.unlock()
    }
    
    /// Feed the two VADs with canonical 16 kHz mono Int16 PCM.
    private func setupAudioPipelines() {
        // Microphone: `AudioEngineManager` already delivers 16 kHz mono Float32.
        micBufferToken = dualChannel.hub.addMicBufferObserver { [weak self] buffer in
            guard let self = self, self.isAudioPipelineActive else { return }
            guard let pcmData = AudioBufferConverter.int16PCM(from: buffer) else { return }
            let level = AudioBufferConverter.calculateRMS(from: buffer)
            self.micVAD.processChunk(pcmData: pcmData, rmsEnergy: level)
        }
        
        // System loopback: ScreenCaptureKit hands us raw CMSampleBuffers that
        // must be decoded and resampled before the VAD can slice them.
        systemBufferToken = dualChannel.hub.addSystemBufferObserver { [weak self] sampleBuffer in
            guard let self = self, self.isAudioPipelineActive else { return }
            guard let converted = AudioBufferConverter.pcmBuffer(from: sampleBuffer),
                  let pcmData = AudioBufferConverter.int16PCM(from: converted) else {
                return
            }
            let level = AudioBufferConverter.calculateRMS(from: converted)
            self.systemVAD.processChunk(pcmData: pcmData, rmsEnergy: level)
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
    
    /// Register a VAD segment with the bounded transcription queue.
    ///
    /// The segment callback is synchronous, so `stopSession()` can be sure the
    /// final utterance is already counted before it waits for the queue to
    /// drain.
    func enqueueSegment(track: SpeakerTrack, pcmData: Data, duration: Double) {
        transcriptionService.submit(pcmData: pcmData) { [weak self] text in
            guard let self, let text, !text.isEmpty else { return }
            let sanitized = WordMemoryEngine.shared.sanitize(text)
            await self.appendTranscribedSegment(track: track, text: sanitized, duration: duration)
        }
    }
    
    private func appendTranscribedSegment(track: SpeakerTrack, text: String, duration: Double) async {
        let segment = TranscriptSegment(
            speaker: track,
            timestamp: Date(),
            text: text,
            durationSeconds: duration
        )
        
        await MainActor.run {
            if self.activeSession == nil {
                self.activeSession = MeetingSession(title: "Echo Meeting Session", startTime: Date())
            }
            self.activeSession?.segments.append(segment)
            if let s = self.activeSession {
                self.onSessionUpdated?(s)
                self.database.saveSession(s)
                self.database.saveUtterance(segment, sessionId: s.id, isDictation: false)
            }
        }
    }
    
    /// Append a completed Quick Dictation utterance into the unified session timeline & SQLite
    public func appendDictation(text: String, duration: Double = 1.0) {
        let segment = TranscriptSegment(
            speaker: .you,
            timestamp: Date(),
            text: text,
            durationSeconds: duration
        )
        
        let performAppend = {
            if self.activeSession == nil {
                self.activeSession = MeetingSession(title: "Echo Speech Stream", startTime: Date())
            }
            self.activeSession?.segments.append(segment)
            if let s = self.activeSession {
                self.onSessionUpdated?(s)
                // Persist to local SQLite backend
                self.database.saveSession(s)
                self.database.saveUtterance(segment, sessionId: s.id, isDictation: true)
            }
        }
        
        if Thread.isMainThread {
            performAppend()
        } else {
            DispatchQueue.main.async(execute: performAppend)
        }
    }
    
    /// Start a new meeting session
    public func startSession(title: String = "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))") async throws {
        let session = MeetingSession(title: title, startTime: Date())
        await MainActor.run {
            self.activeSession = session
            self.captureError = nil
        }
        onSessionUpdated?(session)
        database.saveSession(session)
        
        setAudioPipelineActive(true)
        do {
            try await dualChannel.startMeetingCapture()
        } catch {
            setAudioPipelineActive(false)
            await MainActor.run {
                self.captureError = error.localizedDescription
            }
            print("  ℹ Audio device capture notice: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Stop current meeting session and finalize
    public func stopSession() async -> MeetingSession? {
        // Stop feeding new audio before flushing, so nothing is appended after
        // the flush emits the final segment. `flush()` delivers its callback
        // synchronously, which registers the final segment with the queue.
        setAudioPipelineActive(false)
        micVAD.flush()
        systemVAD.flush()
        
        await dualChannel.stopMeetingCapture()
        
        // Wait for the final utterances to be transcribed and appended before
        // writing `endTime` or exporting the session.
        let drained = await transcriptionService.waitUntilIdle(timeout: 5)
        if !drained {
            print("  ⚠ Meeting stopped with transcriptions still in flight")
        }
        
        return await MainActor.run {
            guard var session = self.activeSession else { return nil }
            session.endTime = Date()
            self.activeSession = session
            self.objectWillChange.send()
            database.saveSession(session)
            return session
        }
    }
    
    /// Transcribe a segmented chunk and append to session timeline
    public func processSpeechSegment(track: SpeakerTrack, pcmData: Data, duration: Double) async {
        do {
            let text = try await transcriptionService.transcribe(pcmData: pcmData)
            guard !text.isEmpty else { return }
            
            // Apply learned word memory & custom vocabulary
            let sanitized = WordMemoryEngine.shared.sanitize(text)
            await appendTranscribedSegment(track: track, text: sanitized, duration: duration)
        } catch {
            print("  ⚠ VAD chunk transcription error: \(error.localizedDescription)")
        }
    }
}
