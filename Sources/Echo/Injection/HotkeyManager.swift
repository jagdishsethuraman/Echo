import AppKit
import Carbon

public final class HotkeyManager: @unchecked Sendable {
    public var onKeyDown: (() -> Void)?
    public var onKeyUp: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onLockStateChanged: ((Bool) -> Void)?
    
    // Global menu-equivalent shortcuts monitored system-wide
    public var onOpenMeetingStudio: (() -> Void)?
    public var onToggleDictation: (() -> Void)?
    public var onCopyLastDictation: (() -> Void)?
    public var onToggleMeetingRecording: (() -> Void)?
    
    @Published private(set) var accessibilityGranted = false
    private var permissionTimer: Timer?
    private let checkTrust: () -> Bool
    private let addGlobalMonitor: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    private let removeGlobalMonitor: (Any) -> Void
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    
    public private(set) var isKeyDown: Bool = false
    public private(set) var isChorded: Bool = false
    public private(set) var isLocked: Bool = false
    private var keyDownTime: TimeInterval = 0
    private var holdTimer: DispatchWorkItem?
    private var holdStarted = false
    private var lastTap: (release: TimeInterval, binding: EchoShortcut)?
    private static let holdDelay: TimeInterval = 0.30
    private static let doubleTapInterval: TimeInterval = 0.38
    
    public var onExportMeeting: (() -> Void)?
    private let shortcuts: KeyboardShortcuts
    private var activeBinding: EchoShortcut?
    private var heldKeyCode: UInt16?
    private var previousFlags: NSEvent.ModifierFlags = []

    public convenience init() { self.init(shortcuts: .shared) }
    init(shortcuts: KeyboardShortcuts,
         checkTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
         addGlobalMonitor: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any? = NSEvent.addGlobalMonitorForEvents,
         removeGlobalMonitor: @escaping (Any) -> Void = NSEvent.removeMonitor) {
        self.shortcuts = shortcuts
        self.checkTrust = checkTrust
        self.addGlobalMonitor = addGlobalMonitor
        self.removeGlobalMonitor = removeGlobalMonitor
    }
    
    deinit {
        stopMonitoring()
    }
    
    /// Check whether macOS Accessibility permissions are granted
    public static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Start listening for global Push-to-Talk shortcut (Default: Control key, double-tap to lock, Esc to cancel)
    public func startMonitoring() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }
        timer.tolerance = 0.1
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshAccessibility(initial: true)

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        let keyEvents: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyEvents) { [weak self] event in
            self?.routeKeyEvent(event) == true ? nil : event
        }
    }
    
    func refreshAccessibility(initial: Bool = false) {
        guard permissionTimer != nil else { return }
        let granted = checkTrust()
        let changed = granted != accessibilityGranted
        guard initial || changed || (granted && globalKeyMonitor == nil) else { return }

        // AppKit can return a monitor before trust is granted that never receives keys.
        if let monitor = globalKeyMonitor { removeGlobalMonitor(monitor) }
        globalKeyMonitor = addGlobalMonitor([.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            if event.type == .flagsChanged {
                self?.handleFlagsChanged(event)
            } else {
                _ = self?.routeKeyEvent(event)
            }
        }
        if changed {
            accessibilityGranted = granted
            if !granted {
                // A release event may now be unreachable. Finish any held dictation.
                let shouldFinish = isLocked || holdStarted
                resetHoldState()
                if shouldFinish {
                    onLockStateChanged?(false)
                    onKeyUp?()
                }
            }
        }
    }

    private func resetHoldState() {
        holdTimer?.cancel()
        holdTimer = nil
        lastTap = nil
        holdStarted = false
        isKeyDown = false
        isChorded = false
        isLocked = false
        heldKeyCode = nil
        activeBinding = nil
        previousFlags = []
    }

    public func stopMonitoring() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        resetHoldState()
        if let l = localFlagsMonitor {
            NSEvent.removeMonitor(l)
            localFlagsMonitor = nil
        }
        if let g = globalKeyMonitor {
            removeGlobalMonitor(g)
            globalKeyMonitor = nil
        }
        if let l = localKeyMonitor {
            NSEvent.removeMonitor(l)
            localKeyMonitor = nil
        }
    }
    
    public func handleFlagsChanged(_ event: NSEvent) {
        let binding = activeBinding ?? shortcuts[.pushToTalk]
        let flags = event.modifierFlags.intersection(EchoShortcut.supported)
        let prior = previousFlags
        previousFlags = flags
        if !flags.subtracting(binding.flags).isEmpty { lastTap = nil }
        if isKeyDown {
            if !flags.subtracting(binding.flags).isEmpty { interruptHold() }
            if !flags.isSuperset(of: binding.flags) {
                heldKeyCode = nil
                updateHold(pressed: false, at: event.timestamp)
            }
        } else if binding.key.isEmpty, flags == binding.flags, !prior.isSuperset(of: flags) {
            updateHold(pressed: true, at: event.timestamp)
        }
    }

    private func updateHold(pressed: Bool, at timestamp: TimeInterval) {
        let eventTime = timestamp > 0 ? timestamp : ProcessInfo.processInfo.systemUptime
        if pressed {
            guard !isKeyDown else { return }
            activeBinding = shortcuts[.pushToTalk]
            keyDownTime = eventTime
            isKeyDown = true
            isChorded = false
            guard !isLocked else { return }
            let timer = DispatchWorkItem { [weak self] in
                guard let self, self.isKeyDown, !self.isChorded else { return }
                self.holdStarted = true
                self.lastTap = nil
                self.onKeyDown?()
            }
            holdTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: timer)
            return
        }

        guard isKeyDown, let binding = activeBinding else { return }
        holdTimer?.cancel()
        holdTimer = nil
        isKeyDown = false
        activeBinding = nil
        if isChorded {
            isChorded = false
        } else if isLocked || holdStarted {
            let wasLocked = isLocked
            holdStarted = false
            isLocked = false
            if wasLocked { onLockStateChanged?(false) }
            onKeyUp?()
        } else if eventTime - keyDownTime < Self.holdDelay {
            if let tap = lastTap, tap.binding == binding, keyDownTime >= tap.release,
               keyDownTime - tap.release <= Self.doubleTapInterval {
                lastTap = nil
                isLocked = true
                onKeyDown?()
                onLockStateChanged?(true)
            } else {
                lastTap = (eventTime, binding)
            }
        } else {
            lastTap = nil
        }
    }

    // Consume locally handled shortcuts so the menu cannot dispatch them twice.
    @discardableResult
    func routeKeyEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyUp {
            guard heldKeyCode == event.keyCode else { return false }
            heldKeyCode = nil
            updateHold(pressed: false, at: event.timestamp)
            return true
        }
        if shortcuts[.pushToTalk].matches(event) {
            if !event.isARepeat {
                heldKeyCode = event.keyCode
                updateHold(pressed: true, at: event.timestamp)
            }
            return true
        }
        handleKeyDown(event)
        return handleGlobalShortcut(event)
    }

    @discardableResult
    public func handleGlobalShortcut(_ event: NSEvent) -> Bool {
        guard let action = ShortcutAction.allCases.first(where: {
            $0 != .pushToTalk && shortcuts[$0].matches(event)
        }) else { return false }
        guard !event.isARepeat else { return true }
        switch action {
        case .studio: onOpenMeetingStudio?()
        case .dictation: onToggleDictation?()
        case .copy: onCopyLastDictation?()
        case .meeting: onToggleMeetingRecording?()
        case .export: onExportMeeting?()
        case .pushToTalk: break
        }
        return true
    }

    private func interruptHold() {
        lastTap = nil
        guard isKeyDown, !isChorded else { return }
        isChorded = true
        holdTimer?.cancel()
        holdTimer = nil
        if holdStarted {
            holdStarted = false
            onCancel?()
        }
    }

    public func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            cancel()
        } else {
            interruptHold()
        }
    }

    public func cancel() {
        let wasRecording = holdStarted || isLocked
        resetHoldState()
        if wasRecording {
            onLockStateChanged?(false)
            onCancel?()
        }
    }

    public func unlock() {
        holdTimer?.cancel()
        holdTimer = nil
        lastTap = nil
        holdStarted = false
        isLocked = false
        if isKeyDown { isChorded = true }
        onLockStateChanged?(false)
    }

    // MARK: - Programmatic Triggers for Unit Testing
    
    public func simulateFlagsChanged(flags: NSEvent.ModifierFlags, timeOffset: TimeInterval = 0) {
        let baseUptime = 1000.0
        let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: baseUptime + timeOffset,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0
        ) ?? NSEvent()
        handleFlagsChanged(event)
    }
    
    public func simulateKeyDown(keyCode: UInt16) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: isKeyDown ? .control : [],
            timestamp: Date().timeIntervalSince1970,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) ?? NSEvent()
        handleKeyDown(event)
    }
    
    public func simulateEscape() {
        simulateKeyDown(keyCode: 53)
    }

    /// Simulates the system-wide shortcut path (global monitor).
    public func simulateKeyShortcut(characters: String, modifiers: NSEvent.ModifierFlags) {
        handleGlobalShortcut(makeShortcutEvent(characters: characters, modifiers: modifiers))
    }

    public func simulateLocalKeyShortcut(characters: String, modifiers: NSEvent.ModifierFlags) {
        routeKeyEvent(makeShortcutEvent(characters: characters, modifiers: modifiers))
    }

    private func makeShortcutEvent(characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: Date().timeIntervalSince1970,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        ) ?? NSEvent()
    }
}
