import Foundation

/// A snapshot of the raw 16 kHz mono Int16 PCM captured for a dictation.
public struct AudioPCMSnapshot: Equatable {
    public let pcm: Data
    /// Total bytes captured, including audio that was trimmed by `maxBytes`.
    public let totalByteCount: Int
    /// `true` when older audio was dropped to satisfy `maxBytes`.
    public let isTruncated: Bool
    
    public var byteCount: Int { pcm.count }
}

/// Chunked, lock-protected store for dictation audio.
///
/// Appending to a single `Data` reallocates and copies the whole recording,
/// which grows quadratically for a long dictation. Keeping the audio as a list
/// of chunks makes appends O(1) and lets callers request only the tail they
/// need for a live partial decode.
///
/// The store is intentionally unbounded in chunk count; the coordinator caps
/// dictation length so the worst case stays around 20 MB (10 minutes of
/// 16 kHz mono Int16).
public final class AudioPCMBufferStore: @unchecked Sendable {
    /// Bytes per second of 16 kHz, mono, 16-bit PCM.
    public static let bytesPerSecond = 16_000 * MemoryLayout<Int16>.size
    
    private let lock = NSLock()
    private var chunks: [Data] = []
    private var totalByteCount = 0
    
    public init() {}
    
    /// Append raw PCM bytes. Empty payloads are ignored.
    public func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        chunks.append(data)
        totalByteCount += data.count
        lock.unlock()
    }
    
    /// Total number of captured bytes.
    public var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalByteCount
    }
    
    /// Captured audio duration in seconds.
    public var durationSeconds: Double {
        Double(byteCount) / Double(Self.bytesPerSecond)
    }
    
    /// Copy the most recent `maxBytes` bytes (or everything when `nil`).
    ///
    /// When the request exceeds the captured audio the whole recording is
    /// returned with `isTruncated == false`, so callers can distinguish "the
    /// beginning of the recording" from "the beginning of a sliding window".
    public func snapshot(maxBytes: Int? = nil) -> AudioPCMSnapshot {
        lock.lock()
        defer { lock.unlock() }
        
        let limit = max(0, maxBytes ?? totalByteCount)
        let bytesToTake = min(limit, totalByteCount)
        let isTruncated = bytesToTake < totalByteCount
        
        if !isTruncated {
            var combined = Data()
            combined.reserveCapacity(totalByteCount)
            for chunk in chunks {
                combined.append(chunk)
            }
            return AudioPCMSnapshot(pcm: combined, totalByteCount: totalByteCount, isTruncated: false)
        }
        
        // Walk backwards until the tail is covered, then restore capture order.
        var remaining = bytesToTake
        var tailChunks: [Data] = []
        for chunk in chunks.reversed() {
            guard remaining > 0 else { break }
            if chunk.count <= remaining {
                tailChunks.append(chunk)
                remaining -= chunk.count
            } else {
                tailChunks.append(chunk.suffix(remaining))
                remaining = 0
            }
        }
        
        var tail = Data()
        tail.reserveCapacity(bytesToTake)
        for chunk in tailChunks.reversed() {
            tail.append(chunk)
        }
        return AudioPCMSnapshot(pcm: tail, totalByteCount: totalByteCount, isTruncated: true)
    }
    
    /// Copy everything captured so far and reset the store.
    public func takeAll() -> AudioPCMSnapshot {
        let snapshot = snapshot()
        removeAll()
        return snapshot
    }
    
    /// Discard all captured audio.
    public func removeAll() {
        lock.lock()
        chunks.removeAll()
        totalByteCount = 0
        lock.unlock()
    }
}
