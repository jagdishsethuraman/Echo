import AppKit
import SwiftUI
import ApplicationServices

@MainActor
public final class MenuBarManager: NSObject, NSMenuDelegate {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private let coordinator = AppCoordinator.shared
    
    // Adaptive Pill Timer State
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var currentState: MenuState = .idle
    
    public override init() {
        super.init()
    }
    
    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.imagePosition = .imageLeft
        
        updateMenuBarIcon(state: .idle)
        rebuildMenu()
    }
    
    public enum MenuState: Equatable {
        case idle
        case dictating
        case meetingRecording
    }
    
    public func updateMenuBarIcon(state: MenuState) {
        self.currentState = state
        guard let button = statusItem?.button else { return }
        
        switch state {
        case .idle:
            stopRecordingTimer()
            button.title = " ◉"
            
        case .dictating:
            stopRecordingTimer()
            button.title = " ◉ Dictating..."
            
        case .meetingRecording:
            startRecordingTimer()
            updateRecordingTitle()
        }
    }
    
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingStartTime = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingTitle()
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
    
    private func updateRecordingTitle() {
        guard let button = statusItem?.button else { return }
        guard let start = recordingStartTime else {
            button.title = " ● 00:00"
            return
        }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        button.title = String(format: " ● %02d:%02d", minutes, seconds)
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        // Status header
        let statusItem = NSMenuItem(title: "Echo Speech Intelligence", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        let engineItem = NSMenuItem(title: "Engine: Phonon-2 (158 MB INT6 Parakeet-TDT)", action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)
        
        // Accessibility Permission Status
        let isTrusted = AXIsProcessTrusted()
        let axTitle = isTrusted ? "Accessibility: ✓ Granted (Auto-Paste Ready)" : "Accessibility: ⚠ Click to Grant in Settings"
        let axItem = NSMenuItem(title: axTitle, action: #selector(openAccessibility), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Meeting Studio Window
        let meetingItem = NSMenuItem(
            title: "Open Meeting Studio...",
            action: #selector(openMeetingStudio),
            keyEquivalent: "e"
        )
        meetingItem.keyEquivalentModifierMask = [.command, .shift]
        meetingItem.target = self
        menu.addItem(meetingItem)
        
        // Quick Dictation Toggle
        let dictateItem = NSMenuItem(
            title: "Quick Dictation (Push-to-Talk: Right ⌥)",
            action: #selector(toggleDictation),
            keyEquivalent: "d"
        )
        dictateItem.keyEquivalentModifierMask = [.command, .shift]
        dictateItem.target = self
        menu.addItem(dictateItem)
        
        // Copy Last Dictation to Clipboard
        let hasLastTranscript = !coordinator.lastTranscript.isEmpty
        let copyLastItem = NSMenuItem(
            title: hasLastTranscript ? "Copy Last Dictation: \"\(coordinator.lastTranscript.prefix(20))...\"" : "Copy Last Dictation",
            action: #selector(copyLastDictation),
            keyEquivalent: "c"
        )
        copyLastItem.keyEquivalentModifierMask = [.command, .shift]
        copyLastItem.isEnabled = hasLastTranscript
        copyLastItem.target = self
        menu.addItem(copyLastItem)
        
        // Toggle Meeting Recording
        let recordItem = NSMenuItem(
            title: currentState == .meetingRecording ? "Stop Meeting Recording" : "Start Meeting Recording",
            action: #selector(toggleMeetingRecording),
            keyEquivalent: "r"
        )
        recordItem.keyEquivalentModifierMask = [.command, .shift]
        recordItem.target = self
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Export to Markdown
        let exportItem = NSMenuItem(
            title: "Export All Notes to Obsidian (.md)",
            action: #selector(exportLastMeeting),
            keyEquivalent: ""
        )
        exportItem.target = self
        menu.addItem(exportItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Echo",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
    }
    
    @objc private func openAccessibility() {
        Task { @MainActor in
            coordinator.openAccessibilitySettings()
        }
    }
    
    @objc private func toggleDictation() {
        Task { @MainActor in
            coordinator.toggleDictation()
        }
    }
    
    @objc private func copyLastDictation() {
        Task { @MainActor in
            coordinator.copyLastTranscriptToClipboard()
        }
    }
    
    @objc private func openMeetingStudio() {
        Task { @MainActor in
            coordinator.showMeetingStudio()
        }
    }
    
    @objc private func toggleMeetingRecording() {
        Task { @MainActor in
            coordinator.toggleMeetingRecording()
            rebuildMenu()
        }
    }
    
    @objc private func exportLastMeeting() {
        Task { @MainActor in
            coordinator.exportLastMeetingMarkdown()
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
