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
    public typealias ReportingCompletion = @Sendable (Result<String, Error>) async -> Void
    public typealias Engine = @Sendable (Data) async throws -> String

    public enum TranscriptionError: LocalizedError, Sendable, Equatable {
        case queueOverloaded(bytesQueued: Int, maxBytes: Int)

        public var errorDescription: String? {
            switch self {
            case .queueOverloaded(let queued, let max):
                return "Inference queue overloaded (\(queued / 1024) KB queued, limit \(max / 1024) KB)."
            }
        }
    }
    
    private let engine: Engine
    private let checkEngineReadiness: @Sendable () throws -> Void
    private let semaphore: AsyncSemaphore
    public let maxPendingBytes: Int
    public let maxDictationPendingBytes: Int

    // A full ten-minute dictation can follow its twelve-second live preview
    // while meeting segments are pending on the same engine.
    public static let defaultDictationBudget = (600 + 12) * AudioPCMBufferStore.bytesPerSecond
    
    private let stateLock = NSLock()
    private var outstanding = 0
    private var meetingBytes = 0
    private var dictationBytes = 0

    /// Bytes reserved for startup, queued inference and running inference across both modes.
    public var currentQueuedBytes: Int {
        stateLock.withLock { meetingBytes + dictationBytes }
    }
    
    public init(
        runner: PhononProcessRunner,
        maxConcurrent: Int = 1,
        maxPendingBytes: Int = 3_840_000,
        maxDictationPendingBytes: Int = TranscriptionService.defaultDictationBudget,
        tempDirectory: URL? = nil
    ) {
        self.semaphore = AsyncSemaphore(limit: max(1, maxConcurrent))
        self.maxPendingBytes = max(0, maxPendingBytes)
        self.maxDictationPendingBytes = min(max(0, maxDictationPendingBytes), Int.max - self.maxPendingBytes)
        self.checkEngineReadiness = { try runner.checkReadiness() }
        self.engine = { pcmData in
            let wavData = AudioBufferConverter.packageWAV(pcmData: pcmData, sampleRate: 16000, channels: 1)
            let tempFile = try AudioTempDirectory.writeTempWAV(
                data: wavData, prefix: "echo_segment", root: tempDirectory
            )
            defer { try? FileManager.default.removeItem(at: tempFile) }
            let (text, _) = try await runner.transcribe(fileURL: tempFile)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    /// Test seam: drive the queue with a closure instead of a child process.
    init(
        engine: @escaping Engine,
        maxConcurrent: Int = 1,
        maxPendingBytes: Int = 3_840_000,
        maxDictationPendingBytes: Int = TranscriptionService.defaultDictationBudget
    ) {
        self.engine = engine
        self.checkEngineReadiness = {}
        self.semaphore = AsyncSemaphore(limit: max(1, maxConcurrent))
        self.maxPendingBytes = max(0, maxPendingBytes)
        self.maxDictationPendingBytes = min(max(0, maxDictationPendingBytes), Int.max - self.maxPendingBytes)
    }

    /// Check that the configured engine executable is available before capture.
    public func checkReadiness() throws {
        try checkEngineReadiness()
    }
    
    /// Submit a segment for transcription. The completion runs after the engine
    /// returns, with `nil` when transcription failed.
    @discardableResult
    public func submit(pcmData: Data, completion: @escaping Completion) -> Task<Void, Never> {
        submitReporting(pcmData: pcmData) { result in
            await completion(try? result.get())
        }
    }

    /// Submit a segment and deliver its transcript or the underlying error.
    @discardableResult
    public func submitReporting(
        pcmData: Data,
        completion: @escaping ReportingCompletion
    ) -> Task<Void, Never> {
        do {
            let reservation = try reserveMeetingAudio(bytes: pcmData.count)
            return submitReserved(pcmData: pcmData, reservation: reservation, completion: completion)
        } catch {
            return Task {
                await completion(.failure(error))
            }
        }
    }

    /// Transfer an existing startup reservation to the inference queue.
    func submitReserved(
        pcmData: Data,
        reservation: Reservation,
        completion: @escaping ReportingCompletion
    ) -> Task<Void, Never> {
        return Task {
            defer { reservation.release() }
            let result: Result<String, Error>
            do {
                result = .success(try await decode(pcmData: pcmData))
            } catch {
                result = .failure(error)
            }
            await completion(result)
        }
    }
    
    /// Transcribe one 16 kHz mono Int16 dictation using the shared inference queue.
    public func transcribe(pcmData: Data) async throws -> String {
        let reservation = try reserve(bytes: pcmData.count, kind: \.dictationBytes, limit: maxDictationPendingBytes)
        defer { reservation.release() }
        return try await decode(pcmData: pcmData)
    }

    private func decode(pcmData: Data) async throws -> String {
        try Task.checkCancellation()
        await semaphore.acquire()
        defer { semaphore.release() }
        try Task.checkCancellation()
        return try await engine(pcmData)
    }

    /// Reserve capacity as soon as speech arrives, even while capture is starting.
    func reserveMeetingAudio(bytes: Int) throws -> Reservation {
        try reserve(bytes: bytes, kind: \.meetingBytes, limit: maxPendingBytes)
    }

    private func reserve(
        bytes: Int,
        kind: ReferenceWritableKeyPath<TranscriptionService, Int>,
        limit: Int
    ) throws -> Reservation {
        try stateLock.withLock {
            let queued = self[keyPath: kind]
            guard bytes <= limit - queued else {
                throw TranscriptionError.queueOverloaded(bytesQueued: queued, maxBytes: limit)
            }
            self[keyPath: kind] += bytes
            outstanding += 1
        }
        return Reservation {
            self.stateLock.withLock {
                self[keyPath: kind] -= bytes
                self.outstanding -= 1
            }
        }
    }

    final class Reservation: @unchecked Sendable {
        private let lock = NSLock()
        private var onRelease: (() -> Void)?

        fileprivate init(onRelease: @escaping () -> Void) {
            self.onRelease = onRelease
        }

        fileprivate func release() {
            let callback = lock.withLock {
                let callback = onRelease
                onRelease = nil
                return callback
            }
            callback?()
        }

        deinit { release() }
    }
    
    /// `true` when neither mode is holding any inference reservations.
    public var isIdle: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return outstanding == 0
    }
    
    /// Wait for every admitted segment or dictation, or until `timeout` elapses.
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
