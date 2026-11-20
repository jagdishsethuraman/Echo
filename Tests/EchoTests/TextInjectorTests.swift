import AppKit
import Foundation
import Testing
@testable import Echo

@Suite("TextInjector")
struct TextInjectorTests {
    /// Simulates a target app that refuses both synthetic paste and typing.
    private final class FailingEventPoster: EventPosterProtocol, @unchecked Sendable {
        func postCmdV() -> Bool { false }
        func typeUnicodeString(_ string: String) -> Bool { false }
    }

    /// Simulates a concurrent copy occurring on the pasteboard while paste is executing.
    private final class ConcurrentCopyingPoster: EventPosterProtocol, @unchecked Sendable {
        private let pasteboard: PasteboardProtocol
        init(pasteboard: PasteboardProtocol) { self.pasteboard = pasteboard }
        func postCmdV() -> Bool {
            _ = pasteboard.setString("user copied something else during paste", forType: .string)
            return true
        }
        func typeUnicodeString(_ string: String) -> Bool { false }
    }

    private func makeInjector(
        pasteboard: InMemoryPasteboard = InMemoryPasteboard(),
        poster: EventPosterProtocol = MockEventPoster(),
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
    
    @Test func defaultOrderUsesSyntheticPaste() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(text: "hello world")
        
        #expect(result.success)
        #expect(result.method == .syntheticPaste)
        #expect(pasteboard.string(forType: .string) == "old clipboard")
        #expect(poster.postedCount == 1)
        #expect(poster.typedCount == 0)
    }

    @Test func typingOrderUsesDirectTypingForShortText() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(
            text: "hello world",
            options: InjectionOptions(order: .axDirectThenTypingThenPaste)
        )
        
        #expect(result.success)
        #expect(result.method == .directTyping)
        #expect(pasteboard.string(forType: .string) == "old clipboard")
        #expect(poster.typedCount == "Hello world ".count)
        #expect(poster.postedCount == 0)
    }
    
    @Test func restoreClipboardPreservesOriginalContent() async {
        let pasteboard = InMemoryPasteboard(initialString: "crucial user clipboard content")
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(
            text: "temporary dictated snippet",
            options: InjectionOptions(restorePreviousClipboard: true)
        )
        
        #expect(result.success)
        #expect(result.method == .syntheticPaste)
        #expect(pasteboard.string(forType: .string) == "crucial user clipboard content")
    }

    @Test func restoreClipboardPreservesNewerConcurrentCopy() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let poster = ConcurrentCopyingPoster(pasteboard: pasteboard)
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(
            text: "temporary dictated snippet",
            options: InjectionOptions(restorePreviousClipboard: true)
        )
        
        #expect(result.success)
        #expect(result.method == .syntheticPaste)
        #expect(pasteboard.string(forType: .string) == "user copied something else during paste")
    }

    @Test func systemEventPosterHandlesEmojiAndGraphemeClusters() {
        let poster = SystemEventPoster()
        // Running in CI / test process without CGEventSource access returns false, or true if permitted.
        // Crucially, it must execute character iteration over multi-byte emojis without crashing or splitting surrogates.
        _ = poster.typeUnicodeString("Echo 🎙️ 👋🏽")
    }
    
    @Test func pasteIsUsedWhenDirectTypingIsDisabled() async {
        let pasteboard = InMemoryPasteboard()
        let poster = MockEventPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        
        let result = await injector.inject(
            text: "meeting notes",
            options: InjectionOptions(useDirectTyping: false, order: .axDirectThenTypingThenPaste)
        )
        
        #expect(result.success)
        #expect(result.method == .syntheticPaste)
        #expect(poster.postedCount == 1)
        #expect(poster.typedCount == 0)
        #expect(pasteboard.string(forType: .string) == nil)
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
        #expect(pasteboard.string(forType: .string) == nil)
    }
    
    @Test func restoringDisabledLeavesTranscriptOnClipboard() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let injector = makeInjector(pasteboard: pasteboard)
        
        _ = await injector.inject(
            text: "copied text",
            options: InjectionOptions(restorePreviousClipboard: false)
        )

        #expect(pasteboard.string(forType: .string) == "Copied text ")
    }

    @Test func accessibilityInjectionLeavesClipboardUntouched() async {
        let pasteboard = InMemoryPasteboard(initialString: "crucial user clipboard content")
        let poster = MockEventPoster()
        let injector = TextInjector(
            pasteboard: pasteboard,
            eventPoster: poster,
            isAccessibilityTrusted: { true },
            accessibilityInjector: { _ in true }
        )
        
        let result = await injector.inject(text: "hello world")

        #expect(result.success)
        #expect(result.method == .accessibilityDirect)
        #expect(pasteboard.string(forType: .string) == "crucial user clipboard content")
        #expect(pasteboard.changeCount == 1)
        #expect(poster.postedCount == 0)
        #expect(poster.typedCount == 0)
    }

    @Test func failedFallbacksKeepTranscriptOnClipboard() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let injector = makeInjector(pasteboard: pasteboard, poster: FailingEventPoster())

        let result = await injector.inject(text: "copied text")

        #expect(result.success)
        #expect(result.method == .clipboardOnly)
        // Nothing reached the focused app, so the transcript must survive on
        // the clipboard for a manual paste.
        #expect(pasteboard.string(forType: .string) == "Copied text ")
    }

    @Test func writeToClipboardPlacesTextAndIncrementsChangeCount() {
        let pasteboard = InMemoryPasteboard(initialString: "before")
        let injector = makeInjector(pasteboard: pasteboard)

        let initialChangeCount = pasteboard.changeCount
        let newChangeCount = injector.writeToClipboard("new clipboard text")

        #expect(pasteboard.string(forType: .string) == "new clipboard text")
        #expect(newChangeCount > initialChangeCount)
    }
}
