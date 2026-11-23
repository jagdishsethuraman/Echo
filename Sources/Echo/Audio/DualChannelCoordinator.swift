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

/// Meeting-side view of the shared `AudioHub`.
///
/// The coordinator no longer owns an audio engine of its own; retaining the hub
/// lets dictation and meeting capture coexist without a second tap on the
/// microphone.
public final class DualChannelCoordinator: @unchecked Sendable {
    public let hub: AudioHub
    public var micEngine: AudioEngineManager { hub.micEngine }
    public var systemCapture: SystemAudioCapture { hub.systemCapture }
    
    public private(set) var micLevel: Float = 0.0
    public private(set) var systemLevel: Float = 0.0
    @MainActor public private(set) var isRecording = false
    
    public var onSegmentReady: ((TaggedAudioSegment) -> Void)?
    public var onDualLevelsUpdated: ((Float, Float) -> Void)?
    
    private let stateQueue = DispatchQueue(label: "com.echo.dualchannel.state")
    @MainActor private var systemRetention: Task<Bool, Never>?
    private var micLevelToken: UUID?
    private var systemLevelToken: UUID?
    
    public init(hub: AudioHub = AudioHub()) {
        self.hub = hub
        setupCallbacks()
    }
    
    deinit {
        if let micLevelToken { hub.removeObserver(micLevelToken) }
        if let systemLevelToken { hub.removeObserver(systemLevelToken) }
    }
    
    private func setupCallbacks() {
        micLevelToken = hub.addMicLevelObserver { [weak self] level in
            guard let self = self else { return }
            let sLevel = self.stateQueue.sync { () -> Float in
                self.micLevel = level
                return self.systemLevel
            }
            self.onDualLevelsUpdated?(level, sLevel)
        }
        
        systemLevelToken = hub.addSystemLevelObserver { [weak self] level in
            guard let self = self else { return }
            let mLevel = self.stateQueue.sync { () -> Float in
                self.systemLevel = level
                return self.micLevel
            }
            self.onDualLevelsUpdated?(mLevel, level)
        }
    }
    
    /// Start dual-channel meeting audio capture
    @MainActor
    public func startMeetingCapture() async throws {
        if let systemRetention {
            _ = await systemRetention.value
            return
        }
        try hub.retainMicrophone()
        isRecording = true

        // System loopback is optional: a missing screen-recording permission
        // should not abort microphone transcription.
        let retention = Task {
            do {
                try await hub.retainSystemAudio()
                return true
            } catch {
                print("System audio capture notice: \(error.localizedDescription)")
                return false
            }
        }
        systemRetention = retention
        _ = await retention.value
    }
    
    /// Stop meeting capture
    @MainActor
    public func stopMeetingCapture() async {
        guard let systemRetention else { return }
        self.systemRetention = nil
        isRecording = false
        stateQueue.sync {
            micLevel = 0.0
            systemLevel = 0.0
        }
        
        hub.releaseMicrophone()
        if await systemRetention.value {
            await hub.releaseSystemAudio()
        }

        if !isRecording { onDualLevelsUpdated?(0.0, 0.0) }
    }
}
