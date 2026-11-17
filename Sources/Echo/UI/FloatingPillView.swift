import SwiftUI

public enum PillState: Equatable, Sendable {
    case idle
    case listening(audioLevel: Float, livePartial: String = "", isLocked: Bool = false)
    case transcribing
    case success(preview: String)
    case error(message: String)
}

public struct FloatingPillView: View {
    public let state: PillState
    
    public init(state: PillState) {
        self.state = state
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .idle:
                EmptyView()
                
            case .listening(let level, let livePartial, let isLocked):
                // Pulsing recording dot
                Circle()
                    .fill(EchoTheme.recordingRed)
                    .frame(width: 8, height: 8)
                    .shadow(color: EchoTheme.recordingRed.opacity(0.8), radius: 5)
                
                // Real-time audio waveform bars
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(EchoTheme.accent)
                            .frame(
                                width: 3,
                                height: max(6, CGFloat(level) * 30.0 * CGFloat((index % 3 + 1)) * 0.4)
                            )
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: level)
                    }
                }
                .frame(width: 32, height: 22)
                
                // Hands-Free Lock Badge
                if isLocked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("LOCKED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(EchoTheme.accent.opacity(0.22))
                    .foregroundColor(EchoTheme.accent)
                    .clipShape(Capsule())
                }
                
                // Live Streamed Words
                if livePartial.isEmpty {
                    Text(isLocked ? "Hands-Free (Tap ⌃ to Finish)..." : "Listening (Hold ⌃ · 2x Lock)...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(EchoTheme.textSecondary)
                } else {
                    HStack(spacing: 4) {
                        Text(livePartial)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(EchoTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        // Blinking typing cursor
                        Rectangle()
                            .fill(EchoTheme.accent)
                            .frame(width: 2, height: 14)
                    }
                }
                
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: EchoTheme.accent))
                    .frame(width: 16, height: 16)
                
                Text("Finalizing...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(EchoTheme.textSecondary)
                
            case .success(let preview):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(EchoTheme.successGreen)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(preview.isEmpty ? "Transcribed" : preview)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(EchoTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(EchoTheme.recordingRed)
                    .font(.system(size: 14))
                
                Text(msg)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(EchoTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassmorphicPill()
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state)
    }
}
