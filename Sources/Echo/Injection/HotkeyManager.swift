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
    
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    
    public private(set) var isKeyDown: Bool = false
    public private(set) var isChorded: Bool = false
    public private(set) var isLocked: Bool = false
    private var keyDownTime: TimeInterval = 0
    private var pendingReleaseWorkItem: DispatchWorkItem?
    
    public var onExportMeeting: (() -> Void)?
    private let shortcuts: KeyboardShortcuts
    private var activeBinding: EchoShortcut?
    private var heldKeyCode: UInt16?
    private var previousFlags: NSEvent.ModifierFlags = []

    public convenience init() { self.init(shortcuts: .shared) }
    init(shortcuts: KeyboardShortcuts) { self.shortcuts = shortcuts }
    
    deinit {
        stopMonitoring()
    }
    
    /// Check whether macOS Accessibility permissions are granted
    public static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Start listening for global Push-to-Talk shortcut (Default: Control key, double-tap to lock, Esc to cancel)
    public func startMonitoring() {
        stopMonitoring()
        
        // Modifier-only bindings arrive as flag transitions.
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        let keyEvents: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyEvents) { [weak self] event in
            _ = self?.routeKeyEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyEvents) { [weak self] event in
            self?.routeKeyEvent(event) == true ? nil : event
        }
    }
    
    public func stopMonitoring() {
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        
        if let g = globalFlagsMonitor {
            NSEvent.removeMonitor(g)
            globalFlagsMonitor = nil
        }
        if let l = localFlagsMonitor {
            NSEvent.removeMonitor(l)
            localFlagsMonitor = nil
        }
        if let g = globalKeyMonitor {
            NSEvent.removeMonitor(g)
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
        if pressed && !isKeyDown {
            activeBinding = shortcuts[.pushToTalk]
            isKeyDown = true
            isChorded = false
            keyDownTime = eventTime
            
            // 1. If currently in locked hands-free mode, tapping Control unlocks and stops
            if isLocked {
                isChorded = true // Suppress the release after the tap that ends lock mode.
                isLocked = false
                pendingReleaseWorkItem?.cancel()
                pendingReleaseWorkItem = nil
                onLockStateChanged?(false)
                onKeyUp?()
                return
            }
            
            // 2. Check if this is the 2nd tap of a rapid double-tap (<380ms from 1st release)
            if let pending = pendingReleaseWorkItem, !pending.isCancelled {
                pending.cancel()
                pendingReleaseWorkItem = nil
                isLocked = true
                onLockStateChanged?(true)
                // Recording was already started on 1st tap; seamless continuation in lock mode!
                return
            }
            
            // 3. Normal initial press: start dictation
            onKeyDown?()
            
        } else if !pressed && isKeyDown {
            activeBinding = nil
            isKeyDown = false
            let holdDuration = eventTime - keyDownTime
            
            // If chorded with an alphanumeric/symbol key, ignore release (no dictation or lock)
            if isChorded {
                isChorded = false
                return
            }
            
            // If in locked hands-free mode, releasing the key does NOT stop recording
            if isLocked {
                return
            }
            
            // If held for longer than 350ms, it is standard push-to-talk: finish immediately
            if holdDuration > 0.35 {
                onKeyUp?()
                return
            }
            
            // If tapped briefly (<350ms), wait 380ms to see if a 2nd tap comes to activate Lock Mode
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isLocked, !self.isChorded else { return }
                self.pendingReleaseWorkItem = nil
                self.onKeyUp?()
            }
            pendingReleaseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: workItem)
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
        guard isKeyDown, !isChorded else { return }
        isChorded = true
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        onCancel?()
    }

    public func handleKeyDown(_ event: NSEvent) {
        let keyCode = event.keyCode
        
        // Escape key (kVK_Escape = 53): cancel recording immediately
        if keyCode == 53 {
            if isKeyDown || isLocked || pendingReleaseWorkItem != nil {
                cancel()
            }
            return
        }
        
        interruptHold()
    }
    
    public func cancel() {
        let wasActive = isKeyDown || isLocked || pendingReleaseWorkItem != nil
        activeBinding = nil
        heldKeyCode = nil
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        isKeyDown = false
        isLocked = false
        isChorded = false
        if wasActive {
            onLockStateChanged?(false)
            onCancel?()
        }
    }
    
    public func unlock() {
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        isLocked = false
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
