import SwiftUI

public enum EchoTheme {
    // Swiss Atelier Obsidian Palette
    public static let background = Color(red: 5/255, green: 5/255, blue: 7/255) // #050507 (Pure Obsidian)
    public static let cardBackground = Color(red: 14/255, green: 14/255, blue: 18/255) // #0e0e12 (Atelier Slate)
    public static let border = Color(red: 229/255, green: 169/255, blue: 60/255, opacity: 0.22) // Atelier Brass subtle rim
    public static let borderLight = Color(white: 1.0, opacity: 0.08)
    
    // Accents
    public static let accent = Color(red: 229/255, green: 169/255, blue: 60/255) // #e5a93c (Atelier Brass)
    public static let accentMuted = Color(red: 229/255, green: 169/255, blue: 60/255, opacity: 0.18)
    public static let attendeeAccent = Color(red: 192/255, green: 132/255, blue: 252/255) // #c084fc (Atelier Lavender)
    
    // Typography
    public static let textPrimary = Color(white: 0.98) // #fafafa
    public static let textSecondary = Color(red: 161/255, green: 161/255, blue: 170/255) // #a1a1aa
    public static let textMuted = Color(white: 0.45)
    
    // Status
    public static let recordingRed = Color(red: 239/255, green: 68/255, blue: 68/255) // #ef4444
    public static let successGreen = Color(red: 34/255, green: 197/255, blue: 94/255) // #22c55e
}

public struct GlassmorphicPillModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(EchoTheme.cardBackground.opacity(0.96))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(EchoTheme.border, lineWidth: 1)
                    )
            )
    }
}

public extension View {
    func glassmorphicPill() -> some View {
        modifier(GlassmorphicPillModifier())
    }
}
