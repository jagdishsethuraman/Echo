import AppKit
import SwiftUI
import ApplicationServices
import AVFoundation

@MainActor
public final class MenuBarManager: NSObject, NSMenuDelegate, NSMenuItemValidation {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private let coordinator = AppCoordinator.shared
    private static let frostTint = NSColor(
        srgbRed: 0.545,
        green: 0.708,
        blue: 0.969,
        alpha: 1.0
    )
    
    // Adaptive Pill Timer State
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var currentState: MenuState = .idle
    
    public override init() {
        super.init()
    }
    
    public func setupMenuBar() {        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        case meetingFinalizing
    }
    
    public func updateMenuBarIcon(state: MenuState) {
        self.currentState = state
        guard let button = statusItem?.button else { return }

        switch state {
        case .idle:
            stopRecordingTimer()
            setStatusIcon("waveform", accessibilityLabel: "Echo ready", tint: nil)
            button.title = ""

        case .dictating:
            startRecordingTimer()
            setStatusIcon("waveform.badge.mic", accessibilityLabel: "Echo dictating", tint: Self.frostTint)
            updateRecordingTitle()

        case .meetingFinalizing:
            stopRecordingTimer()
            setStatusIcon("hourglass", accessibilityLabel: "Finalizing meeting transcript", tint: Self.frostTint)
            button.title = ""

        case .meetingRecording:
            startRecordingTimer()
            setStatusIcon("record.circle.fill", accessibilityLabel: "Meeting recording", tint: .systemRed)
            updateRecordingTitle()
        }
        rebuildMenu()
    }

    private func setStatusIcon(_ symbolName: String, accessibilityLabel: String, tint: NSColor?) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.contentTintColor = tint
        button.toolTip = accessibilityLabel
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
            button.title = " 00:00"
            return
        }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        button.title = String(format: " %02d:%02d", minutes, seconds)
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        // Status header
        let statusItem = NSMenuItem(title: "Echo — On-device dictation", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        let engineItem = NSMenuItem(title: "Phonon-2 speech engine · local", action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)

        if let message = coordinator.meetingCoordinator.captureError {
            let notice = NSMenuItem(title: "View Meeting Notice…", action: #selector(openMeetingStudio), keyEquivalent: "")
            notice.target = self
            notice.toolTip = message
            menu.addItem(notice)
        }
        
        // Accessibility Permission Status
        let isTrusted = AXIsProcessTrusted()
        let axTitle = isTrusted ? "Accessibility Access: Granted" : "Accessibility Access: Not Granted…"
        let axItem = NSMenuItem(title: axTitle, action: #selector(openAccessibility), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        
        // Microphone Permission Status
        let isMicGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let micTitle = isMicGranted ? "Microphone Access: Granted" : "Microphone Access: Not Granted…"
        let micItem = NSMenuItem(title: micTitle, action: #selector(openMicrophoneSettings), keyEquivalent: "")
        micItem.target = self
        menu.addItem(micItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Meeting Studio Window
        let meetingItem = NSMenuItem(
            title: "Open Meeting Studio",
            action: #selector(openMeetingStudio),
            keyEquivalent: "e"
        )
        meetingItem.keyEquivalentModifierMask = [.command, .shift]
        meetingItem.target = self
        menu.addItem(meetingItem)
        
        // Quick Dictation Toggle
        let dictateTitle = currentState == .dictating ? "Stop Dictation" : "Start Dictation"
        let dictateItem = NSMenuItem(
            title: dictateTitle,
            action: #selector(toggleDictation),
            keyEquivalent: "d"
        )
        dictateItem.keyEquivalentModifierMask = [.command, .shift]
        dictateItem.target = self
        menu.addItem(dictateItem)
        
        // Copy Last Dictation to Clipboard
        let hasLastTranscript = !coordinator.lastTranscript.isEmpty
        let copyLastItem = NSMenuItem(
            title: "Copy Last Dictation",
            action: #selector(copyLastDictation),
            keyEquivalent: "c"
        )
        copyLastItem.keyEquivalentModifierMask = [.command, .shift]
        copyLastItem.isEnabled = hasLastTranscript
        copyLastItem.target = self
        menu.addItem(copyLastItem)
        
        // Toggle Meeting Recording
        let recordItem = NSMenuItem(
            title: coordinator.isMeetingFinalizing ? "Finalizing Meeting…" : (coordinator.isMeetingActive ? "Stop Meeting Recording" : "Start Meeting Recording"),
            action: #selector(toggleMeetingRecording),
            keyEquivalent: "r"
        )
        recordItem.keyEquivalentModifierMask = [.command, .shift]
        recordItem.target = self
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Export to Markdown
        let exportItem = NSMenuItem(
            title: "Export Current Session to Markdown…",
            action: #selector(exportLastMeeting),
            keyEquivalent: ""
        )
        exportItem.target = self
        menu.addItem(exportItem)
        
        // Meeting history / retention
        menu.addItem(makeHistoryMenuItem())

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
    
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMeetingRecording), #selector(exportLastMeeting):
            return !coordinator.isMeetingFinalizing
        case #selector(copyLastDictation):
            return !coordinator.lastTranscript.isEmpty
        case #selector(deleteHistorySession(_:)):
            return !(coordinator.isMeetingActive || coordinator.isMeetingFinalizing) || !targetsCurrentSession(menuItem)
        case #selector(exportHistorySession(_:)), #selector(copyHistorySession(_:)):
            return !coordinator.isMeetingFinalizing || !targetsCurrentSession(menuItem)
        default:
            return true
        }
    }

    private func targetsCurrentSession(_ item: NSMenuItem) -> Bool {
        guard let id = item.representedObject as? UUID else { return false }
        return id == coordinator.meetingCoordinator.activeSession?.id
    }

    @objc private func openAccessibility() {
        Task { @MainActor in
            coordinator.openAccessibilitySettings()
        }
    }
    
    @objc private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
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
        DispatchQueue.main.async { [weak self] in
            self?.coordinator.showMeetingStudio()
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
    
    private func makeHistoryMenuItem() -> NSMenuItem {
        let historyItem = NSMenuItem(title: "Meeting History", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu(title: "Meeting History")
        let sessions = DatabaseManager.shared.fetchRecentSessions(limit: 8)

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No saved sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for session in sessions {
                let title = "\(formatter.string(from: session.startTime)) · \(session.title)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()

                let copy = NSMenuItem(
                    title: "Copy Transcript",
                    action: #selector(copyHistorySession(_:)),
                    keyEquivalent: ""
                )
                copy.target = self
                copy.representedObject = session.id
                submenu.addItem(copy)

                let export = NSMenuItem(
                    title: "Export Markdown File…",
                    action: #selector(exportHistorySession(_:)),
                    keyEquivalent: ""
                )
                export.target = self
                export.representedObject = session.id
                submenu.addItem(export)

                let delete = NSMenuItem(
                    title: "Delete Session…",
                    action: #selector(deleteHistorySession(_:)),
                    keyEquivalent: ""
                )
                delete.target = self
                delete.representedObject = session.id
                submenu.addItem(delete)

                item.submenu = submenu
                historyMenu.addItem(item)
            }
            historyMenu.addItem(NSMenuItem.separator())
        }

        let cleanup = NSMenuItem(
            title: "Delete Empty Sessions",
            action: #selector(cleanupEmptySessions),
            keyEquivalent: ""
        )
        cleanup.target = self
        historyMenu.addItem(cleanup)

        let clearDictations = NSMenuItem(
            title: "Clear Dictation History…",
            action: #selector(clearDictationHistory),
            keyEquivalent: ""
        )
        clearDictations.target = self
        historyMenu.addItem(clearDictations)

        historyItem.submenu = historyMenu
        return historyItem
    }

    @objc private func copyHistorySession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        let segments = DatabaseManager.shared.fetchUtterances(sessionId: id)
        let text = segments
            .map { "\($0.speaker == .you ? "You" : "Meeting"): \($0.text)" }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func exportHistorySession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        Task { @MainActor in
            await coordinator.exportSession(id: id)
        }
    }

    @objc private func deleteHistorySession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this meeting session?"
        alert.informativeText = "The transcript will be removed from this Mac."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            await coordinator.deleteSession(id: id)
            rebuildMenu()
        }
    }

    @objc private func cleanupEmptySessions() {
        Task { @MainActor in
            await coordinator.deleteEmptySessions()
            rebuildMenu()
        }
    }

    @objc private func clearDictationHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear Dictation History?"
        alert.informativeText = "All standalone dictation snippets will be removed from local storage."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            await coordinator.deleteStandaloneDictations()
            rebuildMenu()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
