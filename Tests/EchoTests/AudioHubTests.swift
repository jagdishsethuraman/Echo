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
        enum StartFailure: Error { case unavailable }
        let hub = AudioHub(
            startMicrophoneCapture: { throw StartFailure.unavailable },
            startSystemCapture: {},
            stopSystemCapture: {}
        )
        #expect(throws: StartFailure.unavailable) {
            try hub.retainMicrophone()
        }
        #expect(hub.currentMicRetainCount == 0)
    }

    @Test func overlappingSystemRetainsShareStartAndReleaseIndependently() async throws {
        let allowStart = AudioTestGate()
        let starting = AudioTestGate()
        let starts = ValueRecorder<Int>()
        let stops = ValueRecorder<Int>()
        let hub = AudioHub(startSystemCapture: {
            starts.record(1)
            starting.signal()
            await allowStart.wait()
        }, stopSystemCapture: { stops.record(1) })

        let first = Task { try await hub.retainSystemAudio() }
        await starting.wait()
        let second = Task { try await hub.retainSystemAudio() }
        await waitForRetainCount(2, on: hub)
        allowStart.signal()
        try await first.value
        try await second.value

        #expect(starts.count == 1)
        #expect(hub.currentSystemRetainCount == 2)
        await hub.releaseSystemAudio()
        #expect(hub.currentSystemRetainCount == 1)
        #expect(stops.count == 0)
        await hub.releaseSystemAudio()
        #expect(hub.currentSystemRetainCount == 0)
        #expect(stops.count == 1)
    }

    @Test func retainWaitsForThePreviousSystemStop() async throws {
        let allowStop = AudioTestGate()
        let stopping = AudioTestGate()
        let events = ValueRecorder<String>()
        let hub = AudioHub(startSystemCapture: {
            events.record("start")
        }, stopSystemCapture: {
            events.record("stopping")
            if events.count == 2 {
                stopping.signal()
                await allowStop.wait()
            }
            events.record("stopped")
        })

        try await hub.retainSystemAudio()
        let release = Task { await hub.releaseSystemAudio() }
        await stopping.wait()
        let retaining = AudioTestGate()
        let restart = Task {
            retaining.signal()
            try await hub.retainSystemAudio()
        }
        await retaining.wait()
        try await Task.sleep(for: .milliseconds(30))
        #expect(events.snapshot == ["start", "stopping"])
        allowStop.signal()
        await release.value
        try await restart.value
        #expect(events.snapshot == ["start", "stopping", "stopped", "start"])
        await hub.releaseSystemAudio()
    }

    @Test func shutdownDuringSystemStartupWaitsAndClosesTheStream() async {
        let starting = AudioTestGate()
        let allowStart = AudioTestGate()
        let events = ValueRecorder<String>()
        let hub = AudioHub(startSystemCapture: {
            starting.signal()
            await allowStart.wait()
            events.record("started")
        }, stopSystemCapture: { events.record("stopped") })

        let retain = Task { try await hub.retainSystemAudio() }
        await starting.wait()
        let shutdown = Task { await hub.stopAll() }
        await waitForRetainCount(0, on: hub)
        #expect(events.count == 0)
        allowStart.signal()

        await shutdown.value
        await #expect(throws: CancellationError.self) { try await retain.value }
        #expect(events.snapshot == ["started", "stopped"])
        #expect(hub.currentSystemRetainCount == 0)
    }

    private func waitForRetainCount(_ count: Int, on hub: AudioHub) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while hub.currentSystemRetainCount != count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(hub.currentSystemRetainCount == count)
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

    @Test func sweepProtectsAnotherProcessAndPreservesFilesWithoutAnOwner() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("echo-audio-sweep-\(UUID())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["15"]
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }

        let ownedDirectory = root.appendingPathComponent("echo_pid_\(child.processIdentifier)_\(UUID())")
        let unknownDirectory = root.appendingPathComponent("pid_unrecognized")
        for directory in [ownedDirectory, unknownDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let activeWAV = ownedDirectory.appendingPathComponent("active.wav")
        let legacyWAV = root.appendingPathComponent("echo_segment_legacy.wav")
        try Data([1]).write(to: activeWAV)
        try Data([1]).write(to: legacyWAV)

        AudioTempDirectory.sweepOrphanedAudioFiles(in: root)
        #expect(fileManager.fileExists(atPath: activeWAV.path))
        #expect(fileManager.fileExists(atPath: legacyWAV.path))
        #expect(fileManager.fileExists(atPath: unknownDirectory.path))

        child.terminate()
        child.waitUntilExit()
        AudioTempDirectory.sweepOrphanedAudioFiles(in: root)
        #expect(!fileManager.fileExists(atPath: ownedDirectory.path))
        #expect(fileManager.fileExists(atPath: legacyWAV.path))
        #expect(fileManager.fileExists(atPath: unknownDirectory.path))
    }
}

private final class AudioTestGate: Sendable {
    private let group = DispatchGroup()

    init() { group.enter() }

    func signal() { group.leave() }

    func wait() async {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }
    }
}
