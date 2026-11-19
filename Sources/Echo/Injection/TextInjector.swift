import AppKit
import ApplicationServices

// MARK: - Protocols for Testability & Sandbox Compatibility

public protocol PasteboardProtocol: AnyObject, Sendable {
    var changeCount: Int { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    func clearContents() -> Int
    func declareTypes(_ newTypes: [NSPasteboard.PasteboardType], owner: Any?) -> Int
    /// Snapshot every item (text, images, files, …) so a successful injection
    /// can put the user's clipboard back exactly as it was.
    func snapshotItems() -> [NSPasteboardItem]?
    func restoreItems(_ items: [NSPasteboardItem]) -> Bool
}

extension NSPasteboard: PasteboardProtocol, @unchecked @retroactive Sendable {
    public func snapshotItems() -> [NSPasteboardItem]? {
        guard let items = pasteboardItems else { return nil }
        // Copy the data out of each item. The objects returned by
        // `pasteboardItems` are backed by the pasteboard and may become
        // unreadable once its contents change.
        return items.map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    public func restoreItems(_ items: [NSPasteboardItem]) -> Bool {
        clearContents()
        guard !items.isEmpty else { return true }
        return writeObjects(items)
    }
}

public protocol EventPosterProtocol: AnyObject, Sendable {
    func postCmdV() -> Bool
    func typeUnicodeString(_ string: String) -> Bool
}

public final class SystemEventPoster: EventPosterProtocol, @unchecked Sendable {
    public init() {}
    
    /// Type characters directly into the active text field with smooth typing cadency
    public func typeUnicodeString(_ string: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        
        usleep(20_000) // 20ms settle delay
        
        for character in string {
            var units = Array(character.utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            
            keyDown.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            keyUp.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            
            // Clear any lingering modifier flags (Control/Option/Shift)
            keyDown.flags = []
            keyUp.flags = []
            
            // Post directly to session event tap
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            
            // 1.5ms cadency for fast yet reliable typing
            usleep(1500)
        }
        return true
    }
    
    /// Synthesize Cmd+V paste keystroke
    public func postCmdV() -> Bool {
        let kVK_ANSI_V: CGKeyCode = 0x09
        
        guard let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        
        // 25ms settle delay to ensure physical hotkey release is cleared by WindowServer
        usleep(25_000)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false) else {
            return false
        }
        
        // Isolate to Command flag only (scrubbing physical Control/Option key state)
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cgSessionEventTap)
        usleep(25_000) // 25ms hold delay
        keyUp.post(tap: .cgSessionEventTap)
        
        return true
    }
}

// In-memory mock pasteboard for hermetic testing
public final class InMemoryPasteboard: PasteboardProtocol, @unchecked Sendable {
    private var storage: [NSPasteboard.PasteboardType: String] = [:]
    private var _changeCount: Int = 0
    private let lock = NSLock()
    
    public init(initialString: String? = nil) {
        if let s = initialString {
            storage[.string] = s
            _changeCount = 1
        }
    }
    
    public var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _changeCount
    }
    
    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[type]
    }
    
    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage[type] = string
        _changeCount += 1
        return true
    }
    
    public func clearContents() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        _changeCount += 1
        return 0
    }
    
    public func declareTypes(_ newTypes: [NSPasteboard.PasteboardType], owner: Any?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _changeCount += 1
        return _changeCount
    }

    public func snapshotItems() -> [NSPasteboardItem]? {
        lock.lock()
        defer { lock.unlock() }
        guard !storage.isEmpty else { return nil }

        let item = NSPasteboardItem()
        for (type, value) in storage {
            item.setString(value, forType: type)
        }
        return [item]
    }

    public func restoreItems(_ items: [NSPasteboardItem]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        _changeCount += 1

        for item in items {
            if let value = item.string(forType: .string) {
                storage[.string] = value
            }
        }
        return true
    }
}

public final class MockEventPoster: EventPosterProtocol, @unchecked Sendable {
    public var postedCount: Int = 0
    public var typedCount: Int = 0
    
    public init() {}
    
    public func postCmdV() -> Bool {
        postedCount += 1
        return true
    }
    
    public func typeUnicodeString(_ string: String) -> Bool {
        typedCount += string.count
        return true
    }
}

// MARK: - Injection Models & Engine

public enum InjectionCascadeOrder: String, Sendable {
    case axDirectThenPasteThenTyping = "AX -> Cmd+V -> Type"
    case axDirectThenTypingThenPaste = "AX -> Type -> Cmd+V"
}

public struct InjectionOptions: Sendable {
    public var addTrailingSpace: Bool
    public var autoCapitalizeFirstLetter: Bool
    public var useDirectTyping: Bool
    public var restorePreviousClipboard: Bool
    public var order: InjectionCascadeOrder
    
    public init(
        addTrailingSpace: Bool = true,
        autoCapitalizeFirstLetter: Bool = true,
        useDirectTyping: Bool = true,
        restorePreviousClipboard: Bool = true,
        order: InjectionCascadeOrder = .axDirectThenPasteThenTyping
    ) {
        self.addTrailingSpace = addTrailingSpace
        self.autoCapitalizeFirstLetter = autoCapitalizeFirstLetter
        self.useDirectTyping = useDirectTyping
        self.restorePreviousClipboard = restorePreviousClipboard
        self.order = order
    }
}

public enum InjectionMethod: String, Sendable {
    case accessibilityDirect = "AXDirect"
    case directTyping = "DirectTyping"
    case syntheticPaste = "CmdVPaste"
    case clipboardOnly = "ClipboardOnly"
}

public final class TextInjector: @unchecked Sendable {
    private let pasteboard: PasteboardProtocol
    private let eventPoster: EventPosterProtocol
    private let isAccessibilityTrusted: () -> Bool
    private let accessibilityInjector: ((String) -> Bool)?
    
    public init(
        pasteboard: PasteboardProtocol = NSPasteboard.general,
        eventPoster: EventPosterProtocol = SystemEventPoster(),
        isAccessibilityTrusted: @escaping () -> Bool = { TextInjector.isAccessibilityTrusted() },
        accessibilityInjector: ((String) -> Bool)? = nil
    ) {
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.accessibilityInjector = accessibilityInjector
    }
    
    /// Non-intrusive check for Accessibility permission (NEVER prompts unless explicitly asked)
    public static func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            return AXIsProcessTrustedWithOptions(options)
        } else {
            return AXIsProcessTrusted()
        }
    }
    
    /// Intelligent sentence capitalization, pronoun fixes ("I", "I'm"), and proper spacing
    public static func formatSentencePunctuationAndCapitalization(_ text: String) -> String {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return "" }
        
        // 1. Capitalize first character
        if let first = str.first {
            str = first.uppercased() + str.dropFirst()
        }
        
        // 2. Capitalize letters following sentence terminators (. ! ? or newlines)
        if let regex = try? NSRegularExpression(pattern: "([.!?]\\s+)([a-z])", options: []) {
            let nsStr = str as NSString
            let matches = regex.matches(in: str, options: [], range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let letterRange = match.range(at: 2)
                let letter = nsStr.substring(with: letterRange).uppercased()
                let fullRange = match.range
                let prefix = nsStr.substring(with: match.range(at: 1))
                str = (str as NSString).replacingCharacters(in: fullRange, with: prefix + letter)
            }
        }
        
        // 3. Fix standalone pronoun 'i' and standard contractions
        let pronounMap: [(pattern: String, replacement: String)] = [
            ("\\bi\\b", "I"),
            ("\\bi'm\\b", "I'm"),
            ("\\bi'll\\b", "I'll"),
            ("\\bi've\\b", "I've"),
            ("\\bi'd\\b", "I'd"),
            ("\\bi'am\\b", "I'm"),
            ("\\bmac os\\b", "macOS"),
            ("\\bmacos\\b", "macOS"),
            ("\\biphone\\b", "iPhone"),
            ("\\bipad\\b", "iPad"),
            ("\\byoutube\\b", "YouTube")
        ]
        
        for (pattern, repl) in pronounMap {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                str = regex.stringByReplacingMatches(
                    in: str,
                    options: [],
                    range: NSRange(location: 0, length: (str as NSString).length),
                    withTemplate: repl
                )
            }
        }
        
        return str
    }
    
    /// Prepare and sanitize speech transcript before injection
    public func prepareText(_ text: String, options: InjectionOptions = InjectionOptions()) -> String {
        var processed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else { return "" }
        
        if options.autoCapitalizeFirstLetter {
            processed = Self.formatSentencePunctuationAndCapitalization(processed)
        }
        
        if options.addTrailingSpace && !processed.hasSuffix(" ") {
            processed += " "
        }
        
        return processed
    }
    
    /// Direct injection via macOS Accessibility API (instant value insertion)
    public func tryDirectAccessibilityInjection(text: String) -> Bool {
        guard isAccessibilityTrusted() else { return false }
        
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        
        guard result == .success,
              let focusedElement = focusedElementValue,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return false
        }
        
        let element = focusedElement as! AXUIElement
        
        // Try selected text replacement first
        var isSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable) == .success, isSettable.boolValue {
            let setResult = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if setResult == .success {
                return true
            }
        }
        
        return false
    }
    
    /// Master injection pipeline: AX direct first (no clipboard interaction),
    /// then Paste/Type fallbacks using the clipboard, restoring the user's
    /// previous clipboard contents (INJ-03) after a successful fallback.
    @discardableResult
    public func inject(text: String, options: InjectionOptions = InjectionOptions()) async -> (success: Bool, method: InjectionMethod) {
        let prepared = prepareText(text, options: options)
        guard !prepared.isEmpty else { return (false, .clipboardOnly) }
        
        // 1. Path 1: AX Direct attribute injection. This never needs the
        // clipboard, so a successful AX insertion leaves it untouched.
        if performAccessibilityInjection(text: prepared) {
            return (true, .accessibilityDirect)
        }
        
        // 2. Snapshot the clipboard only now that a clipboard-based fallback
        // is actually required. `nil` here means the clipboard was empty.
        let snapshot = options.restorePreviousClipboard ? pasteboard.snapshotItems() : nil

        // 3. Put the prepared transcript on the clipboard for the fallbacks.
        let expectedChangeCount = writeToClipboard(prepared)

        // 4. Follow the configured cascade order.
        switch options.order {
        case .axDirectThenPasteThenTyping:
            // Synthetic Cmd+V paste first (fast, universal, reliable).
            if eventPoster.postCmdV() {
                restoreClipboard(snapshot, expectedChangeCount: expectedChangeCount, enabled: options.restorePreviousClipboard, afterPaste: true)
                return (true, .syntheticPaste)
            }
            
            // Fallback to direct typing if enabled and text is reasonably short.
            if options.useDirectTyping && prepared.count < 300,
               eventPoster.typeUnicodeString(prepared) {
                restoreClipboard(snapshot, expectedChangeCount: expectedChangeCount, enabled: options.restorePreviousClipboard, afterPaste: false)
                return (true, .directTyping)
            }
            
        case .axDirectThenTypingThenPaste:
            // Direct typing first if enabled and text is reasonably short.
            if options.useDirectTyping && prepared.count < 300,
               eventPoster.typeUnicodeString(prepared) {
                restoreClipboard(snapshot, expectedChangeCount: expectedChangeCount, enabled: options.restorePreviousClipboard, afterPaste: false)
                return (true, .directTyping)
            }
            
            // Fallback to Cmd+V paste.
            if eventPoster.postCmdV() {
                restoreClipboard(snapshot, expectedChangeCount: expectedChangeCount, enabled: options.restorePreviousClipboard, afterPaste: true)
                return (true, .syntheticPaste)
            }
        }
        
        // 5. Every synthetic path failed: leave the transcript on the clipboard
        // so the user can still paste it manually. The previous contents are
        // intentionally not restored, otherwise the fallback text would vanish.
        return (true, .clipboardOnly)
    }

    /// Runs the accessibility injector seam if one was supplied (tests), or the
    /// real AX attribute injection otherwise.
    private func performAccessibilityInjection(text: String) -> Bool {
        if let accessibilityInjector {
            return accessibilityInjector(text)
        }
        return tryDirectAccessibilityInjection(text: text)
    }

    @discardableResult
    private func writeToClipboard(_ text: String) -> Int {
        _ = pasteboard.clearContents()
        _ = pasteboard.declareTypes([.string], owner: nil)
        _ = pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Restores the snapshot taken before the clipboard was overwritten. When
    /// restoration is disabled the transcript is left in place. A `nil`
    /// snapshot means the clipboard was empty, so it is cleared again.
    /// If the pasteboard's `changeCount` has changed since the fallback was
    /// written, another process or user copied newer content; in that case,
    /// we do not clobber the user's newer clipboard state.
    private func restoreClipboard(_ snapshot: [NSPasteboardItem]?, expectedChangeCount: Int, enabled: Bool, afterPaste: Bool) {
        guard enabled else { return }
        if afterPaste {
            // Give the target app time to read the pasteboard before restoring.
            usleep(60_000)
        }
        guard pasteboard.changeCount == expectedChangeCount else {
            return
        }
        if let snapshot {
            _ = pasteboard.restoreItems(snapshot)
        } else {
            _ = pasteboard.clearContents()
        }
    }
}
