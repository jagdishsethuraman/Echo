import Foundation
import Testing
@testable import Echo

@Suite("Dictation lifecycle")
struct DictationLifecycleTests {
    @Test @MainActor func delayedResultsCannotUpdateTheNextRecording() async throws {
        let lifecycle = DictationLifecycle()
        let firstMeeting = UUID()
        let secondMeeting = UUID()
        let first = lifecycle.start(meetingSessionID: firstMeeting, target: nil)
        first.isDecodingPreview = true
        first.audio.append(Data(repeating: 0, count: 16_000))
        let firstSnapshot = first.audio.snapshot()

        let (releases, continuation) = AsyncStream<Void>.makeStream()
        let oldDecode = Task { @MainActor in
            for await _ in releases { break }
            first.isDecodingPreview = false
            return lifecycle.acceptPreview(DictationPreview(text: "A", snapshot: firstSnapshot), for: first.id)
        }
        #expect(lifecycle.stop()?.id == first.id)

        let second = lifecycle.start(meetingSessionID: secondMeeting, target: nil)
        second.isDecodingPreview = true
        second.audio.append(Data(repeating: 0, count: 32_000))
        let secondPreview = DictationPreview(text: "B", snapshot: second.audio.snapshot())
        #expect(lifecycle.acceptPreview(secondPreview, for: second.id))
        #expect(!lifecycle.ownsDelivery(first.id))

        continuation.yield(())
        continuation.finish()
        let oldPreviewAccepted = await oldDecode.value
        #expect(!oldPreviewAccepted)
        #expect(second.preview == secondPreview)
        #expect(second.isDecodingPreview)
        #expect(first.meetingSessionID == firstMeeting)
        #expect(second.meetingSessionID == secondMeeting)

        #expect(lifecycle.stop()?.id == second.id)
        #expect(lifecycle.ownsDelivery(second.id))
        #expect(!lifecycle.ownsDelivery(first.id))
    }

    @Test func stalePreviewInShortRecordingRetainsActualCoverage() throws {
        let audio = AudioPCMBufferStore()
        audio.append(Data(repeating: 0, count: 64_000))
        let preview = DictationPreview(text: "Only the beginning", snapshot: audio.snapshot())
        audio.append(Data(repeating: 0, count: 32_000))

        let recovered = try #require(DictationTranscript(finalText: " ", totalBytes: audio.byteCount, preview: preview))
        #expect(recovered.text == "[Partial] Only the beginning")
        #expect(recovered.byteRange == 0..<64_000)
        #expect(recovered.duration == 2)
        #expect(recovered.recoveredFromPreview)
    }

    @Test func longRecordingRecoveryPreservesRollingRangeAndFullResultsTakePrecedence() throws {
        let second = AudioPCMBufferStore.bytesPerSecond
        let audio = AudioPCMBufferStore()
        audio.append(Data(repeating: 0, count: 28 * second))
        let preview = DictationPreview(text: "The visible tail", snapshot: audio.snapshot(maxBytes: 12 * second))
        audio.append(Data(repeating: 0, count: 2 * second))

        let recovered = try #require(DictationTranscript(finalText: "", totalBytes: audio.byteCount, preview: preview))
        #expect(preview.displayText == "… The visible tail")
        #expect(recovered.text == "[Partial] The visible tail")
        #expect(recovered.byteRange == (16 * second)..<(28 * second))
        #expect(recovered.startOffset == 16)
        #expect(recovered.duration == 12)

        let final = try #require(DictationTranscript(finalText: "Entire recording", totalBytes: audio.byteCount, preview: preview))
        #expect(final.text == "Entire recording")
        #expect(final.byteRange == 0..<(30 * second))
        #expect(final.duration == 30)
        #expect(!final.recoveredFromPreview)
    }
}
