import SwiftUI

public enum PillState: Equatable, Sendable {
    case idle
    case listening(audioLevel: Float, livePartial: String = "", isLocked: Bool = false, elapsedSeconds: Int = 0)
    case transcribing
    case success(preview: String)
    case error(message: String)
}

public struct FloatingPillView: View {
    public let state: PillState
    public var onStop: (() -> Void)?
    
    public init(state: PillState, onStop: (() -> Void)? = nil) {
        self.state = state
        self.onStop = onStop
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .idle:
                EmptyView()
                
            case .listening(let level, let livePartial, let isLocked, let elapsedSeconds):
                // Pulsing recording indicator dot
                Circle()
                    .fill(EchoTheme.recordingRed)
                    .frame(width: 8, height: 8)
                    .shadow(color: EchoTheme.recordingRed.opacity(0.8), radius: 5)
                
                // Real-time audio waveform bars
                HStack(spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(EchoTheme.accent)
                            .frame(
                                width: 2.5,
                                height: max(5, CGFloat(level) * 28.0 * CGFloat((index % 3 + 1)) * 0.4)
                            )
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: level)
                    }
                }
                .frame(width: 24, height: 20)
                
                // Live Duration Timer (e.g. 00:14)
                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isLocked ? EchoTheme.accent : EchoTheme.textSecondary)
                
                // Hands-Free Lock Badge
                if isLocked {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("LOCKED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(EchoTheme.accent.opacity(0.22))
                    .foregroundColor(EchoTheme.accent)
                    .clipShape(Capsule())
                }
                
                // Live Streamed Words
                if livePartial.isEmpty {
                    Text(isLocked ? "Hands-Free... (Tap ⌃ or Stop)" : "Listening (Hold ⌃ · 2x Lock)...")
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
                
                // High-Priority Stop & Inject Button
                Button(action: {
                    onStop?()
                }) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                        Text("Stop")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(EchoTheme.recordingRed)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: EchoTheme.accent))
                    .frame(width: 16, height: 16)
                
                Text("Finalizing & Injecting...")
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassmorphicPill()
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state)
    }
}
