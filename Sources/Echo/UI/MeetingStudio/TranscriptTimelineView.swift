import SwiftUI

public struct TranscriptTimelineView: View {
    public let segments: [TranscriptSegment]

    public init(segments: [TranscriptSegment]) {
        self.segments = segments
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if segments.isEmpty {
                        emptyState
                    } else {
                        ForEach(segments) { segment in
                            TranscriptRow(segment: segment)
                                .id(segment.id)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onChange(of: segments.count) {
                if let lastId = segments.last?.id {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(EchoTheme.cardBackgroundSubtle)
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(EchoTheme.borderLight, lineWidth: 1)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(EchoTheme.textMuted)
            }
            .frame(width: 54, height: 54)

            Text("No transcript yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EchoTheme.textSecondary)

            Text("Start a meeting, or hold ⌃ Control to dictate.")
                .font(EchoFont.caption)
                .foregroundStyle(EchoTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.top, 30)
    }
}

public struct TranscriptRow: View {
    public let segment: TranscriptSegment

    @State private var isHovered = false
    @State private var showCopiedFeedback = false

    public init(segment: TranscriptSegment) {
        self.segment = segment
    }

    private var isYou: Bool {
        segment.speaker == .you
    }

    private var speakerColor: Color {
        isYou ? EchoTheme.accent : EchoTheme.attendeeAccent
    }

    private var speakerName: String {
        isYou ? "You" : "Meeting"
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: segment.timestamp)
    }

    private var durationString: String {
        segment.durationSeconds > 0
            ? String(format: "%.1fs", segment.durationSeconds)
            : ""
    }

    private func copyToClipboard(includeMetadata: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if includeMetadata {
            let badge = isYou ? "[You]" : "[Meeting]"
            pasteboard.setString("\(badge) (\(timeString)): \(segment.text)", forType: .string)
        } else {
            pasteboard.setString(segment.text, forType: .string)
        }

        withAnimation(.easeOut(duration: 0.15)) {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(speakerColor.opacity(0.13))
                Circle()
                    .strokeBorder(speakerColor.opacity(0.22), lineWidth: 1)
                Image(systemName: isYou ? "mic.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(speakerColor)
            }
            .frame(width: 26, height: 26)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(speakerName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(speakerColor)

                    Text(timeString)
                        .font(EchoFont.mono)
                        .foregroundStyle(EchoTheme.textMuted)

                    if !durationString.isEmpty {
                        Text(durationString)
                            .font(EchoFont.mono)
                            .foregroundStyle(EchoTheme.textFaint)
                    }

                    Spacer(minLength: 6)

                    if showCopiedFeedback {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7.5, weight: .bold))
                            Text("Copied")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(EchoTheme.successGreen)
                        .transition(.opacity)
                    } else if isHovered {
                        Button {
                            copyToClipboard(includeMetadata: false)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(EchoTheme.textSecondary)
                                .frame(width: 20, height: 18)
                                .background {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.white.opacity(0.07))
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Copy utterance")
                        .transition(.opacity)
                    }

                    Text(isYou ? "Mic" : "System")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(EchoTheme.textFaint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.045)))
                }

                Text(segment.text)
                    .font(EchoFont.transcript)
                    .foregroundStyle(EchoTheme.textPrimary.opacity(0.94))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? EchoTheme.hoverBackground : Color.clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.13)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                copyToClipboard(includeMetadata: false)
            } label: {
                Label("Copy Utterance", systemImage: "doc.on.doc")
            }

            Button {
                copyToClipboard(includeMetadata: true)
            } label: {
                Label("Copy with Timestamp & Speaker", systemImage: "doc.on.clipboard")
            }
        }
    }
}
