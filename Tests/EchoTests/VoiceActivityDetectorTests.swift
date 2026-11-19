import Foundation
import Testing
@testable import Echo

private final class SegmentRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [(pcm: Data, duration: Double)] = []
    
    func record(_ pcm: Data, _ duration: Double) {
        lock.lock()
        segments.append((pcm, duration))
        lock.unlock()
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return segments.count
    }
    
    var snapshot: [(pcm: Data, duration: Double)] {
        lock.lock()
        defer { lock.unlock() }
        return segments
    }
}

@Suite("VoiceActivityDetector", .serialized)
struct VoiceActivityDetectorTests {
    private let sampleRate = 16_000
    
    /// 100 ms of Int16 PCM.
    private func chunk(seconds: Double = 0.1) -> Data {
        Data(count: Int(Double(sampleRate) * seconds) * 2)
    }
    
    /// Segments are delivered on a background queue, so poll instead of assuming
    /// the callback has already run.
    private func waitForSegments(_ recorder: SegmentRecorder, count: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if recorder.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return recorder.count >= count
    }
    
    @Test func speechFollowedBySilenceEmitsSegment() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.1,
            silenceThresholdSeconds: 0.61,
            minSpeechDurationSeconds: 0.4
        )
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        for _ in 0..<5 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        for _ in 0..<5 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        // 0.5 s of silence is below the 0.6 s threshold.
        #expect(recorder.count == 0)
        
        // The sixth silent chunk crosses the threshold and flushes.
        vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        #expect(await waitForSegments(recorder, count: 1))
        
        let segment = recorder.snapshot.first
        // 0.5 s of speech + 0.6 s of trailing silence.
        #expect(segment?.pcm.count == 11 * chunk.count)
        #expect(abs((segment?.duration ?? 0) - 1.1) < 0.001)
    }
    
    @Test func immediateFlushDiscardsBelowMinimumDuration() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.1,
            silenceThresholdSeconds: 0.6,
            minSpeechDurationSeconds: 0.4
        )
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        // 200 ms of speech is below the 400 ms minimum, so a flush drops it.
        for _ in 0..<2 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        vad.flush()
        
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.count == 0)
    }
    
    @Test func silenceOnlyNeverEmitsSegment() async {
        let vad = VoiceActivityDetector(energyThreshold: 0.1)
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        for _ in 0..<50 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.count == 0)
    }
    
    @Test func flushEmitsPendingSpeech() async {
        let vad = VoiceActivityDetector(minSpeechDurationSeconds: 0.1)
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        for _ in 0..<5 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        vad.flush()
        
        #expect(await waitForSegments(recorder, count: 1))
        #expect(abs((recorder.snapshot.first?.duration ?? 0) - 0.5) < 0.001)
    }
    
    @Test func flushOnEmptyBufferDoesNothing() async {
        let vad = VoiceActivityDetector()
        let recorder = SegmentRecorder()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        vad.flush()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.count == 0)
    }
    
    @Test func longSpeechIsSplitAtMaximumDuration() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.1,
            silenceThresholdSeconds: 0.6,
            minSpeechDurationSeconds: 0.1,
            maxSpeechDurationSeconds: 0.3
        )
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        // Three continuous 100 ms chunks cross the 300 ms cap.
        for _ in 0..<3 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        
        #expect(await waitForSegments(recorder, count: 1))
        let segment = recorder.snapshot.first
        #expect(abs((segment?.duration ?? 0) - 0.3) < 0.001)
        #expect(segment?.pcm.count == 3 * chunk.count)
    }
    
    @Test func energyAtThresholdCountsAsSpeech() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.25,
            silenceThresholdSeconds: 0.2,
            minSpeechDurationSeconds: 0.1
        )
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        for _ in 0..<2 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.25)
        }
        for _ in 0..<2 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        
        #expect(await waitForSegments(recorder, count: 1))
    }
    
    @Test func preRollKeepsWordOnsets() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.1,
            silenceThresholdSeconds: 0.21,
            minSpeechDurationSeconds: 0.1,
            preRollSeconds: 0.2
        )
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        // 200 ms of silence before speech becomes the pre-roll.
        for _ in 0..<2 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        // 300 ms of speech, then the 200 ms of silence that closes the segment.
        for _ in 0..<3 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        for _ in 0..<2 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        
        #expect(recorder.count == 1)
        let segment = recorder.snapshot.first
        // 200 ms pre-roll + 300 ms speech + 200 ms trailing silence.
        #expect(segment?.pcm.count == 7 * chunk.count)
        #expect(abs((segment?.duration ?? 0) - 0.7) < 0.001)
    }
    
    @Test func preRollIsBounded() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.1,
            silenceThresholdSeconds: 0.21,
            minSpeechDurationSeconds: 0.1,
            preRollSeconds: 0.15
        )
        let recorder = SegmentRecorder()
        let chunk = chunk()
        vad.onSpeechSegmentCompleted = { pcm, duration in
            recorder.record(pcm, duration)
        }
        
        // 500 ms of silence, of which only the last 150 ms is retained.
        for _ in 0..<5 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        for _ in 0..<3 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        for _ in 0..<2 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }
        
        #expect(recorder.count == 1)
        let segment = recorder.snapshot.first
        // 150 ms pre-roll + 300 ms speech + 200 ms trailing silence.
        #expect(abs((segment?.duration ?? 0) - 0.65) < 0.001)
    }

    @Test func captureBoundaryTimestampIsRecordedAtSpeechOnset() async {
        let vad = VoiceActivityDetector(
            energyThreshold: 0.1,
            silenceThresholdSeconds: 0.21,
            minSpeechDurationSeconds: 0.1,
            preRollSeconds: 0.1
        )
        let chunk = chunk()
        var recordedTimestamp: Date?
        vad.onSpeechSegmentWithTimestampCompleted = { pcm, duration, timestamp in
            recordedTimestamp = timestamp
        }

        let beforeOnset = Date()
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<3 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.5)
        }
        for _ in 0..<3 {
            vad.processChunk(pcmData: chunk, rmsEnergy: 0.0)
        }

        #expect(recordedTimestamp != nil)
        if let ts = recordedTimestamp {
            #expect(ts >= beforeOnset.addingTimeInterval(-0.2))
            #expect(ts <= Date())
        }
    }
}
