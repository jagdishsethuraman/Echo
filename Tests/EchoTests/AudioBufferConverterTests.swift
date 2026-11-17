import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import Echo

@Suite("AudioBufferConverter", .serialized)
struct AudioBufferConverterTests {
    private func makeBuffer(
        samples: [Float],
        sampleRate: Double = 16_000,
        channels: AVAudioChannelCount = 1
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ))
        let frames = samples.count / Int(channels)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(max(frames, 1))
        ))
        buffer.frameLength = AVAudioFrameCount(frames)
        let channelData = try #require(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<frames {
                channelData[channel][frame] = samples[frame * Int(channels) + channel]
            }
        }
        return buffer
    }
    
    private func int16Samples(from data: Data) -> [Int16] {
        data.withUnsafeBytes { raw in
            (0..<(data.count / MemoryLayout<Int16>.size)).map { index in
                raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
            }
        }
    }
    
    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }
    
    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }
    
    @Test func int16PCMClampsOutOfRangeSamples() throws {
        let buffer = try makeBuffer(samples: [-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, .nan])
        let data = try #require(AudioBufferConverter.int16PCM(from: buffer))
        
        #expect(int16Samples(from: data) == [
            Int16(-32_767), Int16(-32_767), Int16(-16_384), 0, 16_384, 32_767, 32_767, 0
        ])
    }
    
    @Test func int16PCMDownmixesToMono() throws {
        let interleaved: [Float] = [1.0, 0.0, 0.0, 1.0, -1.0, 1.0]
        let buffer = try makeBuffer(samples: interleaved, channels: 2)
        let data = try #require(AudioBufferConverter.int16PCM(from: buffer))
        
        #expect(int16Samples(from: data) == [16_384, 16_384, 0])
    }
    
    @Test func int16PCMRejectsEmptyBuffers() throws {
        let buffer = try makeBuffer(samples: [], sampleRate: 16_000)
        #expect(buffer.frameLength == 0)
        #expect(AudioBufferConverter.int16PCM(from: buffer) == nil)
    }
    
    @Test func packagedWAVHasCanonicalHeader() {
        let pcm = Data(repeating: 0x01, count: 32_000)
        let wav = AudioBufferConverter.packageWAV(pcmData: pcm)
        
        #expect(wav.count == 44 + pcm.count)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: wav[12..<16], as: UTF8.self) == "fmt ")
        #expect(String(decoding: wav[36..<40], as: UTF8.self) == "data")
        
        #expect(readUInt32(wav, at: 4) == UInt32(36 + pcm.count))
        #expect(readUInt32(wav, at: 16) == 16)          // fmt chunk size
        #expect(readUInt16(wav, at: 20) == 1)           // PCM format
        #expect(readUInt16(wav, at: 22) == 1)           // channels
        #expect(readUInt32(wav, at: 24) == 16_000)      // sample rate
        #expect(readUInt32(wav, at: 28) == 32_000)      // byte rate
        #expect(readUInt16(wav, at: 32) == 2)           // block align
        #expect(readUInt16(wav, at: 34) == 16)          // bits per sample
        #expect(readUInt32(wav, at: 40) == UInt32(pcm.count))
        #expect(wav.suffix(pcm.count) == pcm)
    }
    
    @Test func resampleReturnsInputWhenAlreadyCanonical() throws {
        let buffer = try makeBuffer(samples: [0.1, 0.2, 0.3])
        let converted = AudioBufferConverter.resampleTo16kMono(buffer)
        #expect(converted === buffer)
    }
    
    @Test func resamples48kTo16kMono() throws {
        // The converter is stateful (it retains a filter tail between calls), so
        // assert the ratio over ten seconds rather than an exact frame count for
        // a tiny buffer.
        let frames = 480_000
        let samples = (0..<frames).map { Float(sin(2.0 * Double.pi * 440.0 * Double($0) / 48_000.0)) * 0.5 }
        let buffer = try makeBuffer(samples: samples, sampleRate: 48_000)
        
        let converted = try #require(AudioBufferConverter.resampleTo16kMono(buffer))
        #expect(converted.format.sampleRate == 16_000)
        #expect(converted.format.channelCount == 1)
        #expect(abs(Int(converted.frameLength) - 160_000) <= 3_200)
        
        let pcm = try #require(AudioBufferConverter.int16PCM(from: converted))
        #expect(pcm.count == Int(converted.frameLength) * 2)
    }
    
    @Test func resamplesStereo44kTo16kMono() throws {
        let frames = 441_000
        var interleaved = [Float]()
        for frame in 0..<frames {
            let value = Float(sin(Double(frame) * 0.01)) * 0.25
            interleaved.append(value)
            interleaved.append(-value)
        }
        let buffer = try makeBuffer(samples: interleaved, sampleRate: 44_100, channels: 2)
        
        let converted = try #require(AudioBufferConverter.resampleTo16kMono(buffer))
        #expect(converted.format.sampleRate == 16_000)
        #expect(converted.format.channelCount == 1)
        #expect(abs(Int(converted.frameLength) - 160_000) <= 3_200)
    }
    
    @Test func decodesScreenCaptureStyleSampleBuffer() throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        
        var asbd = format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        #expect(formatStatus == noErr)
        let description = try #require(formatDescription)
        
        let samples: [Float] = (0..<1_600).map { $0 == 0 ? 0.75 : 0.0 }
        let byteCount = samples.count * MemoryLayout<Float>.size
        
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        #expect(blockStatus == kCMBlockBufferNoErr)
        let block = try #require(blockBuffer)
        
        samples.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 16_000),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: description,
            sampleCount: samples.count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        #expect(sampleStatus == noErr)
        let sample = try #require(sampleBuffer)
        
        let decoded = try #require(AudioBufferConverter.pcmBuffer(from: sample))
        #expect(decoded.format.sampleRate == 16_000)
        #expect(decoded.format.channelCount == 1)
        #expect(decoded.frameLength == 1_600)
        
        let pcm = try #require(AudioBufferConverter.int16PCM(from: decoded))
        let values = int16Samples(from: pcm)
        #expect(values.first == 24_575)
        #expect(values.dropFirst().allSatisfy { $0 == 0 })
    }
    
    @Test func rmsOfSilenceIsLowAndLoudSignalIsHigh() throws {
        let silence = try makeBuffer(samples: Array(repeating: 0, count: 1_600))
        #expect(AudioBufferConverter.calculateRMS(from: silence) == 0)
        
        let loud = try makeBuffer(samples: Array(repeating: 0.9, count: 1_600))
        #expect(AudioBufferConverter.calculateRMS(from: loud) > 0.9)
    }
}
