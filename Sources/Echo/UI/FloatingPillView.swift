import SwiftUI

public enum PillState: Equatable, Sendable {
    case idle
    case listening(audioLevel: Float, livePartial: String = "")
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
                
            case .listening(let level, let livePartial):
                // Pulsing recording dot
                Circle()
                    .fill(EchoTheme.recordingRed)
                    .frame(width: 8, height: 8)
                    .shadow(color: EchoTheme.recordingRed.opacity(0.8), radius: 6)
                
                // Real-time audio waveform bars
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(EchoTheme.accent)
                            .frame(
                                width: 3,
                                height: max(6, CGFloat(level) * 32.0 * CGFloat((index % 3 + 1)) * 0.4)
                            )
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: level)
                    }
                }
                .frame(width: 32, height: 24)
                
                // Live Streamed Words
                if livePartial.isEmpty {
                    Text("Echo Listening...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(EchoTheme.textSecondary)
                } else {
                    HStack(spacing: 4) {
                        Text(livePartial)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(EchoTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        
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
                    .frame(maxWidth: 300, alignment: .leading)
                
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(EchoTheme.recordingRed)
                    .font(.system(size: 14))
                
                Text(msg)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(EchoTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassmorphicPill()
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state)
    }
}
