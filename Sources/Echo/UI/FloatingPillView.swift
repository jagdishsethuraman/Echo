import SwiftUI

public enum PillState: Equatable, Sendable {
    case idle
    case listening(audioLevel: Float, livePartial: String = "", isLocked: Bool = false, elapsedSeconds: Int = 0)
    case transcribing
    case success(preview: String)
    case notice(message: String)
    case error(message: String)
}

public struct FloatingPillView: View {
    @ObservedObject private var shortcuts = KeyboardShortcuts.shared
    public let state: PillState
    public var onStop: (() -> Void)?
    public var onCancel: (() -> Void)?

    public init(state: PillState, onStop: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.state = state
        self.onStop = onStop
        self.onCancel = onCancel
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
                Circle()
                    .fill(EchoTheme.recordingRed)
                    .frame(width: 7, height: 7)
                    .shadow(color: EchoTheme.recordingRed.opacity(0.8), radius: 4)

                HStack(spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(EchoTheme.accent)
                            .frame(
                                width: 2.5,
                                height: max(5, CGFloat(min(1.0, max(0.05, level))) * 22.0 * CGFloat((index % 3 + 1)) * 0.42)
                            )
                            .animation(.easeOut(duration: 0.08), value: level)
                    }
                }
                .frame(width: 24, height: 18)

                Text(formatDuration(elapsedSeconds))
                    .font(EchoFont.timer)
                    .foregroundStyle(isLocked ? EchoTheme.accent : EchoTheme.textSecondary)
                    .monospacedDigit()
                    .fixedSize()

                if isLocked {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7.5, weight: .bold))
                        Text("Locked")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(EchoTheme.accent.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(EchoTheme.accent.opacity(0.24), lineWidth: 1))
                    .foregroundStyle(EchoTheme.accent)
                    .fixedSize()
                }

                Group {
                    if livePartial.isEmpty {
                        Text(isLocked ? "Hands-free · tap Stop to finish" : "Listening · hold \(shortcuts[.pushToTalk].label) to talk")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(EchoTheme.textSecondary)
                    } else {
                        Text(livePartial)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(EchoTheme.textPrimary)
                            .truncationMode(.head)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Button {
                        onCancel?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(EchoTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(EchoTheme.controlBackground))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Discard recording (Esc)")

                    Button {
                        onStop?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text("Stop")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: 56, height: 24)
                        .background(Capsule().fill(EchoTheme.recordingRed))
                        .shadow(color: EchoTheme.recordingRed.opacity(0.3), radius: 3, y: 1)
                    }
                    .buttonStyle(AtelierButtonStyle())
                    .help("Finish & transcribe (\(shortcuts[.pushToTalk].label))")
                }
                .fixedSize()

            case .transcribing:
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: EchoTheme.accent))
                    .frame(width: 16, height: 16)

                Text("Finalizing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EchoTheme.textSecondary)

            case .success(let preview):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(EchoTheme.successGreen)
                    .font(.system(size: 13, weight: .semibold))

                Text(preview.isEmpty ? "Transcribed" : preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EchoTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .notice(let message):
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(EchoTheme.accent)
                    .font(.system(size: 13, weight: .semibold))

                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EchoTheme.textPrimary)
                    .lineLimit(1)

            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(EchoTheme.recordingRed)
                    .font(.system(size: 12))

                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EchoTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glassmorphicPill()
    }
}
