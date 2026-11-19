import Darwin
import Foundation

/// Runs the local `fermion` speech engine as a short-lived child process.
///
/// The runner is deliberately defensive:
/// - stdout and stderr are drained concurrently, so a chatty engine cannot
///   fill a pipe buffer and deadlock the child while we wait for exit.
/// - a configurable watchdog terminates (then kills) a hung process.
/// - task cancellation propagates to the child instead of leaving it running.
public final class PhononProcessRunner: @unchecked Sendable {
    public let fermionPath: String?
    public let device: String
    public let timeout: TimeInterval
    
    public init(
        fermionPath: String? = nil,
        device: String = EchoSettings.resolveFermionDevice(),
        timeout: TimeInterval = 30
    ) {
        self.fermionPath = fermionPath ?? EchoSettings.resolveFermionPath()
        self.device = device
        self.timeout = timeout
    }
    
    public func transcribe(fileURL: URL) async throws -> (text: String, latencyMs: Double) {
        guard let executable = fermionPath else {
            throw PhononClientError.executableNotFound(EchoSettings.fermionPathHint)
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw PhononClientError.executableNotFound(executable)
        }
        
        let clock = ContinuousClock()
        let start = clock.now
        
        let result = try await execute(
            executable: executable,
            arguments: ["transcribe", "phonon-2", fileURL.path]
        )
        
        let duration = clock.now - start
        let latencyMs = Double(duration.components.seconds) * 1000.0
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
        
        if result.timedOut {
            throw PhononClientError.processTimedOut(timeout)
        }
        try Task.checkCancellation()
        
        guard result.status == 0 else {
            let message = result.stderr.isEmpty
                ? "fermion exited with status \(result.status)"
                : result.stderr
            throw PhononClientError.processError(statusCode: Int(result.status), message: message)
        }
        
        return (text: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), latencyMs: latencyMs)
    }
    
    // MARK: - Process Execution
    
    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let status: Int32
        let timedOut: Bool
    }
    
    private func execute(executable: String, arguments: [String]) async throws -> ProcessResult {
        let state = ExecutionState()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let output = OutputBuffer()
                let resume = OneShot()
                let readers = DispatchGroup()
                
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                var environment = ProcessInfo.processInfo.environment
                environment["FERMION_DEVICE"] = device
                process.environment = environment
                
                process.terminationHandler = { finished in
                    // Both pipe readers must reach EOF before we report the
                    // result, otherwise the last chunk can be lost.
                    readers.wait()
                    resume.perform {
                        continuation.resume(returning: ProcessResult(
                            stdout: output.stdout,
                            stderr: output.stderr,
                            status: finished.terminationStatus,
                            timedOut: state.isTimedOut
                        ))
                    }
                }
                
                // If cancellation arrived before the process was attached,
                // never start it.
                if state.attach(process) {
                    resume.perform {
                        continuation.resume(throwing: CancellationError())
                    }
                    return
                }
                
                // Drain the pipes before launching so a fast-exiting child
                // cannot race the readers.
                readers.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    output.setStdout(data)
                    readers.leave()
                }
                readers.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    output.setStderr(data)
                    readers.leave()
                }
                
                do {
                    try process.run()
                } catch {
                    // Unblock the readers if the launch failed.
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    resume.perform {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                if timeout > 0 {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                        guard process.isRunning else { return }
                        state.markTimedOut()
                        state.terminate(force: false)
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                            state.terminate(force: true)
                        }
                    }
                }
                
                if Task.isCancelled {
                    state.markCancelled()
                    state.terminate(force: false)
                }
            }
        } onCancel: {
            state.markCancelled()
            state.terminate(force: false)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                state.terminate(force: true)
            }
        }
    }
}

// MARK: - Helpers

/// Process handle shared between the async task, cancellation handler, and watchdog.
private final class ExecutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var timedOut = false
    private var cancelled = false
    
    /// Attach the process. Returns `true` when the task was cancelled before
    /// the process could be started.
    func attach(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        return cancelled
    }
    
    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
    
    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
    
    func markCancelled() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
    
    func terminate(force: Bool) {
        lock.lock()
        let runningProcess = process
        lock.unlock()
        
        guard let runningProcess, runningProcess.isRunning else { return }
        
        if force {
            kill(runningProcess.processIdentifier, SIGKILL)
        } else {
            runningProcess.terminate()
        }
    }
}

/// Thread-safe accumulator for the two output pipes.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    
    var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stdoutData, as: UTF8.self)
    }
    
    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stderrData, as: UTF8.self)
    }
    
    func setStdout(_ data: Data) {
        lock.lock()
        stdoutData = data
        lock.unlock()
    }
    
    func setStderr(_ data: Data) {
        lock.lock()
        stderrData = data
        lock.unlock()
    }
}

/// Guarantees a continuation is resumed exactly once.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var didRun = false
    
    func perform(_ body: () -> Void) {
        lock.lock()
        if didRun {
            lock.unlock()
            return
        }
        didRun = true
        lock.unlock()
        body()
    }
}
