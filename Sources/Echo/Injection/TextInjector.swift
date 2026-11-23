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

public enum UnicodeTypingResult: Equatable, Sendable {
    case posted
    case partial(remainingText: String)
    case notPosted
}

public protocol EventPosterProtocol: AnyObject, Sendable {
    func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool
    func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult
}

public final class SystemEventPoster: EventPosterProtocol, @unchecked Sendable {
    public init() {}

    /// Reports the unposted suffix at a whole-character boundary.
    public func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult {
        guard let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) else {
            return .notPosted
        }

        usleep(20_000) // Allow the physical hotkey release to reach WindowServer.
        return Self.postCharacters(in: string) { units in
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false),
                  ifFocused() else { return false }

            units.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            keyDown.flags = []
            keyUp.flags = []
            post(keyDown, targetPID: targetPID)
            post(keyUp, targetPID: targetPID)
            usleep(1_500)
            return true
        }
    }

    static func postCharacters(in string: String, post: ([UInt16]) -> Bool) -> UnicodeTypingResult {
        for index in string.indices {
            guard post(Array(string[index].utf16)) else {
                return index == string.startIndex ? .notPosted : .partial(remainingText: String(string[index...]))
            }
        }
        return .posted
    }

    /// A posted shortcut provides no acknowledgment from the destination.
    public func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool {
        let kVK_ANSI_V: CGKeyCode = 0x09
        guard let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        usleep(25_000) // Allow the physical hotkey release to reach WindowServer.
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false),
              ifFocused() else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        post(keyDown, targetPID: targetPID)
        usleep(25_000)
        post(keyUp, targetPID: targetPID)
        return true
    }

    private func post(_ event: CGEvent, targetPID: pid_t?) {
        if let targetPID {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }
}

/// AX object equality distinguishes separate fields in the same application.
struct FocusedDictationField: Equatable {
    let pid: pid_t
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }

    // Chromium editors may expose only their window until an assistive client
    // requests the editable accessibility tree. Prime it before dictation begins.
    @MainActor static func prepareEditor(_ app: NSRunningApplication?) {
        guard let app, let id = app.bundleIdentifier,
              ["com.openai.codex", "com.anthropic.claudefordesktop", "com.microsoft.teams2"].contains(id),
              AXIsProcessTrusted() else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron and Chromium shells expose different activation attributes.
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            if AXUIElementSetAttributeValue(root, attribute as CFString, kCFBooleanTrue) == .success { break }
        }
    }

    @MainActor static func current() -> Self? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        // Ask the owning app which field it focuses. A web editor's AX element
        // can belong to its renderer, while keyboard events go to the host PID.
        let root = AXUIElementCreateApplication(pid)
        let element = TextInjector.accessibilityFocusedElement(in: root)
        func field(_ candidate: AXUIElement?) -> Self? {
            guard let candidate, let editor = editableField(for: candidate),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
            return Self(pid: pid, element: editor)
        }
        if let scoped = field(element) { return scoped }
        guard let system = TextInjector.accessibilityFocusedElement() else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(system, &owner) == .success, owner == pid else { return nil }
        return field(system)
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    static func editableField(for focused: AXUIElement,
                              read: (AXUIElement, String) -> AnyObject? = attribute) -> AXUIElement? {
        func isEditor(_ element: AXUIElement) -> Bool {
            guard let role = read(element, kAXRoleAttribute) as? String,
                  read(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return false }
            if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { return true }
            return role == kAXGroupRole && read(element, "AXEditable") as? Bool == true
        }
        if isEditor(focused) { return focused }
        // Chromium can focus an inline node and name its owning editable field.
        // Never promote a whole web area or window to a delivery target.
        guard read(focused, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let value = read(focused, "AXEditableAncestor"),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let ancestor = value as! AXUIElement
        return isEditor(ancestor) ? ancestor : nil
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
    
    public func postCmdV(targetPID: pid_t?, ifFocused: () -> Bool) -> Bool {
        guard ifFocused() else { return false }
        postedCount += 1
        return true
    }
    
    public func typeUnicodeString(_ string: String, targetPID: pid_t?, ifFocused: () -> Bool) -> UnicodeTypingResult {
        guard ifFocused() else { return .notPosted }
        typedCount += string.count
        return .posted
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
    case partialTyping = "PartialTyping"
    case clipboardOnly = "ClipboardOnly"
}

public struct InjectionResult: Sendable {
    public let method: InjectionMethod
    public let clipboardReady: Bool
    public let remainingText: String?
    public let focusChanged: Bool

    /// An AX write is the only path that acknowledges insertion.
    public var insertionConfirmed: Bool { method == .accessibilityDirect }

    /// Indicates that an action was taken or recovery text is available.
    public var success: Bool { method != .clipboardOnly || clipboardReady }

    fileprivate init(
        _ method: InjectionMethod,
        clipboardReady: Bool = false,
        remainingText: String? = nil,
        focusChanged: Bool = false
    ) {
        self.method = method
        self.clipboardReady = clipboardReady
        self.remainingText = remainingText
        self.focusChanged = focusChanged
    }
}

public final class TextInjector: @unchecked Sendable {
    private let pasteboard: PasteboardProtocol
    private let eventPoster: EventPosterProtocol
    private let isAccessibilityTrusted: () -> Bool
    private let accessibilityInjector: ((String) -> Bool)?

    private struct ClipboardLease {
        let originalItems: [NSPasteboardItem]?
        let changeCount: Int
    }

    @MainActor private var pendingPaste: Task<Void, Never>?
    
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
    
    static func accessibilityFocusedElement(in root: AXUIElement = AXUIElementCreateSystemWide()) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    /// Direct injection via macOS Accessibility API (instant value insertion).
    public func tryDirectAccessibilityInjection(text: String) -> Bool {
        guard isAccessibilityTrusted(), let element = Self.accessibilityFocusedElement() else { return false }
        return insertSelectedText(text, in: element)
    }

    private func insertSelectedText(_ text: String, in element: AXUIElement, ifFocused: () -> Bool = { true }) -> Bool {
        var isSettable: DarwinBoolean = false
        let attribute = kAXSelectedTextAttribute as CFString
        guard AXUIElementIsAttributeSettable(element, attribute, &isSettable) == .success,
              isSettable.boolValue, ifFocused() else { return false }
        return AXUIElementSetAttributeValue(element, attribute, text as CFTypeRef) == .success
    }

    @MainActor @discardableResult
    public func inject(text: String, options: InjectionOptions = InjectionOptions()) async -> InjectionResult {
        await inject(text: text, options: options, target: nil)
    }

    @MainActor
    func injectDictation(
        text: String,
        target: FocusedDictationField?,
        stillOwnsDelivery: () -> Bool = { true },
        currentField: (() -> FocusedDictationField?)? = nil
    ) async -> InjectionResult {
        await inject(text: text, options: InjectionOptions(), target: target, stillOwnsDelivery: stillOwnsDelivery) {
            guard let target else { return false }
            if let currentField { return target == currentField() }
            return target == FocusedDictationField.current()
        }
    }

    @MainActor
    private func inject(
        text: String,
        options: InjectionOptions,
        target: FocusedDictationField?,
        stillOwnsDelivery: () -> Bool = { true },
        ifFocused: () -> Bool = { true }
    ) async -> InjectionResult {
        // Another target may still be reading Echo's previous paste request.
        while let pendingPaste { await pendingPaste.value }
        guard stillOwnsDelivery() else { return InjectionResult(.clipboardOnly) }

        let prepared = prepareText(text, options: options)
        guard !prepared.isEmpty else { return InjectionResult(.clipboardOnly) }
        guard ifFocused() else {
            return InjectionResult(.clipboardOnly, clipboardReady: writeToClipboard(prepared) != nil, focusChanged: true)
        }

        let inserted: Bool
        if let accessibilityInjector {
            inserted = accessibilityInjector(prepared)
        } else if let target {
            inserted = insertSelectedText(prepared, in: target.element, ifFocused: ifFocused)
        } else {
            inserted = tryDirectAccessibilityInjection(text: prepared)
        }
        if inserted { return InjectionResult(.accessibilityDirect) }

        let pasteFirst = options.order == .axDirectThenPasteThenTyping
        var attemptedPaste: ClipboardLease?
        if pasteFirst {
            let attempt = beginPaste(prepared, target: target, restore: options.restorePreviousClipboard, ifFocused: ifFocused)
            if attempt.posted {
                return await completePaste(attempt.lease, restore: options.restorePreviousClipboard)
            }
            attemptedPaste = attempt.lease
        }

        if options.useDirectTyping && prepared.count < 300 && ifFocused() {
            switch eventPoster.typeUnicodeString(prepared, targetPID: target?.pid, ifFocused: ifFocused) {
            case .posted:
                if options.restorePreviousClipboard {
                    restoreClipboard(attemptedPaste)
                } else if attemptedPaste == nil {
                    _ = writeToClipboard(prepared)
                }
                return InjectionResult(.directTyping)
            case .partial(let remaining):
                // Retrying the original text would duplicate the posted prefix.
                let canCopy = attemptedPaste.map { pasteboard.changeCount == $0.changeCount } ?? true
                return InjectionResult(
                    .partialTyping,
                    clipboardReady: canCopy && writeToClipboard(remaining) != nil,
                    remainingText: remaining,
                    focusChanged: !ifFocused()
                )
            case .notPosted:
                break
            }
        }

        if !pasteFirst {
            let attempt = beginPaste(prepared, target: target, restore: options.restorePreviousClipboard, ifFocused: ifFocused)
            if attempt.posted {
                return await completePaste(attempt.lease, restore: options.restorePreviousClipboard)
            }
            attemptedPaste = attempt.lease
        }

        let copied: Bool
        if let attemptedPaste {
            copied = pasteboard.changeCount == attemptedPaste.changeCount
        } else {
            copied = writeToClipboard(prepared) != nil
        }
        return InjectionResult(.clipboardOnly, clipboardReady: copied, focusChanged: !ifFocused())
    }

    @MainActor
    private func beginPaste(
        _ text: String,
        target: FocusedDictationField?,
        restore: Bool,
        ifFocused: () -> Bool
    ) -> (posted: Bool, lease: ClipboardLease?) {
        let originalItems = restore ? pasteboard.snapshotItems() : nil
        guard let changeCount = writeToClipboard(text) else { return (false, nil) }
        let lease = ClipboardLease(originalItems: originalItems, changeCount: changeCount)
        guard ifFocused() else { return (false, lease) }
        let posted = eventPoster.postCmdV(targetPID: target?.pid) {
            ifFocused() && self.pasteboard.changeCount == changeCount
        }
        return (posted, lease)
    }

    @MainActor
    private func completePaste(_ lease: ClipboardLease?, restore: Bool) async -> InjectionResult {
        // Keep the temporary contents available for slow targets. The system
        // offers no acknowledgment that the target consumed the pasteboard.
        let transfer = Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(500))
            if restore { restoreClipboard(lease) }
            pendingPaste = nil
        }
        pendingPaste = transfer
        await transfer.value
        return InjectionResult(
            .syntheticPaste,
            clipboardReady: lease?.changeCount == pasteboard.changeCount
        )
    }

    @discardableResult
    public func writeToClipboard(_ text: String) -> Int? {
        _ = pasteboard.clearContents()
        _ = pasteboard.declareTypes([.string], owner: nil)
        guard pasteboard.setString(text, forType: .string) else { return nil }
        return pasteboard.changeCount
    }

    private func restoreClipboard(_ lease: ClipboardLease?) {
        guard let lease, pasteboard.changeCount == lease.changeCount else { return }
        if let items = lease.originalItems {
            _ = pasteboard.restoreItems(items)
        } else {
            _ = pasteboard.clearContents()
        }
    }
}
