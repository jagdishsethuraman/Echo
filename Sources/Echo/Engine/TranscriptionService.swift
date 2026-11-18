import Foundation

/// Bounded, drainable transcription queue.
///
/// Meeting VADs can produce segments faster than the local engine finishes
/// them. Submitting one `fermion` process per segment without a limit pins the
/// CPU and makes latency unbounded, and `stopSession()` has no way to know
/// whether the final utterance has landed. This service fixes both:
///
/// - at most `maxConcurrent` engine processes run at once (FIFO);
/// - every submitted segment is tracked, so shutdown can wait for the queue to
///   drain before writing `endTime` or exporting.
public final class TranscriptionService: @unchecked Sendable {
    public typealias Completion = @Sendable (String?) async -> Void
    public typealias Engine = @Sendable (Data) async throws -> String
    
    private let engine: Engine
    private let semaphore: AsyncSemaphore
    
    private let stateLock = NSLock()
    private var outstanding = 0
    
    public init(
        runner: PhononProcessRunner,
        maxConcurrent: Int = 1,
        tempDirectory: URL = AudioTempDirectory.rootURL
    ) {
        self.semaphore = AsyncSemaphore(limit: max(1, maxConcurrent))
        self.engine = { pcmData in
            let wavData = AudioBufferConverter.packageWAV(pcmData: pcmData, sampleRate: 16000, channels: 1)
            let tempFile = tempDirectory.appendingPathComponent("echo_segment_\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: tempFile) }
            
            try wavData.write(to: tempFile, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempFile.path)
            let (text, _) = try await runner.transcribe(fileURL: tempFile)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    /// Test seam: drive the queue with a closure instead of a child process.
    init(engine: @escaping Engine, maxConcurrent: Int = 1) {
        self.engine = engine
        self.semaphore = AsyncSemaphore(limit: max(1, maxConcurrent))
    }
    
    /// Submit a segment for transcription. The completion runs after the engine
    /// returns, with `nil` when transcription failed.
    @discardableResult
    public func submit(pcmData: Data, completion: @escaping Completion) -> Task<Void, Never> {
        begin()
        return Task {
            defer { finish() }
            let text = try? await transcribe(pcmData: pcmData)
            await completion(text)
        }
    }
    
    /// Transcribe one 16 kHz mono Int16 PCM segment.
    ///
    /// Concurrency is bounded by the semaphore, so calling this directly is
    /// safe; prefer `submit` when the caller also needs drain tracking.
    public func transcribe(pcmData: Data) async throws -> String {
        await semaphore.acquire()
        defer { semaphore.release() }
        return try await engine(pcmData)
    }
    
    /// `true` when no submitted segment is queued or running.
    public var isIdle: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return outstanding == 0
    }
    
    /// Wait for every submitted segment to complete, or until `timeout` elapses.
    /// Returns `false` when the timeout was hit.
    @discardableResult
    public func waitUntilIdle(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while !isIdle {
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
    
    // MARK: - Outstanding tracking
    
    private func begin() {
        stateLock.lock()
        outstanding += 1
        stateLock.unlock()
    }
    
    private func finish() {
        stateLock.lock()
        outstanding -= 1
        stateLock.unlock()
    }
}

/// Async FIFO semaphore with a synchronous `release`.
///
/// An actor cannot hand a slot directly to a waiter without re-entering, so a
/// small lock-protected primitive keeps acquisition order and avoids spinning.
private final class AsyncSemaphore: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(limit: Int) {
        self.limit = limit
    }
    
    func acquire() async {
        if tryAcquireSlot() { return }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            // A release may have happened between the attempt above and taking
            // this lock again; consume the free slot instead of waiting.
            if inFlight < limit {
                inFlight += 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
    
    private func tryAcquireSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight < limit else { return false }
        inFlight += 1
        return true
    }
    
    func release() {
        lock.lock()
        if let next = waiters.first {
            // Hand the slot straight to the waiter; `inFlight` is unchanged.
            waiters.removeFirst()
            lock.unlock()
            next.resume()
        } else {
            inFlight = max(0, inFlight - 1)
            lock.unlock()
        }
    }
}
