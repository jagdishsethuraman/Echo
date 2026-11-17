import AppKit
import SwiftUI

public final class MeetingStudioWindow: NSWindow {
    public static let shared = MeetingStudioWindow()
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Echo Meeting Studio"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.backgroundColor = NSColor(red: 5/255, green: 5/255, blue: 7/255, alpha: 1.0) // Swiss Obsidian #050507
        self.isReleasedWhenClosed = false
        self.center()
        
        let hostingView = NSHostingView(rootView: MeetingStudioHostView())
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }
    
    public func toggleVisibility() {
        if self.isVisible {
            self.orderOut(nil)
        } else {
            self.center()
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct MeetingStudioHostView: View {
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var meetingCoordinator = AppCoordinator.shared.meetingCoordinator
    
    var body: some View {
        let session = meetingCoordinator.activeSession ?? MeetingSession(title: "Echo Meeting Studio")
        MeetingStudioView(
            session: session,
            micLevel: meetingCoordinator.micLevel,
            systemLevel: meetingCoordinator.systemLevel,
            isRecording: coordinator.isMeetingActive,
            onToggleRecord: {
                Task {
                    await coordinator.toggleMeetingSession()
                }
            },
            onExportMarkdown: {
                coordinator.exportLastMeetingMarkdown()
            }
        )
    }
}
