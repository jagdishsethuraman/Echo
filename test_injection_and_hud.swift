import Foundation
import AppKit

@main
struct TestRunner {
    static func main() async {
        let testInput = "hello, hello. can you see what i'm trying to convey? and i see that uh the typing interface is like colluded with small letters which i'm trying to say. doesn't look that great. and also i see a box around the pill where the speaking pill i would say um is good to see what i'm trying to say but i only see like ending of each word which is not like uh very cool. so i want you to continue tracing that into like a complete sentence and give me the option to update it."

        let formatted = TextInjector.formatSentencePunctuationAndCapitalization(testInput)

        print("--- RAW INPUT ---")
        print(testInput)
        print("\n--- FORMATTED OUTPUT ---")
        print(formatted)

        // Assertions
        assert(formatted.hasPrefix("Hello, hello."), "Must capitalize initial word")
        assert(formatted.contains("Can you see what I'm trying to convey?"), "Must capitalize sentence after ? and I'm")
        assert(formatted.contains("And I see that"), "Must capitalize And and I")
        assert(formatted.contains("Doesn't look that great."), "Must capitalize sentence start")
        assert(formatted.contains("So I want you to"), "Must capitalize sentence start and I")

        print("\n✓ ALL 5 SENTENCE FORMATTING ASSERTIONS PASSED!")

        // Test TextInjector injection with MockEventPoster and InMemoryPasteboard
        let mockPasteboard = InMemoryPasteboard()
        let mockPoster = MockEventPoster()
        let injector = TextInjector(pasteboard: mockPasteboard, eventPoster: mockPoster)

        let result = await injector.inject(text: testInput)
        assert(result.success == true, "Injection must succeed")
        assert(mockPasteboard.string(forType: .string)?.hasPrefix("Hello, hello.") == true, "Clipboard must receive capitalized text")
        assert(mockPoster.typedCount > 0 || mockPoster.postedCount > 0, "Poster must receive typing or Cmd+V")
        print("✓ INJECTION PIPELINE ASSERTIONS PASSED (Method: \(result.method.rawValue))")
    }
}
