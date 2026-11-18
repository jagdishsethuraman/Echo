import AppKit
import ApplicationServices

// MARK: - Protocols for Testability & Sandbox Compatibility

public protocol PasteboardProtocol: AnyObject, Sendable {
    var changeCount: Int { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    func clearContents() -> Int
    func declareTypes(_ newTypes: [NSPasteboard.PasteboardType], owner: Any?) -> Int
}

extension NSPasteboard: PasteboardProtocol, @unchecked @retroactive Sendable {}

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
        
        for char in string.utf16 {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            
            var unit = char
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            
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

public struct InjectionOptions: Sendable {
    public var addTrailingSpace: Bool
    public var autoCapitalizeFirstLetter: Bool
    public var useDirectTyping: Bool
    
    public init(
        addTrailingSpace: Bool = true,
        autoCapitalizeFirstLetter: Bool = true,
        useDirectTyping: Bool = true
    ) {
        self.addTrailingSpace = addTrailingSpace
        self.autoCapitalizeFirstLetter = autoCapitalizeFirstLetter
        self.useDirectTyping = useDirectTyping
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
    
    public init(
        pasteboard: PasteboardProtocol = NSPasteboard.general,
        eventPoster: EventPosterProtocol = SystemEventPoster(),
        isAccessibilityTrusted: @escaping () -> Bool = { TextInjector.isAccessibilityTrusted() }
    ) {
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.isAccessibilityTrusted = isAccessibilityTrusted
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
    
    /// Secondary fallback via AppleScript System Events keystroke
    public func postCmdVViaAppleScript() -> Bool {
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
    
    /// Master injection pipeline: writes to clipboard, types into field, falls back to Cmd+V
    @discardableResult
    public func inject(text: String, options: InjectionOptions = InjectionOptions()) async -> (success: Bool, method: InjectionMethod) {
        let prepared = prepareText(text, options: options)
        guard !prepared.isEmpty else { return (false, .clipboardOnly) }
        
        // 1. Always guarantee transcript is on clipboard first
        _ = pasteboard.clearContents()
        _ = pasteboard.declareTypes([.string], owner: nil)
        _ = pasteboard.setString(prepared, forType: .string)
        
        // 2. Try Path 1: AX Direct attribute injection
        if tryDirectAccessibilityInjection(text: prepared) {
            return (true, .accessibilityDirect)
        }
        
        // 3. Try Path 2: Direct Unicode Typing (Simulates real-time typing into any focused field)
        if options.useDirectTyping && prepared.count < 300 {
            if eventPoster.typeUnicodeString(prepared) {
                return (true, .directTyping)
            }
        }
        
        // 4. Try Path 3: Cmd+V synthetic paste (Instant universal auto-paste fallback)
        if eventPoster.postCmdV() {
            return (true, .syntheticPaste)
        }
        
        // 5. Try Path 4: AppleScript System Events paste fallback
        if postCmdVViaAppleScript() {
            return (true, .syntheticPaste)
        }
        
        // 6. Fallback: Saved safely on clipboard
        return (true, .clipboardOnly)
    }
}
