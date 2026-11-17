import AppKit
import Carbon

public final class HotkeyManager: @unchecked Sendable {
    public var onKeyDown: (() -> Void)?
    public var onKeyUp: (() -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isKeyDown: Bool = false
    
    public init() {}
    
    deinit {
        stopMonitoring()
    }
    
    /// Check whether macOS Accessibility permissions are granted
    public static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Start listening for global Push-to-Talk shortcut (Default: Right Option / Alt key or Fn)
    public func startMonitoring() {
        stopMonitoring()
        
        // FlagsChanged monitor for modifier-based push-to-talk (e.g. Right Option: flag 0x80040)
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
        // Example: Option key toggled
        if event.type == .flagsChanged {
            let optionPressed = event.modifierFlags.contains(.option)
            if optionPressed && !isKeyDown {
                isKeyDown = true
                onKeyDown?()
            } else if !optionPressed && isKeyDown {
                isKeyDown = false
                onKeyUp?()
            }
        }
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
