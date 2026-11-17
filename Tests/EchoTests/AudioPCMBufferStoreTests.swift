import Foundation
import Testing
@testable import Echo

@Suite("AudioPCMBufferStore")
struct AudioPCMBufferStoreTests {
    private static let bytesPerSecond = AudioPCMBufferStore.bytesPerSecond
    
    /// Chunk sizes chosen to exercise odd boundaries in the tail walk.
    private static let chunkSizes = [1, 7, 1_000, 3, 13_000, 65, 4_097]
    
    private static func payload() -> Data {
        var payload = Data()
        var seed: UInt8 = 0
        for size in chunkSizes {
            var chunk = Data(count: size)
            for index in 0..<size {
                chunk[index] = seed &+ UInt8(index % 251)
            }
            payload.append(chunk)
            seed = seed &+ 17
        }
        return payload
    }
    
    @Test func startsEmpty() {
        let store = AudioPCMBufferStore()
        #expect(store.byteCount == 0)
        #expect(store.durationSeconds == 0)
        #expect(store.snapshot().pcm.isEmpty)
        #expect(store.snapshot().isTruncated == false)
        #expect(store.snapshot(maxBytes: 100).pcm.isEmpty)
        #expect(store.snapshot(maxBytes: 100).isTruncated == false)
    }
    
    @Test func emptyAppendIsIgnored() {
        let store = AudioPCMBufferStore()
        store.append(Data())
        #expect(store.byteCount == 0)
        #expect(store.snapshot().pcm.isEmpty)
    }
    
    @Test func appendsPreserveBytesAndOrder() {
        let store = AudioPCMBufferStore()
        var expected = Data()
        var seed: UInt8 = 0
        
        for size in Self.chunkSizes {
            var chunk = Data(count: size)
            for index in 0..<size {
                chunk[index] = seed &+ UInt8(index % 251)
            }
            expected.append(chunk)
            store.append(chunk)
            seed = seed &+ 17
            #expect(store.byteCount == expected.count)
        }
        
        let snapshot = store.snapshot()
        #expect(snapshot.pcm == expected)
        #expect(snapshot.totalByteCount == expected.count)
        #expect(snapshot.isTruncated == false)
        
        // Requesting exactly the captured length must not count as a trim.
        let exact = store.snapshot(maxBytes: expected.count)
        #expect(exact.pcm == expected)
        #expect(exact.isTruncated == false)
    }
    
    @Test func tailSnapshotsMatchDataSuffix() {
        let payload = Self.payload()
        let store = AudioPCMBufferStore()
        store.append(payload)
        
        var limits = [0, 1, 2, 6, 7, 8, 999, 1_000, 1_001, 1_003, 14_000, 14_003, 14_068]
        limits.append(payload.count - 1)
        limits.append(payload.count)
        limits.append(payload.count + 50)
        limits.append(contentsOf: Array(stride(from: 0, to: 40, by: 3)))
        
        for limit in limits {
            let snapshot = store.snapshot(maxBytes: limit)
            let expected = limit >= payload.count ? payload : payload.suffix(max(0, limit))
            #expect(snapshot.pcm == expected, "tail mismatch at limit \(limit)")
            #expect(snapshot.pcm.count == min(limit, payload.count))
            #expect(snapshot.isTruncated == (limit < payload.count), "truncation flag wrong at \(limit)")
            #expect(snapshot.totalByteCount == payload.count)
        }
    }
    
    @Test func takeAllDrainsStore() {
        let store = AudioPCMBufferStore()
        store.append(Self.payload())
        let captured = store.takeAll()
        
        #expect(captured.pcm == Self.payload())
        #expect(captured.isTruncated == false)
        #expect(store.byteCount == 0)
        #expect(store.snapshot().pcm.isEmpty)
        
        // The store remains usable after draining.
        store.append(Data(repeating: 0x42, count: 500))
        #expect(store.byteCount == 500)
        #expect(store.snapshot().pcm == Data(repeating: 0x42, count: 500))
    }
    
    @Test func removeAllClearsStore() {
        let store = AudioPCMBufferStore()
        store.append(Self.payload())
        store.removeAll()
        #expect(store.byteCount == 0)
        #expect(store.snapshot().pcm.isEmpty)
    }
    
    @Test func durationUses16kHzMonoInt16() {
        let store = AudioPCMBufferStore()
        store.append(Data(count: Self.bytesPerSecond))
        #expect(store.durationSeconds == 1.0)
        #expect(Self.bytesPerSecond == 32_000)
        
        store.append(Data(count: Self.bytesPerSecond / 2))
        #expect(store.durationSeconds == 1.5)
    }
    
    @Test func concurrentAppendsDoNotLoseBytes() {
        let store = AudioPCMBufferStore()
        let appenders = 8
        let iterations = 250
        let chunk = Data(repeating: 0x01, count: 32)
        
        DispatchQueue.concurrentPerform(iterations: appenders) { _ in
            for _ in 0..<iterations {
                store.append(chunk)
            }
        }
        
        let expectedBytes = appenders * iterations * chunk.count
        #expect(store.byteCount == expectedBytes)
        #expect(store.durationSeconds == Double(expectedBytes) / Double(Self.bytesPerSecond))
        #expect(store.snapshot(maxBytes: 1_000).pcm.count == 1_000)
        #expect(store.snapshot().pcm.count == expectedBytes)
    }
}
