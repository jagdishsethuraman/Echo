import SwiftUI
import AppKit

// MARK: - Palette

/// Echo's visual language: a native macOS dark "graphite frost" surface with a
/// cool, low-saturation accent pair. The palette intentionally avoids the old
/// brass/lavender combination in favor of colors that sit quietly next to
/// system materials.
public enum EchoTheme {
    // Base surfaces (used over NSVisualEffectView vibrancy)
    public static let background = Color(red: 0.075, green: 0.082, blue: 0.098)
    public static let windowBackground = Color(red: 0.105, green: 0.114, blue: 0.133)
    public static let windowTint = Color(red: 0.085, green: 0.092, blue: 0.108)
    public static let sidebarBackground = Color(red: 0.095, green: 0.103, blue: 0.120)

    // Elevated surfaces
    public static let cardBackground = Color.white.opacity(0.055)
    public static let cardBackgroundSubtle = Color.white.opacity(0.030)
    public static let cardBackgroundElevated = Color.white.opacity(0.085)
    public static let hoverBackground = Color.white.opacity(0.070)
    public static let controlBackground = Color.white.opacity(0.060)

    // Hairlines & glass highlights
    public static let border = Color.white.opacity(0.105)
    public static let borderLight = Color.white.opacity(0.055)
    public static let borderAccent = accent.opacity(0.40)
    public static let separator = Color.white.opacity(0.075)
    public static let highlight = Color.white.opacity(0.16)

    // Accents: frost blue primary, sea-glass teal secondary
    public static let accent = Color(red: 0.545, green: 0.708, blue: 0.969) // #8BB5F7
    public static let accentMuted = Color(red: 0.545, green: 0.708, blue: 0.969, opacity: 0.15)
    public static let accentStrong = Color(red: 0.420, green: 0.596, blue: 0.898)
    public static let attendeeAccent = Color(red: 0.435, green: 0.831, blue: 0.780) // #6FD4C7
    public static let textOnAccent = Color(red: 0.055, green: 0.070, blue: 0.098)

    // Typography
    public static let textPrimary = Color(white: 0.955)
    public static let textSecondary = Color(white: 0.685)
    public static let textMuted = Color(white: 0.430)
    public static let textFaint = Color(white: 0.320)

    // Status
    public static let recordingRed = Color(red: 0.984, green: 0.427, blue: 0.404) // #FB6D67
    public static let successGreen = Color(red: 0.400, green: 0.851, blue: 0.643)  // #66D9A4
    public static let warningAmber = Color(red: 0.949, green: 0.757, blue: 0.427)

    // Geometry
    public static let windowRadius: CGFloat = 12
    public static let cardRadius: CGFloat = 11
    public static let controlRadius: CGFloat = 7
}

// MARK: - Typography

public enum EchoFont {
    public static let windowTitle = Font.system(size: 13, weight: .semibold)
    public static let section = Font.system(size: 11, weight: .semibold)
    public static let body = Font.system(size: 12, weight: .regular)
    public static let bodyMedium = Font.system(size: 12, weight: .medium)
    public static let transcript = Font.system(size: 13, weight: .regular)
    public static let caption = Font.system(size: 10.5, weight: .regular)
    public static let captionMedium = Font.system(size: 10.5, weight: .medium)
    public static let mono = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    public static let timer = Font.system(size: 11.5, weight: .semibold, design: .monospaced)
}

// MARK: - Native frosted background

/// Wraps a native `NSVisualEffectView` so SwiftUI can show real macOS
/// vibrancy instead of a flat approximation.
public struct FrostedBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var isEmphasized: Bool
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        isEmphasized: Bool = true,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.isEmphasized = isEmphasized
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
    }
}

/// The studio's full-window frosted graphite backdrop.
public struct FrostedBackdrop: View {
    public init() {}

    public var body: some View {
        ZStack {
            FrostedBackground(
                material: .hudWindow,
                blendingMode: .behindWindow,
                isEmphasized: true,
                state: .followsWindowActiveState
            )
            .allowsHitTesting(false)
            LinearGradient(
                colors: [
                    Color(red: 0.135, green: 0.147, blue: 0.170).opacity(0.66),
                    Color(red: 0.088, green: 0.096, blue: 0.112).opacity(0.76),
                    Color(red: 0.070, green: 0.077, blue: 0.091).opacity(0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.white.opacity(0.045), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

public struct FrostedSurfaceModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var fill: Color
    public var stroke: Color
    public var isElevated: Bool

    public init(
        cornerRadius: CGFloat = EchoTheme.cardRadius,
        fill: Color = EchoTheme.cardBackground,
        stroke: Color = EchoTheme.borderLight,
        isElevated: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.stroke = stroke
        self.isElevated = isElevated
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fill)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
            .shadow(
                color: isElevated ? Color.black.opacity(0.22) : .clear,
                radius: isElevated ? 10 : 0,
                x: 0,
                y: isElevated ? 4 : 0
            )
    }
}

public extension View {
    func frostedCard(
        cornerRadius: CGFloat = EchoTheme.cardRadius,
        fill: Color = EchoTheme.cardBackground,
        stroke: Color = EchoTheme.borderLight,
        isElevated: Bool = false
    ) -> some View {
        modifier(
            FrostedSurfaceModifier(
                cornerRadius: cornerRadius,
                fill: fill,
                stroke: stroke,
                isElevated: isElevated
            )
        )
    }

    /// The HUD pill's glass capsule.
    func glassmorphicPill() -> some View {
        modifier(GlassmorphicPillModifier())
    }
}

public struct GlassmorphicPillModifier: ViewModifier {
    public func body(content: Content) -> some View {
        let capsule = Capsule()
        content
            .background {
                capsule.fill(
                    LinearGradient(colors: [EchoTheme.windowBackground, EchoTheme.windowTint],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(capsule)
            .overlay {
                capsule.strokeBorder(
                    LinearGradient(colors: [EchoTheme.highlight, EchoTheme.borderLight],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
    }
}

// MARK: - Controls

/// Subtle press animation shared by Echo's custom controls.
public struct AtelierButtonStyle: ButtonStyle {
    @State private var isHovered = false
    public let isPrimary: Bool

    public init(isPrimary: Bool = false) {
        self.isPrimary = isPrimary
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.05 : (isHovered ? 0.05 : 0.0))
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// Filled accent button (primary action).
public struct AccentButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(EchoTheme.textOnAccent)
            .brightness(configuration.isPressed ? -0.06 : (isHovered ? 0.06 : 0.0))
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

/// Quiet glass button used in toolbars and cards.
public struct GlassButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.11 : 0.065))
            }
            .overlay {
                RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.16 : 0.09), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

public extension View {
    /// Standard section label used above panes and cards.
    func echoSectionLabel() -> some View {
        self
            .font(EchoFont.section)
            .foregroundStyle(EchoTheme.textMuted)
            .tracking(0.2)
    }
}
