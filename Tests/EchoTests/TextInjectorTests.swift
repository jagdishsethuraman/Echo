import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import Echo

@Suite("TextInjector")
struct TextInjectorTests {
    /// Simulates a target app that refuses both synthetic paste and typing.
    private final class FailingEventPoster: EventPosterProtocol, @unchecked Sendable {
        func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool { false }
        func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult { .notPosted }
    }

    /// Simulates a concurrent copy occurring on the pasteboard while paste is executing.
    private final class ConcurrentCopyingPoster: EventPosterProtocol, @unchecked Sendable {
        private let pasteboard: PasteboardProtocol
        init(pasteboard: PasteboardProtocol) { self.pasteboard = pasteboard }
        func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool {
            _ = pasteboard.setString("user copied something else during paste", forType: .string)
            return true
        }
        func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult { .notPosted }
    }

    private final class PartialTypingPoster: EventPosterProtocol, @unchecked Sendable {
        var postedUnits: [[UInt16]] = []
        var pasteRequests = 0

        func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool {
            pasteRequests += 1
            return true
        }

        func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult {
            SystemEventPoster.postCharacters(in: string) { units in
                guard postedUnits.isEmpty else { return false }
                postedUnits.append(units)
                return true
            }
        }
    }

    private final class SlowReadingPoster: EventPosterProtocol, @unchecked Sendable {
        let pasteboard: PasteboardProtocol
        var delayedRead: Task<String?, Never>?
        var didPost: (() -> Void)?

        init(pasteboard: PasteboardProtocol) { self.pasteboard = pasteboard }

        func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool {
            guard ifFocused() else { return false }
            delayedRead = Task { [pasteboard] in
                try? await Task.sleep(for: .milliseconds(120))
                return pasteboard.string(forType: .string)
            }
            didPost?()
            return true
        }

        func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult {
            .notPosted
        }
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

    @Test func systemEventPosterSendsWholeGraphemes() {
        var posted: [[UInt16]] = []
        let result = SystemEventPoster.postCharacters(in: "🎙️👋🏽e\u{301}") {
            posted.append($0)
            return true
        }

        #expect(result == .posted)
        #expect(posted == ["🎙️", "👋🏽", "e\u{301}"].map { Array($0.utf16) })
    }

    @Test func typingFailureLeavesOnlyTheUnpostedSuffixForManualPaste() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let poster = PartialTypingPoster()
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)
        let result = await injector.inject(
            text: "👋🏽e\u{301} hello",
            options: InjectionOptions(order: .axDirectThenTypingThenPaste)
        )

        #expect(poster.postedUnits == [Array("👋🏽".utf16)])
        #expect(poster.pasteRequests == 0)
        #expect(result.method == .partialTyping)
        #expect(!result.insertionConfirmed)
        #expect(result.clipboardReady)
        #expect(result.remainingText == "e\u{301} hello ")
        #expect(pasteboard.string(forType: .string) == "e\u{301} hello ")
    }

    @Test @MainActor func changedFieldInTheSameProcessUsesManualPaste() async {
        let pid = getpid()
        // The production comparison uses AX object identity. Distinct AX objects
        // with the same process ID stand in for two focused controls.
        let original = FocusedDictationField(pid: pid, element: AXUIElementCreateApplication(pid))
        let other = FocusedDictationField(pid: pid, element: AXUIElementCreateSystemWide())
        let equivalent = FocusedDictationField(pid: pid, element: AXUIElementCreateApplication(pid))
        #expect(original == equivalent)
        #expect(original != other)

        let pasteboard = InMemoryPasteboard()
        let poster = MockEventPoster()
        let injector = TextInjector(
            pasteboard: pasteboard,
            eventPoster: poster,
            accessibilityInjector: { _ in
                Issue.record("Attempted an AX write after focus moved")
                return true
            }
        )
        let result = await injector.injectDictation(text: "private dictation", target: original, currentField: { other })

        #expect(result.method == .clipboardOnly)
        #expect(result.focusChanged)
        #expect(result.clipboardReady)
        #expect(poster.postedCount == 0)
        #expect(poster.typedCount == 0)
        #expect(pasteboard.string(forType: .string) == "Private dictation ")
    }

    @Test @MainActor func slowPasteTargetReadsBeforeRestoreWithoutConfirmingInsertion() async {
        let pasteboard = InMemoryPasteboard(initialString: "old clipboard")
        let poster = SlowReadingPoster(pasteboard: pasteboard)
        let result = await makeInjector(pasteboard: pasteboard, poster: poster).inject(text: "follow up")

        let observed = await poster.delayedRead?.value
        #expect(observed == "Follow up ")
        #expect(result.method == .syntheticPaste)
        #expect(!result.insertionConfirmed)
        #expect(pasteboard.string(forType: .string) == "old clipboard")
    }

    @Test @MainActor func overlappingPasteRequestsKeepEachTargetsClipboardContents() async {
        let pasteboard = InMemoryPasteboard(initialString: "user clipboard")
        let poster = SlowReadingPoster(pasteboard: pasteboard)
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)

        let (posts, continuation) = AsyncStream<Void>.makeStream()
        poster.didPost = { continuation.yield(()) }
        var posted = posts.makeAsyncIterator()
        let first = Task { await injector.inject(text: "first") }
        _ = await posted.next()
        let firstRead = poster.delayedRead

        let second = Task { await injector.inject(text: "second") }
        _ = await posted.next()
        let secondRead = poster.delayedRead
        continuation.finish()

        #expect(await firstRead?.value == "First ")
        #expect(await secondRead?.value == "Second ")
        #expect(await first.value.method == .syntheticPaste)
        #expect(await second.value.method == .syntheticPaste)
        #expect(pasteboard.string(forType: .string) == "user clipboard")
    }

    @Test @MainActor func deliveryWaitChecksWhetherItsRecordingStillOwnsTheResult() async {
        let pasteboard = InMemoryPasteboard(initialString: "user clipboard")
        let poster = SlowReadingPoster(pasteboard: pasteboard)
        let injector = makeInjector(pasteboard: pasteboard, poster: poster)

        let (posts, continuation) = AsyncStream<Void>.makeStream()
        poster.didPost = { continuation.yield(()) }
        var posted = posts.makeAsyncIterator()
        let first = Task { await injector.inject(text: "first") }
        _ = await posted.next()
        continuation.finish()

        let result = await injector.injectDictation(text: "obsolete", target: nil, stillOwnsDelivery: { false })
        #expect(result.method == .clipboardOnly)
        #expect(!result.clipboardReady)
        #expect(await first.value.method == .syntheticPaste)
        #expect(pasteboard.string(forType: .string) == "user clipboard")
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

    @Test func writeToClipboardPlacesTextAndIncrementsChangeCount() throws {
        let pasteboard = InMemoryPasteboard(initialString: "before")
        let injector = makeInjector(pasteboard: pasteboard)

        let initialChangeCount = pasteboard.changeCount
        let newChangeCount = try #require(injector.writeToClipboard("new clipboard text"))

        #expect(pasteboard.string(forType: .string) == "new clipboard text")
        #expect(newChangeCount > initialChangeCount)
    }
}
