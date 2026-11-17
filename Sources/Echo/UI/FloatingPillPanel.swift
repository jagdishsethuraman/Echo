import AppKit
import SwiftUI

public final class FloatingPillPanel: NSPanel {
    private let stateModel: PillStateObservable
    private var dismissTimer: Timer?
    public var onStopRequested: (() -> Void)?
    
    public init() {
        self.stateModel = PillStateObservable()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Priority level: .statusBar ensures it floats above full-screen windows and video calls
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        
        let container = FloatingPillContainer(stateModel: stateModel) { [weak self] in
            self?.onStopRequested?()
        }
        let hostingView = NSHostingView(rootView: container)
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
    
    public func show(state: PillState = .listening(audioLevel: 0.2, livePartial: "", isLocked: false, elapsedSeconds: 0)) {
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
        case .listening(_, let livePartial, let isLocked, _):
            let lockBonus: CGFloat = isLocked ? 60 : 0
            let controlsPadding: CGFloat = 175 + lockBonus // dot + waveform + timer + stop button
            if livePartial.isEmpty {
                return max(320, controlsPadding + 140)
            } else {
                let estTextWidth = CGFloat(livePartial.count) * 7.5
                return min(740, max(320, estTextWidth + controlsPadding))
            }
        case .transcribing:
            return 260
        case .success(let preview):
            let estTextWidth = CGFloat(preview.count) * 7.2
            return min(640, max(280, estTextWidth + 90))
        case .error(let msg):
            let estTextWidth = CGFloat(msg.count) * 7.2
            return min(580, max(280, estTextWidth + 90))
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
    var onStop: (() -> Void)?
    
    public init(stateModel: PillStateObservable, onStop: (() -> Void)? = nil) {
        self.stateModel = stateModel
        self.onStop = onStop
    }
    
    public var body: some View {
        FloatingPillView(state: stateModel.state, onStop: onStop)
    }
}
