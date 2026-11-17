import AVFoundation

public final class AudioEngineManager: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var isRecording = false
    private let stateQueue = DispatchQueue(label: "com.echo.audioengine.state")
    
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?
    
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    public var onVolumeLevel: ((Float) -> Void)?
    
    public init() {}
    
    public var isRunning: Bool {
        return stateQueue.sync { isRecording && engine.isRunning }
    }
    
    /// Start microphone audio capture with automatic 16kHz mono conversion
    public func startCapture() throws {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !isRecording else { return false }
            isRecording = true
            return true
        }
        guard shouldStart else { return }
        
        let inputNode = engine.inputNode
        
        // Target format for Phonon-2 speech engine (16kHz mono Float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "EchoAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target 16kHz format."])
        }
        
        inputNode.removeTap(onBus: 0)
        // Passing format: nil automatically adopts the node's native bus format, eliminating format mismatch crashes
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let level = AudioBufferConverter.calculateRMS(from: buffer)
            self.onVolumeLevel?(level)
            
            let bufferFormat = buffer.format
            if bufferFormat == targetFormat {
                self.onAudioBuffer?(buffer)
            } else {
                if self.converter == nil || self.converterSourceFormat != bufferFormat {
                    self.converter = AVAudioConverter(from: bufferFormat, to: targetFormat)
                    self.converterSourceFormat = bufferFormat
                }
                
                guard let conv = self.converter else { return }
                let ratio = 16000.0 / bufferFormat.sampleRate
                let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                
                if frameCapacity > 0, let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) {
                    var error: NSError?
                    var haveData = true
                    conv.convert(to: converted, error: &error) { _, outStatus in
                        if haveData {
                            haveData = false
                            outStatus.pointee = .haveData
                            return buffer
                        } else {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                    }
                    if error == nil && converted.frameLength > 0 {
                        self.onAudioBuffer?(converted)
                    }
                }
            }
        }
        
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            stateQueue.sync { isRecording = false }
            throw error
        }
    }
    
    public func stopCapture() {
        let shouldStop = stateQueue.sync { () -> Bool in
            guard isRecording else { return false }
            isRecording = false
            return true
        }
        guard shouldStop else { return }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onVolumeLevel?(0.0)
    }
}
