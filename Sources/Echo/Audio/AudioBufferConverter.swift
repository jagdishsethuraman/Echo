import AVFoundation
import CoreMedia
import Foundation

public enum AudioBufferConverter {
    
    /// Calculate Root-Mean-Square (RMS) volume level normalized between 0.0 and 1.0
    public static func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }
        
        var sum: Float = 0.0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let sample = data[frame]
                sum += sample * sample
            }
        }
        
        let mean = sum / Float(frameLength * channelCount)
        let rms = sqrt(mean)
        // Scale logarithmically to a readable 0.0 - 1.0 range
        let db = 20.0 * log10(max(rms, 0.0001))
        let normalized = max(0.0, min(1.0, (db + 50.0) / 50.0))
        return normalized
    }
    
    /// Convert raw 16kHz 16-bit Int16 PCM data into standard canonical WAV container data
    public static func createWAVHeader(dataLength: Int, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        var header = Data()
        
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let totalChunkSize = 36 + dataLength
        
        // "RIFF" chunk descriptor
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(totalChunkSize).littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // "fmt " sub-chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Subchunk1Size (16 for PCM)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // AudioFormat (1 for PCM)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        
        // "data" sub-chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataLength).littleEndian) { Array($0) })
        
        return header
    }
    
    /// Package raw 16kHz Int16 PCM bytes with standard RIFF WAV header
    public static func packageWAV(pcmData: Data, sampleRate: Int = 16000, channels: Int = 1) -> Data {
        let header = createWAVHeader(dataLength: pcmData.count, sampleRate: sampleRate, channels: channels, bitsPerSample: 16)
        var wav = Data()
        wav.reserveCapacity(header.count + pcmData.count)
        wav.append(header)
        wav.append(pcmData)
        return wav
    }
    
    // MARK: - Pipeline Conversion
    
    /// Canonical format expected by the VAD and the speech engine.
    private static var canonicalFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
    }
    
    /// Resample/downmix any PCM buffer to canonical 16 kHz mono Float32.
    ///
    /// A single `AVAudioConverter` is reused per source format: sample-rate
    /// conversion is stateful, and creating a fresh converter per buffer drops
    /// its internal filter tail (roughly 15 ms of audio each time).
    public static func resampleTo16kMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let targetFormat = canonicalFormat else { return nil }
        if buffer.format == targetFormat { return buffer }
        
        converterLock.lock()
        defer { converterLock.unlock() }
        
        let key = "\(buffer.format.sampleRate)|\(buffer.format.channelCount)|\(buffer.format.isInterleaved ? 1 : 0)|\(buffer.format.commonFormat.rawValue)"
        let converter: AVAudioConverter
        
        if let cached = converters[key] {
            converter = cached
        } else {
            guard let created = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
            converters[key] = created
            converter = created
        }
        
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        // Extra headroom for samples the converter may have retained from the
        // previous buffer.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 256
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }
        
        var error: NSError?
        var suppliedInput = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
    
    private static let converterLock = NSLock()
    private static var converters: [String: AVAudioConverter] = [:]
    
    /// Convert a Float32 PCM buffer into little-endian 16-bit PCM bytes.
    public static func int16PCM(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }
        
        let channelCount = Int(buffer.format.channelCount)
        var data = Data(count: frameCount * MemoryLayout<Int16>.size)
        
        data.withUnsafeMutableBytes { rawBuffer in
            guard let samples = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            
            if channelCount == 1 {
                let source = channelData[0]
                for frame in 0..<frameCount {
                    samples[frame] = clampedInt16(source[frame])
                }
            } else {
                // Downmix by averaging all channels into mono.
                for frame in 0..<frameCount {
                    var sum: Float = 0
                    for channel in 0..<channelCount {
                        sum += channelData[channel][frame]
                    }
                    samples[frame] = clampedInt16(sum / Float(channelCount))
                }
            }
        }
        
        return data
    }
    
    /// Decode a ScreenCaptureKit audio `CMSampleBuffer` into canonical 16 kHz mono Float32.
    public static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return nil }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        
        var asbd = asbdPointer.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr, buffer.frameLength > 0 else { return nil }
        
        return resampleTo16kMono(buffer)
    }
    
    private static func clampedInt16(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        let clamped = max(-1.0, min(1.0, value))
        return Int16((clamped * 32767.0).rounded())
    }
}
