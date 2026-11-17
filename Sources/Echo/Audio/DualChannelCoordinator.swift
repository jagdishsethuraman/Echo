import AVFoundation
import Foundation

public enum SpeakerTrack: String, Codable, Sendable {
    case you = "You"
    case meeting = "Meeting Attendees"
}

public struct TaggedAudioSegment: Sendable {
    public let track: SpeakerTrack
    public let timestamp: Date
    public let pcmData: Data
    public let durationSeconds: Double
    
    public init(track: SpeakerTrack, timestamp: Date = Date(), pcmData: Data, durationSeconds: Double) {
        self.track = track
        self.timestamp = timestamp
        self.pcmData = pcmData
        self.durationSeconds = durationSeconds
    }
    
    /// Package raw PCM data into a 16kHz mono WAV file payload
    public var wavData: Data {
        AudioBufferConverter.packageWAV(pcmData: pcmData, sampleRate: 16000, channels: 1)
    }
}

public final class DualChannelCoordinator: @unchecked Sendable {
    public let micEngine: AudioEngineManager
    public let systemCapture: SystemAudioCapture
    
    public private(set) var micLevel: Float = 0.0
    public private(set) var systemLevel: Float = 0.0
    public private(set) var isRecording = false
    
    public var onSegmentReady: ((TaggedAudioSegment) -> Void)?
    public var onDualLevelsUpdated: ((Float, Float) -> Void)?
    
    private let stateQueue = DispatchQueue(label: "com.echo.dualchannel.state")
    
    public init(
        micEngine: AudioEngineManager = AudioEngineManager(),
        systemCapture: SystemAudioCapture = SystemAudioCapture()
    ) {
        self.micEngine = micEngine
        self.systemCapture = systemCapture
        
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        micEngine.onVolumeLevel = { [weak self] level in
            guard let self = self else { return }
            let sLevel = self.stateQueue.sync { () -> Float in
                self.micLevel = level
                return self.systemLevel
            }
            self.onDualLevelsUpdated?(level, sLevel)
        }
        
        systemCapture.onSystemVolumeLevel = { [weak self] level in
            guard let self = self else { return }
            let mLevel = self.stateQueue.sync { () -> Float in
                self.systemLevel = level
                return self.micLevel
            }
            self.onDualLevelsUpdated?(mLevel, level)
        }
    }
    
    /// Start dual-channel meeting audio capture
    public func startMeetingCapture() async throws {
        let shouldStart: Bool = stateQueue.sync {
            guard !isRecording else { return false }
            isRecording = true
            return true
        }
        guard shouldStart else { return }
        
        // Start Mic
        try micEngine.startCapture()
        
        // Start System Loopback
        do {
            try await systemCapture.startCapture()
        } catch {
            print("System audio capture notice: \(error.localizedDescription)")
        }
    }
    
    /// Stop meeting capture
    public func stopMeetingCapture() async {
        let shouldStop: Bool = stateQueue.sync {
            guard isRecording else { return false }
            isRecording = false
            micLevel = 0.0
            systemLevel = 0.0
            return true
        }
        guard shouldStop else { return }
        
        micEngine.stopCapture()
        try? await systemCapture.stopCapture()
        
        onDualLevelsUpdated?(0.0, 0.0)
    }
}
