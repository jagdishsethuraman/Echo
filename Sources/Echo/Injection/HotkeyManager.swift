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
    
    public init() {}
    
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
        
        // Modifier flags monitor for Control key
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        // KeyDown monitor for Escape (cancel) and chorded shortcuts (e.g. Ctrl+C, Ctrl+Space)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let controlPressed = flags.contains(.control)
        
        // If other modifiers (Command, Option, Shift) are held down, this is not a pure dictation trigger
        let otherModifiers = flags.intersection([.command, .option, .shift])
        if !otherModifiers.isEmpty {
            if isKeyDown {
                // Chorded with another modifier key (e.g. Ctrl+Cmd+Space). Abort dictation.
                isChorded = true
                pendingReleaseWorkItem?.cancel()
                pendingReleaseWorkItem = nil
                onCancel?()
            }
            return
        }
        
        let eventTime = event.timestamp > 0 ? event.timestamp : ProcessInfo.processInfo.systemUptime
        
        if controlPressed && !isKeyDown {
            isKeyDown = true
            isChorded = false
            keyDownTime = eventTime
            
            // 1. If currently in locked hands-free mode, tapping Control unlocks and stops
            if isLocked {
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
            
        } else if !controlPressed && isKeyDown {
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
    
    public func handleKeyDown(_ event: NSEvent) {
        let keyCode = event.keyCode
        
        // Escape key (kVK_Escape = 53): cancel recording immediately
        if keyCode == 53 {
            if isKeyDown || isLocked || pendingReleaseWorkItem != nil {
                cancel()
            }
            return
        }
        
        // Global Command+Shift shortcuts (⇧⌘E, ⇧⌘D, ⇧⌘C, ⇧⌘R)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains([.command, .shift]) {
            if let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "e":
                    onOpenMeetingStudio?()
                    return
                case "d":
                    onToggleDictation?()
                    return
                case "c":
                    onCopyLastDictation?()
                    return
                case "r":
                    onToggleMeetingRecording?()
                    return
                default:
                    break
                }
            }
        }
        
        // If Control is physically held down and any other key is pressed,
        // this is a chorded shortcut (e.g. Ctrl+C, Ctrl+V, Ctrl+Space, Ctrl+A).
        if isKeyDown {
            isChorded = true
            pendingReleaseWorkItem?.cancel()
            pendingReleaseWorkItem = nil
            onCancel?()
        }
    }
    
    public func cancel() {
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        let wasActive = isKeyDown || isLocked
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

    public func simulateKeyShortcut(characters: String, modifiers: NSEvent.ModifierFlags) {
        let event = NSEvent.keyEvent(
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
        handleKeyDown(event)
    }
}
