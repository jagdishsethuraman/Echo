import SwiftUI
import ApplicationServices

public struct MeetingStudioView: View {
    public let session: MeetingSession
    public let micLevel: Float
    public let systemLevel: Float
    public let isRecording: Bool
    
    public var onToggleRecord: (() -> Void)?
    public var onExportMarkdown: (() -> Void)?
    
    public init(
        session: MeetingSession,
        micLevel: Float = 0.0,
        systemLevel: Float = 0.0,
        isRecording: Bool = false,
        onToggleRecord: (() -> Void)? = nil,
        onExportMarkdown: (() -> Void)? = nil
    ) {
        self.session = session
        self.micLevel = micLevel
        self.systemLevel = systemLevel
        self.isRecording = isRecording
        self.onToggleRecord = onToggleRecord
        self.onExportMarkdown = onExportMarkdown
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Swiss Editorial Top Bar
            HStack(spacing: 16) {
                // Atelier Status Pill
                HStack(spacing: 8) {
                    Circle()
                        .fill(isRecording ? EchoTheme.recordingRed : EchoTheme.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: isRecording ? EchoTheme.recordingRed.opacity(0.8) : Color.clear, radius: 4)
                    Text("ECHO // ACOUSTIC STUDIO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(EchoTheme.accent)
                    Text("· \(session.title)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(EchoTheme.textSecondary)
                }
                
                Spacer()
                
                // Hardware & Telemetry meters
                HStack(spacing: 14) {
                    AudioMeterPill(label: "MIC", level: micLevel, color: EchoTheme.accent)
                    AudioMeterPill(label: "MEETING", level: systemLevel, color: EchoTheme.attendeeAccent)
                    
                    // Meeting Record Toggle Button
                    Button(action: { onToggleRecord?() }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isRecording ? EchoTheme.recordingRed : EchoTheme.accent)
                                .frame(width: 6, height: 6)
                            Text(isRecording ? "Stop Meeting" : "Start Meeting")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isRecording ? EchoTheme.recordingRed : EchoTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isRecording ? EchoTheme.recordingRed.opacity(0.15) : EchoTheme.accent.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isRecording ? EchoTheme.recordingRed.opacity(0.4) : EchoTheme.accent.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(EchoTheme.background)
            .overlay(Divider().background(EchoTheme.border), alignment: .bottom)
            
            // Accessibility Permission Helper Banner (if needed)
            if !AXIsProcessTrusted() {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(EchoTheme.accent)
                    Text("Accessibility permission needed for auto-pasting at active cursor.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(EchoTheme.textPrimary)
                    Spacer()
                    Button("Grant in System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(EchoTheme.accent)
                    .cornerRadius(4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(EchoTheme.accent.opacity(0.12))
                .overlay(Divider().background(EchoTheme.border), alignment: .bottom)
            }
            
            // Bento Grid Split-Pane (Timeline 62% + Live Notes 38%)
            HStack(spacing: 0) {
                // Left Pane: Dual-Channel Conversational Timeline
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("CONVERSATION STREAM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(EchoTheme.textMuted)
                        Spacer()
                        Text("PHONON-2 · 37.7X RTF")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(EchoTheme.accent.opacity(0.8))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(EchoTheme.cardBackground.opacity(0.5))
                    .overlay(Divider().background(EchoTheme.borderLight), alignment: .bottom)
                    
                    TranscriptTimelineView(segments: session.segments)
                }
                .frame(maxWidth: .infinity)
                .background(EchoTheme.background)
                
                // Vertical Brass Divider
                Rectangle()
                    .fill(EchoTheme.border)
                    .frame(width: 1)
                
                // Right Pane: Live AI Executive Notes (Swiss Bento)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("LIVE AI EXECUTIVE NOTES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(EchoTheme.textMuted)
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(EchoTheme.accent)
                    }
                    .padding(.bottom, 4)
                    
                    // Decisions Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key Decisions")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(EchoTheme.accent)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            DecisionRow(text: "Single binary unified app (saves 1.2 GB RAM).")
                            DecisionRow(text: "Phonon-2 INT6 locked as primary offline STT.")
                            DecisionRow(text: "Every dictation saved to clipboard + studio timeline.")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EchoTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(EchoTheme.borderLight, lineWidth: 1))
                    
                    // Action Items Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Items")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(EchoTheme.textPrimary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            ActionCheckRow(isDone: true, text: "Benchmark Swift loopback engine")
                            ActionCheckRow(isDone: true, text: "Build non-activating floating HUD")
                            ActionCheckRow(isDone: true, text: "Dual-channel loopback & VAD")
                            ActionCheckRow(isDone: true, text: "Universal clipboard & cursor injection")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EchoTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(EchoTheme.borderLight, lineWidth: 1))
                    
                    Spacer()
                    
                    // Export to Obsidian Button
                    Button(action: { onExportMarkdown?() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .bold))
                            Text("Export Notes to Obsidian (.md)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(EchoTheme.accent)
                        .cornerRadius(8)
                        .shadow(color: EchoTheme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(18)
                .frame(width: 290)
                .background(EchoTheme.cardBackground.opacity(0.35))
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .background(EchoTheme.background)
    }
}

struct DecisionRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundColor(EchoTheme.accent)
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(EchoTheme.textSecondary)
                .lineSpacing(2)
        }
    }
}

struct ActionCheckRow: View {
    let isDone: Bool
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(isDone ? EchoTheme.accent : EchoTheme.textMuted)
            Text(text)
                .font(.system(size: 11, weight: isDone ? .regular : .medium))
                .foregroundColor(isDone ? EchoTheme.textSecondary : EchoTheme.textPrimary)
        }
    }
}

public struct AudioMeterPill: View {
    public let label: String
    public let level: Float
    public let color: Color
    
    public var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(EchoTheme.textMuted)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(EchoTheme.borderLight)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, level))))
                }
            }
            .frame(width: 40, height: 4)
        }
    }
}
