import AppKit
import SwiftUI

public final class MeetingStudioWindow: NSWindow {
    public static let shared = MeetingStudioWindow()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Echo Meeting Studio"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.titlebarSeparatorStyle = .none
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.isMovableByWindowBackground = true
        self.appearance = NSAppearance(named: .darkAqua)
        self.minSize = NSSize(width: 840, height: 560)
        self.setFrameAutosaveName("EchoMeetingStudioWindow")
        self.collectionBehavior = [.moveToActiveSpace, .participatesInCycle, .fullScreenAuxiliary]
        self.center()

        let hostingView = NSHostingView(rootView: MeetingStudioHostView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    public func showWindow() {
        if self.isMiniaturized {
            self.deminiaturize(nil)
        }
        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toggleVisibility() {
        if self.isVisible && self.isKeyWindow {
            self.orderOut(nil)
        } else {
            showWindow()
        }
    }
}

private struct MeetingStudioHostView: View {
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var meetingCoordinator = AppCoordinator.shared.meetingCoordinator

    var body: some View {
        let session = meetingCoordinator.activeSession ?? MeetingSession(title: "No active session")
        MeetingStudioView(
            session: session,
            audioLevels: meetingCoordinator.audioLevels,
            isRecording: coordinator.isMeetingActive,
            onToggleRecord: {
                Task {
                    await coordinator.toggleMeetingSession()
                }
            },
            onExportMarkdown: {
                Task {
                    var sessionWithItems = session
                    let persistedItems = await DatabaseManager.shared.fetchActionItemsAsync(sessionId: session.id)
                    sessionWithItems.actionItems = persistedItems.isEmpty ? session.actionItems : persistedItems
                    await coordinator.exportSessionMarkdown(sessionWithItems)
                }
            }
        )
    }
}
