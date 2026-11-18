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
    public private(set) var isRecording = false
    
    public var onSegmentReady: ((TaggedAudioSegment) -> Void)?
    public var onDualLevelsUpdated: ((Float, Float) -> Void)?
    
    private let stateQueue = DispatchQueue(label: "com.echo.dualchannel.state")
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
    public func startMeetingCapture() async throws {
        let shouldStart: Bool = stateQueue.sync {
            guard !isRecording else { return false }
            isRecording = true
            return true
        }
        guard shouldStart else { return }
        
        // Start Mic. If the engine cannot start, roll back the recording flag
        // so a later attempt can try again.
        do {
            try hub.retainMicrophone()
        } catch {
            stateQueue.sync { isRecording = false }
            throw error
        }
        
        // System loopback is optional: a missing screen-recording permission
        // should not abort microphone transcription.
        do {
            try await hub.retainSystemAudio()
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
        
        hub.releaseMicrophone()
        await hub.releaseSystemAudio()
        
        onDualLevelsUpdated?(0.0, 0.0)
    }
}
