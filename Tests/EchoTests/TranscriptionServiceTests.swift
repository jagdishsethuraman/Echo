import Foundation
import Testing
@testable import Echo

private final class ConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var peak = 0
    
    func enter() {
        lock.lock()
        active += 1
        peak = max(peak, active)
        lock.unlock()
    }
    
    func leave() {
        lock.lock()
        active -= 1
        lock.unlock()
    }
    
    var maxActive: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }
}

private final class CompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [String?] = []
    
    func record(_ text: String?) {
        lock.lock()
        results.append(text)
        lock.unlock()
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.count
    }
    
    var snapshot: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

private struct EngineFailure: Error {}

@Suite("TranscriptionService", .serialized)
struct TranscriptionServiceTests {
    private let pcm = Data(repeating: 1, count: 64)
    
    @Test func serializesEngineCalls() async {
        let probe = ConcurrencyProbe()
        let service = TranscriptionService(engine: { _ in
            probe.enter()
            try await Task.sleep(for: .milliseconds(40))
            probe.leave()
            return "ok"
        }, maxConcurrent: 1)
        
        let tasks = (0..<4).map { _ in
            Task { try? await service.transcribe(pcmData: pcm) }
        }
        for task in tasks {
            _ = await task.value
        }
        
        #expect(probe.maxActive == 1)
    }
    
    @Test func waitUntilIdleWaitsForSubmittedWork() async {
        let recorder = CompletionRecorder()
        let service = TranscriptionService(engine: { _ in
            try await Task.sleep(for: .milliseconds(60))
            return "text"
        })
        
        for _ in 0..<3 {
            service.submit(pcmData: pcm) { text in
                recorder.record(text)
            }
        }
        
        #expect(!service.isIdle)
        let drained = await service.waitUntilIdle(timeout: 3)
        
        #expect(drained)
        #expect(service.isIdle)
        #expect(recorder.count == 3)
        #expect(recorder.snapshot.allSatisfy { $0 == "text" })
    }
    
    @Test func waitUntilIdleReportsTimeout() async {
        let service = TranscriptionService(engine: { _ in
            try await Task.sleep(for: .milliseconds(400))
            return "slow"
        })
        
        service.submit(pcmData: pcm) { _ in }
        let drained = await service.waitUntilIdle(timeout: 0.05)
        
        #expect(!drained)
        // Let the outstanding work finish so the suite does not leak a task.
        _ = await service.waitUntilIdle(timeout: 2)
    }
    
    @Test func failedTranscriptionCompletesWithNil() async {
        let recorder = CompletionRecorder()
        let service = TranscriptionService(engine: { _ in
            throw EngineFailure()
        })
        
        service.submit(pcmData: pcm) { text in
            recorder.record(text)
        }
        
        #expect(await service.waitUntilIdle(timeout: 1))
        #expect(recorder.count == 1)
        #expect(recorder.snapshot.first == .some(nil))
    }

    @Test func unavailableExecutableFailsReadinessCheck() {
        let missingExecutable = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let runner = PhononProcessRunner(fermionPath: missingExecutable)
        let service = TranscriptionService(runner: runner)

        do {
            try service.checkReadiness()
            Issue.record("Expected the engine readiness check to fail")
        } catch PhononClientError.executableNotFound(let path) {
            #expect(path == missingExecutable)
        } catch {
            Issue.record("Unexpected readiness error: \(error)")
        }
    }

    @Test func reportingSubmissionDistinguishesEmptyTranscriptFromFailure() async throws {
        let service = TranscriptionService(engine: { data in
            if data.isEmpty { return "" }
            throw EngineFailure()
        })
        try service.checkReadiness()

        await confirmation("empty transcript delivered") { delivered in
            await service.submitReporting(pcmData: Data()) { result in
                #expect((try? result.get()) == "")
                delivered()
            }.value
        }
        await confirmation("transcription failure delivered") { delivered in
            await service.submitReporting(pcmData: pcm) { result in
                #expect(throws: EngineFailure.self) { try result.get() }
                delivered()
            }.value
        }
        #expect(service.isIdle)
    }

    @Test func queueRejectsSubmissionsExceedingBacklogBudget() async {
        let chunk = Data(repeating: 0, count: 100)
        let service = TranscriptionService(
            engine: { _ in
                try await Task.sleep(for: .milliseconds(50))
                return "ok"
            },
            maxConcurrent: 1,
            maxPendingBytes: 200
        )

        let t1 = service.submitReporting(pcmData: chunk) { _ in }
        #expect(service.currentQueuedBytes == 100)

        let t2 = service.submitReporting(pcmData: chunk) { _ in }
        #expect(service.currentQueuedBytes == 200)

        let receivedError: TranscriptionService.TranscriptionError? = await withCheckedContinuation { continuation in
            _ = service.submitReporting(pcmData: chunk) { result in
                if case .failure(let err as TranscriptionService.TranscriptionError) = result {
                    continuation.resume(returning: err)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }

        #expect(receivedError == .queueOverloaded(bytesQueued: 200, maxBytes: 200))

        _ = await t1.value
        _ = await t2.value
        _ = await service.waitUntilIdle(timeout: 2)
        #expect(service.currentQueuedBytes == 0)
    }

    @Test func repeatedDictationsRespectTheirBudgetWhileMeetingInferenceIsBusy() async throws {
        let allowEngine = DispatchGroup()
        allowEngine.enter()
        let calls = CompletionRecorder()
        let chunk = Data(repeating: 0, count: 100)
        let service = TranscriptionService(
            engine: { _ in
                calls.record("started")
                await withCheckedContinuation { continuation in
                    allowEngine.notify(queue: .global()) { continuation.resume() }
                }
                return "ok"
            },
            maxPendingBytes: 100,
            maxDictationPendingBytes: 200
        )

        let meeting = service.submit(pcmData: chunk) { _ in }
        let dictations = (0..<2).map { _ in Task { try await service.transcribe(pcmData: chunk) } }
        let deadline = ContinuousClock.now + .seconds(2)
        while service.currentQueuedBytes < 300, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.currentQueuedBytes == 300)
        #expect(!service.isIdle)

        if service.currentQueuedBytes == 300 {
            for _ in 0..<10 {
                await #expect(throws: TranscriptionService.TranscriptionError.queueOverloaded(bytesQueued: 200, maxBytes: 200)) {
                    try await service.transcribe(pcmData: chunk)
                }
            }
            #expect(service.currentQueuedBytes == 300)
            #expect(calls.count == 1)
        }

        allowEngine.leave()
        await meeting.value
        for dictation in dictations {
            #expect(try await dictation.value == "ok")
        }
        #expect(calls.count == 3)
        #expect(service.currentQueuedBytes == 0)
        #expect(service.isIdle)
    }

    @Test func runnerReceivesPrivateWAVInTheProcessDirectory() async throws {
        let files = FileManager.default
        let fixture = files.temporaryDirectory.appendingPathComponent("echo-transcription-\(UUID())")
        try files.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: fixture) }

        let executable = fixture.appendingPathComponent("fermion-fixture")
        let script = """
        #!/bin/sh
        test -r "$3" || exit 1
        /usr/bin/stat -f '%Lp' "$3" || exit 1
        printf '%s\\n' "$3"
        """
        try Data(script.utf8).write(to: executable)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let scratch = fixture.appendingPathComponent("audio")
        let service = TranscriptionService(
            runner: PhononProcessRunner(fermionPath: executable.path),
            tempDirectory: scratch
        )

        let transcript = try await service.transcribe(pcmData: pcm)
        let lines = transcript.split(separator: "\n")
        #expect(lines.first == "600")
        let wavPath = try #require(lines.last.map(String.init))
        let wav = URL(fileURLWithPath: wavPath)
        let directory = wav.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(directory.lastPathComponent.hasPrefix("echo_pid_\(pid)_"))
        #expect(directory.deletingLastPathComponent().path == scratch.path)
        let permissions = try files.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
        #expect(!files.fileExists(atPath: wavPath))
    }
}
