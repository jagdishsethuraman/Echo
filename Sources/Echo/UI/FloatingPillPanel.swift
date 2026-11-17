import AppKit
import SwiftUI

public final class FloatingPillPanel: NSPanel {
    private let stateModel: PillStateObservable
    private var dismissTimer: Timer?
    
    public init() {
        self.stateModel = PillStateObservable()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        
        let hostingView = NSHostingView(rootView: FloatingPillContainer(stateModel: stateModel))
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }
    
    public override var canBecomeKey: Bool {
        return false
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
    
    public func show(state: PillState = .listening(audioLevel: 0.2, livePartial: "")) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        stateModel.state = state
        reposition()
        
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    public func updateState(_ state: PillState) {
        stateModel.state = state
        
        switch state {
        case .success, .error:
            dismissTimer?.invalidate()
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.hide()
                }
            }
        default:
            break
        }
    }
    
    public func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.stateModel.state = .idle
        })
    }
    
    private func reposition() {
        let mouseLoc = NSEvent.mouseLocation
        let panelW: CGFloat = 380
        let panelH: CGFloat = 48
        
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main else {
            return
        }
        
        let screenRect = screen.visibleFrame
        var x = mouseLoc.x - (panelW / 2)
        var y = mouseLoc.y + 24
        
        if x < screenRect.minX + 20 { x = screenRect.minX + 20 }
        if x + panelW > screenRect.maxX - 20 { x = screenRect.maxX - panelW - 20 }
        if y + panelH > screenRect.maxY - 20 {
            y = mouseLoc.y - panelH - 24
        }
        
        self.setFrame(NSRect(x: x, y: y, width: panelW, height: panelH), display: true)
    }
}

public final class PillStateObservable: ObservableObject {
    @Published public var state: PillState = .idle
    public init() {}
}

public struct FloatingPillContainer: View {
    @ObservedObject var stateModel: PillStateObservable
    
    public init(stateModel: PillStateObservable) {
        self.stateModel = stateModel
    }
    
    public var body: some View {
        FloatingPillView(state: stateModel.state)
    }
}
