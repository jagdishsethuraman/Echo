import AVFoundation
import CoreMedia
import Foundation

/// Owns the single microphone engine and system-audio capture shared by
/// dictation and the meeting studio.
///
/// Before this hub existed, `AppCoordinator` and `DualChannelCoordinator` each
/// created an `AudioEngineManager`. Starting a meeting while dictating opened a
/// second `AVAudioEngine` tap on the same input device, and the single-consumer
/// callback properties meant whichever consumer wired last silently replaced
/// the other. The hub fixes both:
///
/// - capture is reference-counted, so overlapping dictation and meeting
///   sessions share one engine and stopping one does not stop the other;
/// - buffers and levels fan out to any number of observers with removable
///   tokens.
public final class AudioHub: @unchecked Sendable {
    public typealias MicBufferObserver = @Sendable (AVAudioPCMBuffer) -> Void
    public typealias MicLevelObserver = @Sendable (Float) -> Void
    public typealias SystemBufferObserver = @Sendable (CMSampleBuffer) -> Void
    public typealias SystemLevelObserver = @Sendable (Float) -> Void
    public typealias AudioErrorObserver = @Sendable (Error) -> Void
    
    public let micEngine: AudioEngineManager
    public let systemCapture: SystemAudioCapture
    
    private let lock = NSLock()
    private var micBufferObservers: [UUID: MicBufferObserver] = [:]
    private var micLevelObservers: [UUID: MicLevelObserver] = [:]
    private var systemBufferObservers: [UUID: SystemBufferObserver] = [:]
    private var systemLevelObservers: [UUID: SystemLevelObserver] = [:]
    private var errorObservers: [UUID: AudioErrorObserver] = [:]
    
    public private(set) var lastError: Error?
    
    private var micRetainCount = 0
    private var systemRetainCount = 0
    
    private var lastMicLevelPublish: TimeInterval = 0
    private var lastSystemLevelPublish: TimeInterval = 0
    
    /// Meters only need to animate at UI speed; 12 Hz keeps the waveform
    /// responsive without invalidating SwiftUI at the audio callback rate.
    private let levelPublishInterval: TimeInterval = 1.0 / 12.0
    
    public init(
        micEngine: AudioEngineManager = AudioEngineManager(),
        systemCapture: SystemAudioCapture = SystemAudioCapture()
    ) {
        self.micEngine = micEngine
        self.systemCapture = systemCapture
        
        micEngine.onAudioBuffer = { [weak self] buffer in
            self?.broadcastMicBuffer(buffer)
        }
        micEngine.onVolumeLevel = { [weak self] level in
            self?.broadcastMicLevel(level)
        }
        systemCapture.onSystemAudioBuffer = { [weak self] sampleBuffer in
            self?.broadcastSystemBuffer(sampleBuffer)
        }
        systemCapture.onSystemVolumeLevel = { [weak self] level in
            self?.broadcastSystemLevel(level)
        }
        systemCapture.onCaptureFailed = { [weak self] error in
            self?.broadcastError(error)
        }
    }
    
    // MARK: - Observer registration
    
    @discardableResult
    public func addMicBufferObserver(_ observer: @escaping MicBufferObserver) -> UUID {
        let token = UUID()
        lock.lock()
        micBufferObservers[token] = observer
        lock.unlock()
        return token
    }
    
    @discardableResult
    public func addMicLevelObserver(_ observer: @escaping MicLevelObserver) -> UUID {
        let token = UUID()
        lock.lock()
        micLevelObservers[token] = observer
        lock.unlock()
        return token
    }
    
    @discardableResult
    public func addSystemBufferObserver(_ observer: @escaping SystemBufferObserver) -> UUID {
        let token = UUID()
        lock.lock()
        systemBufferObservers[token] = observer
        lock.unlock()
        return token
    }
    
    @discardableResult
    public func addSystemLevelObserver(_ observer: @escaping SystemLevelObserver) -> UUID {
        let token = UUID()
        lock.lock()
        systemLevelObservers[token] = observer
        lock.unlock()
        return token
    }
    
    @discardableResult
    public func addErrorObserver(_ observer: @escaping AudioErrorObserver) -> UUID {
        let token = UUID()
        lock.lock()
        errorObservers[token] = observer
        lock.unlock()
        return token
    }
    
    public func removeObserver(_ token: UUID) {
        lock.lock()
        micBufferObservers.removeValue(forKey: token)
        micLevelObservers.removeValue(forKey: token)
        systemBufferObservers.removeValue(forKey: token)
        systemLevelObservers.removeValue(forKey: token)
        errorObservers.removeValue(forKey: token)
        lock.unlock()
    }
    
    // MARK: - Reference-counted capture
    
    /// Retain microphone capture. Starts the engine on the first retention.
    public func retainMicrophone() throws {
        let shouldStart = bumpMicRetainCount()
        guard shouldStart else { return }
        
        do {
            try micEngine.startCapture()
        } catch {
            _ = dropMicRetainCount()
            throw error
        }
    }
    
    /// Release microphone capture. Stops the engine when the last user leaves.
    public func releaseMicrophone() {
        guard dropMicRetainCount() else { return }
        micEngine.stopCapture()
    }
    
    /// Retain system-audio loopback. Starts ScreenCaptureKit on the first
    /// retention. System audio is optional, so callers may log and continue.
    public func retainSystemAudio() async throws {
        let shouldStart = bumpSystemRetainCount()
        guard shouldStart else { return }
        
        do {
            try await systemCapture.startCapture()
        } catch {
            _ = dropSystemRetainCount()
            throw error
        }
    }
    
    /// Release system-audio loopback. Stops the stream when the last user
    /// leaves.
    public func releaseSystemAudio() async {
        guard dropSystemRetainCount() else { return }
        try? await systemCapture.stopCapture()
    }
    
    // MARK: - Fan-out
    
    /// Internal so tests can exercise fan-out without opening a real device.
    func broadcastMicBuffer(_ buffer: AVAudioPCMBuffer) {
        let observers = snapshotMicBufferObservers()
        for observer in observers {
            observer(buffer)
        }
    }
    
    func broadcastMicLevel(_ level: Float) {
        guard shouldPublishLevel(level, channel: .microphone) else { return }
        let observers = snapshotMicLevelObservers()
        for observer in observers {
            observer(level)
        }
    }
    
    func broadcastSystemBuffer(_ sampleBuffer: CMSampleBuffer) {
        let observers = snapshotSystemBufferObservers()
        for observer in observers {
            observer(sampleBuffer)
        }
    }
    
    func broadcastSystemLevel(_ level: Float) {
        guard shouldPublishLevel(level, channel: .system) else { return }
        let observers = snapshotSystemLevelObservers()
        for observer in observers {
            observer(level)
        }
    }
    
    func broadcastError(_ error: Error) {
        lock.lock()
        self.lastError = error
        lock.unlock()
        let observers = snapshotErrorObservers()
        for observer in observers {
            observer(error)
        }
    }
    
    // MARK: - Lock-protected state
    
    private func bumpMicRetainCount() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        micRetainCount += 1
        return micRetainCount == 1
    }
    
    private func dropMicRetainCount() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        micRetainCount = max(0, micRetainCount - 1)
        return micRetainCount == 0
    }
    
    private func bumpSystemRetainCount() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        systemRetainCount += 1
        return systemRetainCount == 1
    }
    
    private func dropSystemRetainCount() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        systemRetainCount = max(0, systemRetainCount - 1)
        return systemRetainCount == 0
    }
    
    private func snapshotMicBufferObservers() -> [MicBufferObserver] {
        lock.lock()
        defer { lock.unlock() }
        return Array(micBufferObservers.values)
    }
    
    private func snapshotMicLevelObservers() -> [MicLevelObserver] {
        lock.lock()
        defer { lock.unlock() }
        return Array(micLevelObservers.values)
    }
    
    private func snapshotSystemBufferObservers() -> [SystemBufferObserver] {
        lock.lock()
        defer { lock.unlock() }
        return Array(systemBufferObservers.values)
    }
    
    private func snapshotSystemLevelObservers() -> [SystemLevelObserver] {
        lock.lock()
        defer { lock.unlock() }
        return Array(systemLevelObservers.values)
    }
    
    private func snapshotErrorObservers() -> [AudioErrorObserver] {
        lock.lock()
        defer { lock.unlock() }
        return Array(errorObservers.values)
    }
    
    /// Returns `true` when the level should be delivered. Zero is always
    /// delivered so meters snap back to rest even inside a throttle window.
    private enum LevelChannel {
        case microphone
        case system
    }
    
    private func shouldPublishLevel(_ level: Float, channel: LevelChannel) -> Bool {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        
        let lastPublish: TimeInterval
        switch channel {
        case .microphone: lastPublish = lastMicLevelPublish
        case .system: lastPublish = lastSystemLevelPublish
        }
        
        guard level == 0 || now - lastPublish >= levelPublishInterval else {
            return false
        }
        
        switch channel {
        case .microphone: lastMicLevelPublish = now
        case .system: lastSystemLevelPublish = now
        }
        return true
    }
}
