import AVFoundation
import CoreMedia
import ScreenCaptureKit

public final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var isCapturing = false
    private let stateQueue = DispatchQueue(label: "com.echo.systemaudio.state")
    private let callbackLock = NSLock()
    
    private var _onSystemAudioBuffer: ((CMSampleBuffer) -> Void)?
    private var _onSystemPCMBuffer: ((AVAudioPCMBuffer, Float) -> Void)?
    private var _onSystemVolumeLevel: ((Float) -> Void)?
    private var _onCaptureFailed: ((Error) -> Void)?
    
    public var onSystemAudioBuffer: ((CMSampleBuffer) -> Void)? {
        get { callbackLock.withLock { _onSystemAudioBuffer } }
        set { callbackLock.withLock { _onSystemAudioBuffer = newValue } }
    }

    public var onSystemPCMBuffer: ((AVAudioPCMBuffer, Float) -> Void)? {
        get { callbackLock.withLock { _onSystemPCMBuffer } }
        set { callbackLock.withLock { _onSystemPCMBuffer = newValue } }
    }
    
    public var onSystemVolumeLevel: ((Float) -> Void)? {
        get { callbackLock.withLock { _onSystemVolumeLevel } }
        set { callbackLock.withLock { _onSystemVolumeLevel = newValue } }
    }
    
    public var onCaptureFailed: ((Error) -> Void)? {
        get { callbackLock.withLock { _onCaptureFailed } }
        set { callbackLock.withLock { _onCaptureFailed = newValue } }
    }
    
    public override init() {
        super.init()
    }
    
    public var isActive: Bool {
        return stateQueue.sync { isCapturing }
    }
    
    /// Create optimized audio-only ScreenCaptureKit configuration
    public static func makeAudioConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true // Critical: Prevents echo & feedback
        config.sampleRate = 16000
        config.channelCount = 1
        
        // Minimize video pipeline overhead to zero for pure audio recording
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        return config
    }
    
    /// Start capturing system audio via ScreenCaptureKit
    public func startCapture() async throws {
        AudioBufferConverter.resetConverters()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "EchoAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display found for audio capture."])
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = Self.makeAudioConfiguration()
        
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.echo.systemaudio.samples"))
        
        try await scStream.startCapture()
        
        stateQueue.sync {
            self.stream = scStream
            self.isCapturing = true
        }
    }
    
    public func stopCapture() async throws {
        AudioBufferConverter.resetConverters()
        let activeStream: SCStream? = stateQueue.sync {
            let s = self.stream
            self.stream = nil
            self.isCapturing = false
            return s
        }
        
        if let s = activeStream {
            try await s.stopCapture()
        }
        onSystemVolumeLevel?(0.0)
    }
    
    // MARK: - SCStreamOutput
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid else { return }
        
        onSystemAudioBuffer?(sampleBuffer)
        
        // Single-pass conversion: decode & resample once per incoming CMSampleBuffer.
        // Shares the converted 16kHz mono buffer and calculated RMS without double-advancing the converter.
        if onSystemPCMBuffer != nil || onSystemVolumeLevel != nil {
            if let converted = AudioBufferConverter.pcmBuffer(from: sampleBuffer) {
                let level = AudioBufferConverter.calculateRMS(from: converted)
                onSystemPCMBuffer?(converted, level)
                onSystemVolumeLevel?(level)
            }
        }
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateQueue.sync {
            self.isCapturing = false
        }
        onSystemVolumeLevel?(0.0)
        onCaptureFailed?(error)
    }
}
