import Foundation

public final class MeetingCoordinator: ObservableObject, @unchecked Sendable {
    public let dualChannel: DualChannelCoordinator
    public let phononRunner: PhononProcessRunner
    public let micVAD: VoiceActivityDetector
    public let systemVAD: VoiceActivityDetector
    
    @Published public var activeSession: MeetingSession?
    @Published public var micLevel: Float = 0.0
    @Published public var systemLevel: Float = 0.0
    
    public var onSessionUpdated: ((MeetingSession) -> Void)?
    
    private let sessionQueue = DispatchQueue(label: "com.echo.meeting.session")
    private let tempDir = FileManager.default.temporaryDirectory
    
    public init(
        dualChannel: DualChannelCoordinator = DualChannelCoordinator(),
        phononRunner: PhononProcessRunner = PhononProcessRunner()
    ) {
        self.dualChannel = dualChannel
        self.phononRunner = phononRunner
        self.micVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        self.systemVAD = VoiceActivityDetector(energyThreshold: 0.08, silenceThresholdSeconds: 0.6)
        
        let initialSession = MeetingSession(title: "Echo Speech Stream", startTime: Date())
        self.activeSession = initialSession
        
        setupVADHandlers()
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
    
    /// Append a completed Quick Dictation utterance into the unified session timeline
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
        
        do {
            try await dualChannel.startMeetingCapture()
        } catch {
            print("  ℹ Audio device capture notice: \(error.localizedDescription)")
        }
    }
    
    /// Stop current meeting session and finalize
    public func stopSession() async -> MeetingSession? {
        micVAD.flush()
        systemVAD.flush()
        
        await dualChannel.stopMeetingCapture()
        
        return await MainActor.run {
            guard var session = self.activeSession else { return nil }
            session.endTime = Date()
            self.activeSession = session
            self.objectWillChange.send()
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
            
            let segment = TranscriptSegment(
                speaker: track,
                timestamp: Date(),
                text: trimmed,
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
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            print("  ⚠ VAD chunk transcription error: \(error.localizedDescription)")
        }
    }
}
