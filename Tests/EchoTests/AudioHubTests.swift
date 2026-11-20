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
    
    @Test func errorFansOutToEveryObserver() {
        let hub = AudioHub()
        let recorder = ValueRecorder<String>()
        
        hub.addErrorObserver { error in
            recorder.record(error.localizedDescription)
        }
        
        let testError = NSError(domain: "EchoAudio", code: 99, userInfo: [NSLocalizedDescriptionKey: "Audio stream stalled"])
        hub.broadcastError(testError)
        
        #expect(recorder.snapshot == ["Audio stream stalled"])
        #expect(hub.lastError?.localizedDescription == "Audio stream stalled")
    }

    @Test func systemPCMBufferFansOutToObservers() {
        let hub = AudioHub()
        let recorder = ValueRecorder<Float>()
        let buffer = makeBuffer()
        
        hub.addSystemPCMBufferObserver { buf, level in
            recorder.record(level)
        }
        hub.broadcastSystemPCMBuffer(buffer, level: 0.75)
        
        #expect(recorder.snapshot == [0.75])
    }

    @Test func failedMicrophoneStartLeavesZeroRetainCount() {
        let hub = AudioHub()
        do {
            try hub.retainMicrophone()
            #expect(hub.currentMicRetainCount == 1)
            hub.releaseMicrophone()
            #expect(hub.currentMicRetainCount == 0)
        } catch {
            // Hardware start failure must leave retain count at zero
            #expect(hub.currentMicRetainCount == 0)
        }
    }

    @Test func audioTempDirectoryProtectsCurrentProcess() {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        #expect(AudioTempDirectory.isProcessAlive(pid: currentPid) == true)
        #expect(AudioTempDirectory.isProcessAlive(pid: -999) == false)

        let url = try? AudioTempDirectory.writeTempWAV(data: Data([0, 1, 2]), prefix: "test_isolated")
        #expect(url != nil)
        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(url.path.contains("pid_\(currentPid)"))

            // Sweep must NOT delete active process files
            AudioTempDirectory.sweepOrphanedAudioFiles()
            #expect(FileManager.default.fileExists(atPath: url.path))

            // Cleanup current process removes it
            AudioTempDirectory.cleanupCurrentProcess()
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}
