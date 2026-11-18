import AppKit
import SwiftUI

public final class FloatingPillPanel: NSPanel {
    private let stateModel: PillStateObservable
    private var dismissTimer: Timer?
    public var onStopRequested: (() -> Void)?
    public var onCancelRequested: (() -> Void)?
    private var lastTargetWidth: CGFloat = 370
    
    public init() {
        self.stateModel = PillStateObservable()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Priority level: .popUpMenu ensures it stays pinned above video calls and full-screen windows
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.appearance = NSAppearance(named: .darkAqua)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        
        let container = FloatingPillContainer(
            stateModel: stateModel,
            onStop: { [weak self] in self?.onStopRequested?() },
            onCancel: { [weak self] in self?.onCancelRequested?() }
        )
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
        let oldState = stateModel.state
        stateModel.state = state
        
        // Only trigger reposition if the structural layout changed (e.g. state type, lock toggle, or broad text bucket)
        let needsReposition: Bool
        switch (oldState, state) {
        case (.listening(_, _, let oldLocked, _), .listening(_, _, let newLocked, _)):
            needsReposition = (oldLocked != newLocked) || (abs(targetWidth(for: oldState) - targetWidth(for: state)) > 20)
        case (.idle, .listening), (.listening, .transcribing), (.transcribing, .success), (.transcribing, .error):
            needsReposition = true
        default:
            needsReposition = abs(targetWidth(for: oldState) - targetWidth(for: state)) > 20
        }
        
        if needsReposition {
            reposition(for: state, animate: true)
        }
        
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
            return 240
        case .listening(_, let livePartial, let isLocked, _):
            let baseWidth: CGFloat = isLocked ? 410 : 370
            if livePartial.isEmpty {
                return baseWidth
            } else {
                // Quantize text width in 40pt buckets to avoid flutter on every letter
                let rawWidth = baseWidth + CGFloat(livePartial.count) * 7.0
                let quantized = ceil(rawWidth / 40.0) * 40.0
                return min(640, max(baseWidth, quantized))
            }
        case .transcribing:
            return 280
        case .success(let preview):
            let rawWidth = 280 + CGFloat(preview.count) * 6.5
            let quantized = ceil(rawWidth / 30.0) * 30.0
            return min(560, max(280, quantized))
        case .error:
            return 360
        }
    }
    
    /// Target screen: chooses the monitor containing the mouse pointer, falling back to main display (UX-03)
    private var targetScreen: NSScreen? {
        let mouseLoc = NSEvent.mouseLocation
        if let screenUnderMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screenUnderMouse
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
    
    private func reposition(for state: PillState, animate: Bool = true) {
        guard let screen = targetScreen else { return }
        
        let screenRect = screen.visibleFrame
        let panelW: CGFloat = targetWidth(for: state)
        let panelH: CGFloat = 52
        
        // Bottom-Center screen positioning: keep the 38pt pill 24px above the Dock/bottom edge
        let x = round(screenRect.midX - (panelW / 2))
        let y = round(screenRect.minY + 24)
        let targetFrame = NSRect(x: x, y: y, width: panelW, height: panelH)
        
        // Prevent re-animating if already at position (eliminates jitter and oscillations)
        if abs(self.frame.origin.x - targetFrame.origin.x) < 1.0 &&
           abs(self.frame.size.width - targetFrame.size.width) < 1.0 &&
           abs(self.frame.origin.y - targetFrame.origin.y) < 1.0 {
            return
        }
        
        lastTargetWidth = panelW
        
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
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
    var onCancel: (() -> Void)?
    
    public init(stateModel: PillStateObservable, onStop: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.stateModel = stateModel
        self.onStop = onStop
        self.onCancel = onCancel
    }
    
    public var body: some View {
        FloatingPillView(state: stateModel.state, onStop: onStop, onCancel: onCancel)
    }
}
