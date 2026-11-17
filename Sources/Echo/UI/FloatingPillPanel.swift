import AppKit
import SwiftUI

public final class FloatingPillPanel: NSPanel {
    private let stateModel: PillStateObservable
    private var dismissTimer: Timer?
    
    public init() {
        self.stateModel = PillStateObservable()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 46),
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
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }
    
    public override var canBecomeKey: Bool {
        return false
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
    
    public func show(state: PillState = .listening(audioLevel: 0.2, livePartial: "", isLocked: false)) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        stateModel.state = state
        reposition(for: state, animate: false)
        
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    public func updateState(_ state: PillState) {
        stateModel.state = state
        reposition(for: state, animate: true)
        
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
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.stateModel.state = .idle
        })
    }
    
    private func targetWidth(for state: PillState) -> CGFloat {
        switch state {
        case .idle:
            return 220
        case .listening(_, let livePartial, let isLocked):
            let lockBonus: CGFloat = isLocked ? 68 : 0
            if livePartial.isEmpty {
                return 260 + lockBonus
            } else {
                let estTextWidth = CGFloat(livePartial.count) * 7.5
                return min(720, max(260 + lockBonus, estTextWidth + 120 + lockBonus))
            }
        case .transcribing:
            return 240
        case .success(let preview):
            let estTextWidth = CGFloat(preview.count) * 7.2
            return min(640, max(260, estTextWidth + 90))
        case .error(let msg):
            let estTextWidth = CGFloat(msg.count) * 7.2
            return min(580, max(260, estTextWidth + 90))
        }
    }
    
    private func reposition(for state: PillState, animate: Bool = true) {
        guard let screen = NSScreen.main else { return }
        
        let screenRect = screen.visibleFrame
        let panelW: CGFloat = targetWidth(for: state)
        let panelH: CGFloat = 46
        
        // Bottom-Center screen positioning: 28px above Dock / taskbar
        let x = screenRect.midX - (panelW / 2)
        let y = screenRect.minY + 28
        let targetFrame = NSRect(x: x, y: y, width: panelW, height: panelH)
        
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            self.setFrame(targetFrame, display: true)
        }
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
