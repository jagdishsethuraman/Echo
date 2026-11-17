import AppKit
import Foundation

@main
struct InjectionVerificationTest {
    static func main() async {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  ECHO — Text Injection & Direct Typing Verification")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        let mockPasteboard = InMemoryPasteboard(initialString: "old clipboard content")
        let mockEventPoster = MockEventPoster()
        let injector = TextInjector(pasteboard: mockPasteboard, eventPoster: mockEventPoster)
        
        // Test 1: Preparation
        let sample = "   hello world this is an echo live dictation test   "
        let prepared = injector.prepareText(sample)
        assert(prepared == "hello world this is an echo live dictation test ", "Trailing space formatting failed")
        print("[1/4] Text preparation & trailing space: PASSED")
        
        // Test 2: Direct Unicode Typing
        let result = await injector.inject(text: sample, options: InjectionOptions(useDirectTyping: true))
        assert(result.success, "Injection reported failure")
        assert(result.method == .directTyping, "Expected direct typing method")
        assert(mockEventPoster.typedCount == prepared.count, "Did not type characters directly")
        print("[2/4] Direct Unicode typing: PASSED (\(mockEventPoster.typedCount) chars typed)")
        
        // Test 3: Clipboard Retention
        let clipboardContent = mockPasteboard.string(forType: .string)
        assert(clipboardContent == prepared, "Transcript was erased from clipboard!")
        print("[3/4] Clipboard retention: PASSED (Clipboard preserved: \"\(clipboardContent!)\")")
        
        // Test 4: Meeting Coordinator Append
        let coord = MeetingCoordinator(phononRunner: PhononProcessRunner())
        coord.appendDictation(text: "Live speech utterance", duration: 1.5)
        
        let segments = coord.activeSession?.segments ?? []
        assert(segments.count == 1, "Dictation not appended to meeting session")
        assert(segments.first?.text == "Live speech utterance", "Segment text mismatch")
        assert(segments.first?.speaker == .you, "Speaker track mismatch")
        print("[4/4] Meeting Studio stream unification: PASSED (Session has \(segments.count) utterance)")
        
        print("\n  ALL VERIFICATIONS PASSED: 100% OPERATIONAL")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
