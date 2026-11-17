import SwiftUI

public struct TranscriptTimelineView: View {
    public let segments: [TranscriptSegment]
    
    public init(segments: [TranscriptSegment]) {
        self.segments = segments
    }
    
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if segments.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.system(size: 28))
                            .foregroundColor(EchoTheme.textMuted.opacity(0.4))
                        Text("Waiting for dual-channel audio...")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(EchoTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.top, 50)
                } else {
                    ForEach(segments) { segment in
                        SwissTranscriptBubble(segment: segment)
                    }
                }
            }
            .padding(18)
        }
    }
}

public struct SwissTranscriptBubble: View {
    public let segment: TranscriptSegment
    
    private var isYou: Bool {
        segment.speaker == .you
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: segment.timestamp)
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Editorial Accent Rail
            Rectangle()
                .fill(isYou ? EchoTheme.accent : EchoTheme.attendeeAccent)
                .frame(width: 2.5)
                .cornerRadius(1)
            
            VStack(alignment: .leading, spacing: 6) {
                // Monospace Metadata Header
                HStack(spacing: 8) {
                    Text(segment.speaker.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isYou ? EchoTheme.accent : EchoTheme.attendeeAccent)
                    
                    Text("·  \(timeString)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(EchoTheme.textMuted)
                    
                    Spacer()
                    
                    Text(isYou ? "MIC 16k" : "LOOPBACK")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(EchoTheme.textMuted.opacity(0.8))
                }
                
                // Quote body text with Swiss editorial feel
                Text("\"\(segment.text)\"")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(EchoTheme.textPrimary)
                    .lineSpacing(4)
            }
            .padding(.vertical, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isYou ? EchoTheme.cardBackground.opacity(0.8) : EchoTheme.cardBackground.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isYou ? EchoTheme.border.opacity(0.5) : EchoTheme.borderLight, lineWidth: 1)
                )
        )
    }
}
