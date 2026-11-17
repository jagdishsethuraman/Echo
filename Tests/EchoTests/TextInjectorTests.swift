import AppKit
import Foundation
import Testing
@testable import Echo

@Suite("TextInjector")
struct TextInjectorTests {
    private func makeInjector(
        pasteboard: InMemoryPasteboard = InMemoryPasteboard(),
        poster: MockEventPoster = MockEventPoster(),
        trusted: Bool = false
    ) -> TextInjector {
        TextInjector(
            pasteboard: pasteboard,
            eventPoster: poster,
            isAccessibilityTrusted: { trusted }
        )
    }
    
    // MARK: - Formatting
    
    @Test func capitalizesFirstLetterAndSentences() {
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("hello world") == "Hello world")
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("hello. next one? and more! done") == "Hello. Next one? And more! Done")
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("   spaced   ") == "Spaced")
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("") == "")
    }
    
    @Test func fixesPronounsAndProductNames() {
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("i think i'm right") == "I think I'm right")
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("use mac os on the iphone") == "Use macOS on the iPhone")
        #expect(TextInjector.formatSentencePunctuationAndCapitalization("watch youtube") == "Watch YouTube")
    }
    
    @Test func prepareTextAppliesOptions() {
        let injector = makeInjector()
        
        #expect(injector.prepareText("  hello world  ") == "Hello world ")
        #expect(injector.prepareText("already spaced ") == "Already spaced ")
        #expect(injector.prepareText(
            "  no changes  ",
            options: InjectionOptions(addTrailingSpace: false, autoCapitalizeFirstLetter: false)
        ) == "no changes")
        #expect(injector.prepareText("   ") == "")
    }
    
    // MARK: - Injection Cascade
    
    @Test func emptyTranscriptIsNotInjected() async {
        let pasteboard = InMemoryPasteboard(initialString: "previous")
        let injector = makeInjector(pasteboard: pasteboard)
        
        let result = await injector.inject(text: "   \n ")
        
        #expect(result.success == false)
        #expect(result.method == .clipboardOnly)
        #expect(pasteboard.string(forType: .string) == "previous")
    }
    
    @Test func shortTranscriptIsTypedDirectly() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(text: "hello world")
        
        #expect(result.success)
        #expect(result.method == .directTyping)
        #expect(pasteboard.string(forType: .string) == "Hello world ")
        #expect(poster.typedCount == "Hello world ".count)
        #expect(poster.postedCount == 0)
    }
    
    @Test func pasteIsUsedWhenDirectTypingIsDisabled() async {
        let pasteboard = InMemoryPasteboard()
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(
            text: "meeting notes",
            options: InjectionOptions(useDirectTyping: false)
        )
        
        #expect(result.success)
        #expect(result.method == .syntheticPaste)
        #expect(poster.postedCount == 1)
        #expect(poster.typedCount == 0)
        #expect(pasteboard.string(forType: .string) == "Meeting notes ")
    }
    
    @Test func longTranscriptSkipsDirectTyping() async {
        let pasteboard = InMemoryPasteboard()
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let longText = String(repeating: "a", count: 320)
        let result = await injector.inject(text: longText)
        
        #expect(result.success)
        #expect(result.method == .syntheticPaste)
        #expect(poster.typedCount == 0)
        #expect(poster.postedCount == 1)
        #expect(pasteboard.string(forType: .string) == "A" + String(repeating: "a", count: 319) + " ")
    }
    
    @Test func allPathsKeepTranscriptOnClipboard() async {
        // Even when AX is unavailable, every method leaves the prepared text
        // on the pasteboard so nothing is lost if typing or pasting fails.
        let pasteboard = InMemoryPasteboard()
        let injector = makeInjector(pasteboard: pasteboard)
        
        _ = await injector.inject(text: "copied text")
        
        #expect(pasteboard.string(forType: .string) == "Copied text ")
        #expect(pasteboard.changeCount > 0)
    }
}
