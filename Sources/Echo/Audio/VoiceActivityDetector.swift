import Foundation

public final class VoiceActivityDetector: @unchecked Sendable {
    public let energyThreshold: Float
    public let silenceThresholdSeconds: Double
    public let minSpeechDurationSeconds: Double
    public let maxSpeechDurationSeconds: Double
    public let sampleRate: Int
    
    private var speechBuffer = Data()
    private var silenceFramesCount: Int = 0
    private var isSpeaking = false
    private let lock = NSLock()
    
    public var onSpeechSegmentCompleted: ((Data, Double) -> Void)?
    
    public init(
        energyThreshold: Float = 0.08,
        silenceThresholdSeconds: Double = 0.6,
        minSpeechDurationSeconds: Double = 0.4,
        maxSpeechDurationSeconds: Double = 15.0,
        sampleRate: Int = 16000
    ) {
        self.energyThreshold = energyThreshold
        self.silenceThresholdSeconds = silenceThresholdSeconds
        self.minSpeechDurationSeconds = minSpeechDurationSeconds
        self.maxSpeechDurationSeconds = maxSpeechDurationSeconds
        self.sampleRate = sampleRate
    }
    
    /// Process incoming 16kHz Int16 mono PCM chunk
    public func processChunk(pcmData: Data, rmsEnergy: Float) {
        lock.lock()
        defer { lock.unlock() }
        
        let bytesPerSample = 2 // 16-bit
        let chunkDuration = Double(pcmData.count / bytesPerSample) / Double(sampleRate)
        
        if rmsEnergy >= energyThreshold {
            // Speech detected
            if !isSpeaking {
                isSpeaking = true
            }
            speechBuffer.append(pcmData)
            silenceFramesCount = 0
            
            // Check if buffer exceeded max duration
            let currentDuration = Double(speechBuffer.count / bytesPerSample) / Double(sampleRate)
            if currentDuration >= maxSpeechDurationSeconds {
                flushCurrentSegment()
            }
        } else {
            // Silence frame
            if isSpeaking {
                speechBuffer.append(pcmData)
                let silenceFrameTime = chunkDuration
                let requiredSilenceFrames = Int(silenceThresholdSeconds / max(silenceFrameTime, 0.01))
                silenceFramesCount += 1
                
                if silenceFramesCount >= requiredSilenceFrames {
                    flushCurrentSegment()
                }
            }
        }
    }
    
    /// Force flush any active speech buffer (e.g. when meeting ends)
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        flushCurrentSegment()
    }
    
    private func flushCurrentSegment() {
        guard !speechBuffer.isEmpty else {
            isSpeaking = false
            silenceFramesCount = 0
            return
        }
        
        let bytesPerSample = 2
        let duration = Double(speechBuffer.count / bytesPerSample) / Double(sampleRate)
        
        if duration >= minSpeechDurationSeconds {
            let completedData = speechBuffer
            speechBuffer = Data()
            isSpeaking = false
            silenceFramesCount = 0
            
            // Dispatch outside lock
            let callback = self.onSpeechSegmentCompleted
            DispatchQueue.global(qos: .userInitiated).async {
                callback?(completedData, duration)
            }
        } else {
            // Below minimum duration (noise pop) - discard
            speechBuffer = Data()
            isSpeaking = false
            silenceFramesCount = 0
        }
    }
}
