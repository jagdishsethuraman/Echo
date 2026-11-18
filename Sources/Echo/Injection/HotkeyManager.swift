import AppKit
import Carbon

public final class HotkeyManager: @unchecked Sendable {
    public var onKeyDown: (() -> Void)?
    public var onKeyUp: (() -> Void)?
    public var onLockStateChanged: ((Bool) -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isKeyDown: Bool = false
    private var keyDownTime: TimeInterval = 0
    private var lastKeyUpTime: TimeInterval = 0
    public private(set) var isLocked: Bool = false
    private var pendingReleaseWorkItem: DispatchWorkItem?
    
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
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        
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
                keyDownTime = now
                
                // 1. If currently in locked hands-free mode, tapping Control unlocks and stops
                if isLocked {
                    isLocked = false
                    pendingReleaseWorkItem?.cancel()
                    pendingReleaseWorkItem = nil
                    onLockStateChanged?(false)
                    onKeyUp?()
                    return
                }
                
                // 2. Check if this is the 2nd tap of a rapid double-tap (<300ms from 1st release)
                if let pending = pendingReleaseWorkItem, !pending.isCancelled {
                    pending.cancel()
                    pendingReleaseWorkItem = nil
                    isLocked = true
                    onLockStateChanged?(true)
                    // Recording was already started on 1st tap; seamless continuation!
                    return
                }
                
                // 3. Normal initial press: start dictation
                onKeyDown?()
                
            } else if !controlPressed && isKeyDown {
                isKeyDown = false
                let holdDuration = now - keyDownTime
                lastKeyUpTime = now
                
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
                    guard let self = self, !self.isLocked else { return }
                    self.pendingReleaseWorkItem = nil
                    self.onKeyUp?()
                }
                pendingReleaseWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: workItem)
            }
        }
    }
    
    public func unlock() {
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
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
