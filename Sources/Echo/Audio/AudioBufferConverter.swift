import AVFoundation
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
}
