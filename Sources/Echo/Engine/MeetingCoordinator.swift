import Foundation
import CoreMedia

public final class MeetingCoordinator: ObservableObject, @unchecked Sendable {
    public let dualChannel: DualChannelCoordinator
    public let phononRunner: PhononProcessRunner
    public let micVAD: VoiceActivityDetector
    public let systemVAD: VoiceActivityDetector
    private let database: DatabaseManager
    
    @Published public var activeSession: MeetingSession?
    @Published public var micLevel: Float = 0.0
    @Published public var systemLevel: Float = 0.0
    
    public var onSessionUpdated: ((MeetingSession) -> Void)?
    
    private let sessionQueue = DispatchQueue(label: "com.echo.meeting.session")
    private let tempDir = FileManager.default.temporaryDirectory
    
    /// Guards the audio pipeline flag because the callbacks fire on the audio
    /// and ScreenCaptureKit sample queues, while start/stop happen on the main actor.
    private let pipelineLock = NSLock()
    private var audioPipelineActive = false
    
    public init(
        dualChannel: DualChannelCoordinator = DualChannelCoordinator(),
        phononRunner: PhononProcessRunner = PhononProcessRunner(),
        database: DatabaseManager = .shared
    ) {
        self.dualChannel = dualChannel
        self.phononRunner = phononRunner
        self.database = database
        self.micVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        self.systemVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        
        // Restore recent session and past utterances from local SQLite database
        if var lastSession = database.fetchRecentSessions(limit: 1).first {
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
        dualChannel.micEngine.onAudioBuffer = { [weak self] buffer in
            guard let self = self, self.isAudioPipelineActive else { return }
            guard let pcmData = AudioBufferConverter.int16PCM(from: buffer) else { return }
            let level = AudioBufferConverter.calculateRMS(from: buffer)
            self.micVAD.processChunk(pcmData: pcmData, rmsEnergy: level)
        }
        
        // System loopback: ScreenCaptureKit hands us raw CMSampleBuffers that
        // must be decoded and resampled before the VAD can slice them.
        dualChannel.systemCapture.onSystemAudioBuffer = { [weak self] sampleBuffer in
            guard let self = self, self.isAudioPipelineActive else { return }
            guard let converted = AudioBufferConverter.pcmBuffer(from: sampleBuffer),
                  let pcmData = AudioBufferConverter.int16PCM(from: converted) else {
                return
            }
            let level = AudioBufferConverter.calculateRMS(from: converted)
            self.systemVAD.processChunk(pcmData: pcmData, rmsEnergy: level)
        }
    }
    
    private func setupVADHandlers() {
        dualChannel.onDualLevelsUpdated = { [weak self] mic, sys in
            DispatchQueue.main.async {
                self?.micLevel = mic
                self?.systemLevel = sys
            }
        }
        
        micVAD.onSpeechSegmentCompleted = { [weak self] pcmData, duration in
            Task {
                await self?.processSpeechSegment(track: .you, pcmData: pcmData, duration: duration)
            }
        }
        
        systemVAD.onSpeechSegmentCompleted = { [weak self] pcmData, duration in
            Task {
                await self?.processSpeechSegment(track: .meeting, pcmData: pcmData, duration: duration)
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
            self.objectWillChange.send()
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
            self.objectWillChange.send()
        }
        onSessionUpdated?(session)
        database.saveSession(session)
        
        setAudioPipelineActive(true)
        do {
            try await dualChannel.startMeetingCapture()
        } catch {
            setAudioPipelineActive(false)
            print("  ℹ Audio device capture notice: \(error.localizedDescription)")
        }
    }
    
    /// Stop current meeting session and finalize
    public func stopSession() async -> MeetingSession? {
        // Stop feeding new audio before flushing, so nothing is appended after
        // the flush emits the final segment.
        setAudioPipelineActive(false)
        micVAD.flush()
        systemVAD.flush()
        
        await dualChannel.stopMeetingCapture()
        
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
        let wavData = AudioBufferConverter.packageWAV(pcmData: pcmData, sampleRate: 16000, channels: 1)
        
        let tempFile = tempDir.appendingPathComponent("echo_segment_\(UUID().uuidString).wav")
        do {
            try wavData.write(to: tempFile)
            let (text, _) = try await phononRunner.transcribe(fileURL: tempFile)
            try? FileManager.default.removeItem(at: tempFile)
            
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            // Apply learned word memory & custom vocabulary
            let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
            
            let segment = TranscriptSegment(
                speaker: track,
                timestamp: Date(),
                text: sanitized,
                durationSeconds: duration
            )
            
            await MainActor.run {
                if self.activeSession == nil {
                    self.activeSession = MeetingSession(title: "Echo Meeting Session", startTime: Date())
                }
                self.activeSession?.segments.append(segment)
                self.objectWillChange.send()
                if let s = self.activeSession {
                    self.onSessionUpdated?(s)
                    self.database.saveSession(s)
                    self.database.saveUtterance(segment, sessionId: s.id, isDictation: false)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            print("  ⚠ VAD chunk transcription error: \(error.localizedDescription)")
        }
    }
}
