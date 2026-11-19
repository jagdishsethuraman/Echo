import Foundation

public final class VoiceActivityDetector: @unchecked Sendable {
    public let energyThreshold: Float
    public let silenceThresholdSeconds: Double
    public let minSpeechDurationSeconds: Double
    public let maxSpeechDurationSeconds: Double
    public let preRollSeconds: Double
    public let sampleRate: Int
    
    private var speechBuffer = Data()
    private var preRollBuffer = Data()
    private var silenceFramesCount: Int = 0
    private var isSpeaking = false
    private var speechStartTime: Date?
    private let lock = NSLock()
    
    /// Called synchronously on the thread that detected the segment boundary.
    /// Consumers that need to do expensive work should hand it off themselves.
    public var onSpeechSegmentCompleted: ((Data, Double) -> Void)?
    /// Includes the capture onset timestamp recorded when speech first crossed threshold.
    public var onSpeechSegmentWithTimestampCompleted: ((Data, Double, Date) -> Void)?
    
    public init(
        energyThreshold: Float = 0.08,
        silenceThresholdSeconds: Double = 0.6,
        minSpeechDurationSeconds: Double = 0.4,
        maxSpeechDurationSeconds: Double = 15.0,
        preRollSeconds: Double = 0.3,
        sampleRate: Int = 16000
    ) {
        self.energyThreshold = energyThreshold
        self.silenceThresholdSeconds = silenceThresholdSeconds
        self.minSpeechDurationSeconds = minSpeechDurationSeconds
        self.maxSpeechDurationSeconds = maxSpeechDurationSeconds
        self.preRollSeconds = preRollSeconds
        self.sampleRate = sampleRate
    }
    
    /// Process incoming 16kHz Int16 mono PCM chunk
    public func processChunk(pcmData: Data, rmsEnergy: Float) {
        var completed: (Data, Double, Date)?
        
        lock.lock()
        if rmsEnergy >= energyThreshold {
            // Speech detected. Prepend the pre-roll so the first phoneme of the
            // utterance is not clipped.
            if !isSpeaking {
                isSpeaking = true
                let preRollDuration = Double(preRollBuffer.count / 2) / Double(sampleRate)
                speechStartTime = Date().addingTimeInterval(-preRollDuration)
                speechBuffer = preRollBuffer
                preRollBuffer.removeAll(keepingCapacity: true)
            }
            speechBuffer.append(pcmData)
            silenceFramesCount = 0
            
            // Check if buffer exceeded max duration
            let currentDuration = Double(speechBuffer.count / 2) / Double(sampleRate)
            if currentDuration >= maxSpeechDurationSeconds {
                completed = takeSegmentLocked()
            }
        } else if isSpeaking {
            // Trailing silence stays part of the segment until the threshold is
            // reached, which keeps the natural pause at the end of a sentence.
            speechBuffer.append(pcmData)
            let chunkDuration = Double(pcmData.count / 2) / Double(sampleRate)
            let requiredSilenceFrames = Int(silenceThresholdSeconds / max(chunkDuration, 0.01))
            silenceFramesCount += 1
            
            if silenceFramesCount >= requiredSilenceFrames {
                completed = takeSegmentLocked()
            }
        } else {
            // Keep a rolling tail of silence ready for the next utterance.
            if preRollSeconds > 0 {
                preRollBuffer.append(pcmData)
                let maxPreRollBytes = Int(preRollSeconds * Double(sampleRate)) * 2
                if preRollBuffer.count > maxPreRollBytes {
                    preRollBuffer.removeFirst(preRollBuffer.count - maxPreRollBytes)
                }
            }
        }
        lock.unlock()
        
        // Deliver outside the lock so consumers can call back into the detector.
        if let completed {
            onSpeechSegmentCompleted?(completed.0, completed.1)
            onSpeechSegmentWithTimestampCompleted?(completed.0, completed.1, completed.2)
        }
    }
    
    /// Force flush any active speech buffer (e.g. when meeting ends)
    public func flush() {
        var completed: (Data, Double, Date)?
        
        lock.lock()
        completed = takeSegmentLocked()
        lock.unlock()
        
        if let completed {
            onSpeechSegmentCompleted?(completed.0, completed.1)
            onSpeechSegmentWithTimestampCompleted?(completed.0, completed.1, completed.2)
        }
    }
    
    /// Reset the detector without emitting a segment.
    public func reset() {
        lock.lock()
        speechBuffer.removeAll(keepingCapacity: true)
        preRollBuffer.removeAll(keepingCapacity: true)
        silenceFramesCount = 0
        isSpeaking = false
        speechStartTime = nil
        lock.unlock()
    }
    
    /// Finish the current segment. Must be called with `lock` held.
    private func takeSegmentLocked() -> (Data, Double, Date)? {
        guard !speechBuffer.isEmpty else {
            isSpeaking = false
            silenceFramesCount = 0
            speechStartTime = nil
            return nil
        }
        
        let duration = Double(speechBuffer.count / 2) / Double(sampleRate)
        let completedData = speechBuffer
        let timestamp = speechStartTime ?? Date()
        speechBuffer.removeAll(keepingCapacity: true)
        isSpeaking = false
        silenceFramesCount = 0
        speechStartTime = nil
        
        // Below minimum duration (noise pop) - discard.
        guard duration >= minSpeechDurationSeconds else { return nil }
        return (completedData, duration, timestamp)
    }
}
