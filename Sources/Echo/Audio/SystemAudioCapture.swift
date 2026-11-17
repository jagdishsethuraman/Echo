import AVFoundation
import CoreMedia
import ScreenCaptureKit

public final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var isCapturing = false
    private let stateQueue = DispatchQueue(label: "com.echo.systemaudio.state")
    
    public var onSystemAudioBuffer: ((CMSampleBuffer) -> Void)?
    public var onSystemVolumeLevel: ((Float) -> Void)?
    
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
        
        // Approximate VU energy from audio sample buffer
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let length = CMBlockBufferGetDataLength(blockBuffer)
            if length > 0 {
                var dataPointer: UnsafeMutablePointer<Int8>?
                if CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &dataPointer) == noErr,
                   let pointer = dataPointer {
                    let samples = pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { $0 }
                    let count = length / 2
                    var sum: Float = 0
                    for i in 0..<min(count, 512) {
                        let f = Float(samples[i]) / 32768.0
                        sum += f * f
                    }
                    let rms = sqrt(sum / Float(min(count, 512)))
                    onSystemVolumeLevel?(min(1.0, rms * 4.0))
                }
            }
        }
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateQueue.sync {
            self.isCapturing = false
        }
    }
}
