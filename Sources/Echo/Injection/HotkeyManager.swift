import AppKit
import Carbon

public final class HotkeyManager: @unchecked Sendable {
    public var onKeyDown: (() -> Void)?
    public var onKeyUp: (() -> Void)?
    public var onLockStateChanged: ((Bool) -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isKeyDown: Bool = false
    private var lastControlDownTime: TimeInterval = 0
    public private(set) var isLocked: Bool = false
    
    public init() {}
    
    deinit {
        stopMonitoring()
    }
    
    /// Check whether macOS Accessibility permissions are granted
    public static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Start listening for global Push-to-Talk shortcut (Default: Control key, double-tap to lock)
    public func startMonitoring() {
        stopMonitoring()
        
        // FlagsChanged monitor for modifier-based push-to-talk (Control key)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }
    
    public func stopMonitoring() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }
    
    private func handleEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            let controlPressed = event.modifierFlags.contains(.control)
            let now = Date().timeIntervalSince1970
            
            if controlPressed && !isKeyDown {
                isKeyDown = true
                let elapsed = now - lastControlDownTime
                lastControlDownTime = now
                
                // If already in locked hands-free recording, tapping Control finishes and unlocks
                if isLocked {
                    isLocked = false
                    onLockStateChanged?(false)
                    onKeyUp?()
                    return
                }
                
                // Double-click Control within 380ms triggers Hands-Free Lock Mode
                if elapsed < 0.38 {
                    isLocked = true
                    onLockStateChanged?(true)
                    onKeyDown?()
                    return
                }
                
                // Normal push-to-talk trigger
                onKeyDown?()
                
            } else if !controlPressed && isKeyDown {
                isKeyDown = false
                
                // In locked hands-free mode, releasing the key does NOT stop recording
                if isLocked {
                    return
                }
                
                // Normal push-to-talk release finishes recording and injects text
                onKeyUp?()
            }
        }
    }
    
    public func unlock() {
        isLocked = false
        onLockStateChanged?(false)
    }
    
    /// Programmatic trigger for automated test harnesses
    public func simulateKeyDown() {
        guard !isKeyDown else { return }
        isKeyDown = true
        onKeyDown?()
    }
    
    public func simulateKeyUp() {
        guard isKeyDown else { return }
        isKeyDown = false
        onKeyUp?()
    }
}
