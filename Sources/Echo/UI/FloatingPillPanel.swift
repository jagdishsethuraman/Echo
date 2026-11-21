import AppKit
import SwiftUI

public final class FloatingPillPanel: NSPanel {
    private let stateModel: PillStateObservable
    private var dismissTimer: Timer?
    private var presentationID = UUID()
    public var onStopRequested: (() -> Void)?
    public var onCancelRequested: (() -> Void)?
    static let listeningWidth: CGFloat = 480
    
    public init() {
        self.stateModel = PillStateObservable()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.listeningWidth, height: 52),
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
        presentationID = UUID()
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
        
        if Self.targetWidth(for: oldState) != Self.targetWidth(for: state) {
            reposition(for: state, animate: true)
        }
        
        switch state {
        case .success, .notice, .error:
            dismissTimer?.invalidate()
            let presentationID = presentationID
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] timer in
                Task { @MainActor in
                    guard let self, self.presentationID == presentationID, self.dismissTimer === timer else { return }
                    self.hide()
                }
            }
        default:
            dismissTimer?.invalidate()
            dismissTimer = nil
        }
    }
    
    public func hide() {
        let presentationID = presentationID
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            guard self.presentationID == presentationID else { return }
            self.orderOut(nil)
            self.stateModel.state = .idle
        })
    }
    
    public static func measureTextWidth(_ text: String, font: NSFont = .systemFont(ofSize: 12, weight: .medium)) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return ceil(size.width)
    }
    
    public static func targetWidth(for state: PillState) -> CGFloat {
        switch state {
        case .idle:
            return 240
        case .listening:
            return listeningWidth
        case .transcribing:
            return 280
        case .success(let message), .notice(let message):
            let text = message.isEmpty ? "Transcribed" : message
            let textW = measureTextWidth(text)
            let rawWidth = max(280, 56 + textW + 28)
            let quantized = ceil(rawWidth / 30.0) * 30.0
            return min(720, max(280, quantized))
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
        let panelW = min(Self.targetWidth(for: state), screenRect.width)
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
