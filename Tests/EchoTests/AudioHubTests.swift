import AVFoundation
import Foundation
import Testing
@testable import Echo

private final class ValueRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []
    
    func record(_ value: Value) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }
    
    var snapshot: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Suite("AudioHub", .serialized)
struct AudioHubTests {
    private func makeBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        buffer.frameLength = 16
        return buffer
    }
    
    @Test func microphoneLevelsFanOutToEveryObserver() {
        let hub = AudioHub()
        let first = ValueRecorder<Float>()
        let second = ValueRecorder<Float>()
        
        hub.addMicLevelObserver { first.record($0) }
        hub.addMicLevelObserver { second.record($0) }
        
        hub.broadcastMicLevel(0.5)
        
        #expect(first.snapshot == [0.5])
        #expect(second.snapshot == [0.5])
    }
    
    @Test func microphoneBuffersFanOutToEveryObserver() {
        let hub = AudioHub()
        let first = ValueRecorder<Int>()
        let second = ValueRecorder<Int>()
        let buffer = makeBuffer()
        
        hub.addMicBufferObserver { _ in first.record(1) }
        hub.addMicBufferObserver { _ in second.record(1) }
        
        hub.broadcastMicBuffer(buffer)
        
        #expect(first.count == 1)
        #expect(second.count == 1)
    }
    
    @Test func removingAnObserverStopsDelivery() {
        let hub = AudioHub()
        let recorder = ValueRecorder<Float>()
        let token = hub.addMicLevelObserver { recorder.record($0) }
        
        hub.broadcastMicLevel(0.4)
        hub.removeObserver(token)
        hub.broadcastMicLevel(0.6)
        
        #expect(recorder.snapshot == [0.4])
    }
    
    @Test func levelsAreThrottledButZeroAlwaysPasses() {
        let hub = AudioHub()
        let recorder = ValueRecorder<Float>()
        hub.addMicLevelObserver { recorder.record($0) }
        
        hub.broadcastMicLevel(0.5)
        hub.broadcastMicLevel(0.6)
        // The second non-zero update falls inside the 12 Hz window.
        #expect(recorder.snapshot == [0.5])
        
        hub.broadcastMicLevel(0)
        hub.broadcastMicLevel(0)
        #expect(recorder.snapshot == [0.5, 0, 0])
    }
}
