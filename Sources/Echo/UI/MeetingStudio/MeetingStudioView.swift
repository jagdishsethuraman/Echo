import SwiftUI
import AppKit
import ApplicationServices
import AVFoundation

public struct LiveAudioMetersCluster: View {
    @ObservedObject var levels: MeetingAudioLevels

    public init(levels: MeetingAudioLevels) {
        self.levels = levels
    }

    public var body: some View {
        HStack(spacing: 14) {
            AudioMeterPill(label: "MIC", level: levels.micLevel, color: EchoTheme.accent)
            AudioMeterPill(label: "MEETING", level: levels.systemLevel, color: EchoTheme.attendeeAccent)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(EchoTheme.cardBackgroundSubtle)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(EchoTheme.borderLight, lineWidth: 1)
        }
    }
}

public struct MeetingStudioView: View {
    public let session: MeetingSession
    public let audioLevels: MeetingAudioLevels
    public let isRecording: Bool

    public var onToggleRecord: (() -> Void)?
    public var onExportMarkdown: (() -> Void)?

    @ObservedObject var memoryState = WordMemoryState.shared
    @ObservedObject var coordinator = AppCoordinator.shared
    @ObservedObject var meetingCoordinator = AppCoordinator.shared.meetingCoordinator

    public var micLevel: Float { audioLevels.micLevel }
    public var systemLevel: Float { audioLevels.systemLevel }

    @State private var searchFilter: String = ""
    @State private var showNotesCopied: Bool = false
    @State private var newActionText: String = ""
    @State private var isAddingActionItem: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var actionItems: [ActionItemState] = []
    @State private var decisions: [String] = []
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @State private var isMicrophoneAuthorized: Bool = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private let incrementalExtractor = IncrementalNotesExtractor()

    public init(
        session: MeetingSession,
        audioLevels: MeetingAudioLevels = MeetingAudioLevels(),
        isRecording: Bool = false,
        onToggleRecord: (() -> Void)? = nil,
        onExportMarkdown: (() -> Void)? = nil
    ) {
        self.session = session
        self.audioLevels = audioLevels
        self.isRecording = isRecording
        self.onToggleRecord = onToggleRecord
        self.onExportMarkdown = onExportMarkdown
    }

    public init(
        session: MeetingSession,
        micLevel: Float = 0.0,
        systemLevel: Float = 0.0,
        isRecording: Bool = false,
        onToggleRecord: (() -> Void)? = nil,
        onExportMarkdown: (() -> Void)? = nil
    ) {
        self.init(
            session: session,
            audioLevels: MeetingAudioLevels(micLevel: micLevel, systemLevel: systemLevel),
            isRecording: isRecording,
            onToggleRecord: onToggleRecord,
            onExportMarkdown: onExportMarkdown
        )
    }

    private func loadSessionData(for sessionId: UUID) {
        incrementalExtractor.reset(for: sessionId)
        let persisted = DatabaseManager.shared.fetchActionItems(sessionId: sessionId)
        actionItems = persisted
        let (updatedDecisions, newActions) = incrementalExtractor.update(segments: session.segments, for: sessionId)
        decisions = updatedDecisions
        for text in newActions {
            let lower = text.lowercased()
            if !actionItems.contains(where: { $0.text.lowercased() == lower }) {
                let item = ActionItemState(text: text, isDone: false)
                actionItems.append(item)
                DatabaseManager.shared.saveActionItem(item, sessionId: sessionId)
            }
        }
    }

    private func syncActionItems() {
        let (updatedDecisions, newActions) = incrementalExtractor.update(segments: session.segments, for: session.id)
        decisions = updatedDecisions
        for text in newActions {
            let lower = text.lowercased()
            if !actionItems.contains(where: { $0.text.lowercased() == lower }) {
                let item = ActionItemState(text: text, isDone: false)
                actionItems.append(item)
                DatabaseManager.shared.saveActionItem(item, sessionId: session.id)
            }
        }
    }

    private var filteredSegments: [TranscriptSegment] {
        let trimmed = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return session.segments }
        return session.segments.filter {
            $0.text.localizedCaseInsensitiveContains(trimmed) ||
            $0.speaker.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func copyExecutiveNotes() {
        let notes = MeetingNotesExtractor.formatMarkdown(
            title: session.title,
            decisions: decisions,
            actionItems: actionItems
        )

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(notes, forType: .string)

        withAnimation(.easeOut(duration: 0.15)) {
            showNotesCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                showNotesCopied = false
            }
        }
    }

    private func commitNewActionItem() {
        let trimmed = newActionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = ActionItemState(text: trimmed, isDone: false)
        actionItems.append(item)
        DatabaseManager.shared.saveActionItem(item, sessionId: session.id)
        newActionText = ""
    }

    private func refreshPermissions() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        isMicrophoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            toolbar

            if memoryState.isVisible {
                WordMemoryDrawerView(memoryState: memoryState)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !isMicrophoneAuthorized {
                microphoneBanner
            }

            if !isAccessibilityTrusted {
                permissionBanner
            }

            if let error = meetingCoordinator.captureError {
                captureErrorBanner(error)
            }

            Divider()
                .overlay(EchoTheme.separator)

            HStack(spacing: 0) {
                transcriptPane
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(EchoTheme.separator)
                    .frame(width: 1)

                notesPane
                    .frame(width: 320)
            }
        }
        .background(FrostedBackdrop())
        .preferredColorScheme(.dark)
        .frame(minWidth: 840, minHeight: 560)
        .onAppear {
            refreshPermissions()
            loadSessionData(for: session.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onChange(of: session.id) { _, newId in
            loadSessionData(for: newId)
        }
        .onChange(of: session.segments) {
            syncActionItems()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            appMark

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text("Meeting Studio")
                        .font(EchoFont.windowTitle)
                        .foregroundStyle(EchoTheme.textPrimary)

                    statusBadge
                }
                HStack(spacing: 5) {
                    Text(session.title)
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textSecondary)
                        .lineLimit(1)
                    Text("·")
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textFaint)
                    Text(coordinator.statusMessage)
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            LiveAudioMetersCluster(levels: audioLevels)

            Button {
                memoryState.reload()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    memoryState.isVisible.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 10, weight: .medium))
                    Text("Memory")
                        .font(EchoFont.bodyMedium)
                    Text("\(memoryState.entries.count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(memoryState.isVisible ? EchoTheme.textOnAccent : EchoTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background {
                            Capsule().fill(memoryState.isVisible ? Color.white.opacity(0.22) : Color.white.opacity(0.07))
                        }
                }
                .foregroundStyle(memoryState.isVisible ? EchoTheme.textOnAccent : EchoTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background {
                    RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                        .fill(memoryState.isVisible ? EchoTheme.accent : Color.clear)
                }
            }
            .buttonStyle(GlassButtonStyle())
            .help("Word Memory & Dictionary")

            recordButton
        }
        .padding(.leading, 78)
        .padding(.trailing, 16)
        .frame(height: 56)
        .background {
            ZStack {
                Color.black.opacity(0.12)
                LinearGradient(
                    colors: [Color.white.opacity(0.030), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(EchoTheme.separator).frame(height: 1)
        }
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(EchoTheme.accent.opacity(0.14))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(EchoTheme.accent.opacity(0.26), lineWidth: 1)
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EchoTheme.accent)
        }
        .frame(width: 27, height: 27)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isRecording ? EchoTheme.recordingRed : EchoTheme.textMuted)
                .frame(width: 5.5, height: 5.5)
                .shadow(color: isRecording ? EchoTheme.recordingRed.opacity(0.7) : .clear, radius: 3)
            Text(coordinator.isMeetingFinalizing ? "Finalizing" : (isRecording ? "Recording" : "Ready"))
                .font(EchoFont.captionMedium)
                .foregroundStyle(isRecording ? EchoTheme.recordingRed : EchoTheme.textMuted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background {
            Capsule().fill(isRecording ? EchoTheme.recordingRed.opacity(0.12) : Color.white.opacity(0.055))
        }
        .overlay {
            Capsule().strokeBorder(isRecording ? EchoTheme.recordingRed.opacity(0.24) : EchoTheme.borderLight, lineWidth: 1)
        }
    }

    private var recordButton: some View {
        Button {
            onToggleRecord?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(coordinator.isMeetingFinalizing ? "Finalizing…" : (isRecording ? "Stop Meeting" : "Start Meeting"))
                    .font(EchoFont.bodyMedium)
                    .fixedSize()
            }
            .foregroundStyle(isRecording ? EchoTheme.recordingRed : EchoTheme.textOnAccent)
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .buttonStyle(RecordingButtonStyle(isRecording: isRecording))
        .disabled(coordinator.isMeetingFinalizing)
        .help(isRecording ? "Stop the current meeting recording" : "Start recording a meeting")
        .accessibilityLabel(coordinator.isMeetingFinalizing ? "Finalizing meeting transcript" : (isRecording ? "Stop meeting recording" : "Start meeting recording"))
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "hand.raised")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EchoTheme.accent)

            Text("Accessibility access is off")
                .font(EchoFont.captionMedium)
                .foregroundStyle(EchoTheme.textPrimary)

            Text("Echo can't paste into the active app yet.")
                .font(EchoFont.caption)
                .foregroundStyle(EchoTheme.textSecondary)

            Spacer(minLength: 8)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(LinkButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(EchoTheme.accent.opacity(0.055))
        .overlay(alignment: .bottom) {
            Rectangle().fill(EchoTheme.separator).frame(height: 1)
        }
    }

    private var microphoneBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EchoTheme.recordingRed)

            Text("Microphone access is off")
                .font(EchoFont.captionMedium)
                .foregroundStyle(EchoTheme.textPrimary)

            Text("Echo cannot capture audio until microphone permission is granted in Settings.")
                .font(EchoFont.caption)
                .foregroundStyle(EchoTheme.textSecondary)

            Spacer(minLength: 8)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(LinkButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(EchoTheme.recordingRed.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(EchoTheme.recordingRed.opacity(0.25)).frame(height: 1)
        }
    }

    private func captureErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EchoTheme.recordingRed)

            Text("Meeting notice")
                .font(EchoFont.captionMedium)
                .foregroundStyle(EchoTheme.recordingRed)

            Text(message)
                .font(EchoFont.caption)
                .foregroundStyle(EchoTheme.textSecondary)
                .lineLimit(3)
                .help(message)

            Spacer(minLength: 8)

            Button {
                meetingCoordinator.captureError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(EchoTheme.textSecondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss meeting notice")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 34)
        .background(EchoTheme.recordingRed.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(EchoTheme.recordingRed.opacity(0.25)).frame(height: 1)
        }
    }

    // MARK: - Transcript pane

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Transcript")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(EchoTheme.textPrimary)

                Text("\(session.segments.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EchoTheme.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.white.opacity(0.07)))

                Spacer(minLength: 10)

                searchField

                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7.5, weight: .semibold))
                    Text("On-device · Phonon-2")
                        .font(EchoFont.caption)
                }
                .foregroundStyle(EchoTheme.textMuted)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.white.opacity(0.018))
            .overlay(alignment: .bottom) {
                Rectangle().fill(EchoTheme.separator).frame(height: 1)
            }

            if !searchFilter.isEmpty {
                HStack(spacing: 6) {
                    Text("\(filteredSegments.count) match\(filteredSegments.count == 1 ? "" : "es")")
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.accent)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            TranscriptTimelineView(segments: filteredSegments)
        }
        .background(Color.black.opacity(0.10))
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(EchoTheme.textMuted)

            ZStack(alignment: .leading) {
                if searchFilter.isEmpty {
                    Text("Search transcript")
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textFaint)
                }
                TextField("", text: $searchFilter)
                    .textFieldStyle(.plain)
                    .font(EchoFont.caption)
                    .foregroundStyle(EchoTheme.textPrimary)
                    .focused($isSearchFocused)
            }

            if !searchFilter.isEmpty {
                Button {
                    searchFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(EchoTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .frame(width: 186, height: 24)
        .background {
            RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                .fill(EchoTheme.controlBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? EchoTheme.accent.opacity(0.7) : EchoTheme.borderLight,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.12), value: isSearchFocused)
        .onExitCommand {
            searchFilter = ""
            isSearchFocused = false
        }
    }

    // MARK: - Notes pane

    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Notes")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(EchoTheme.textPrimary)

                Text("AI")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(EchoTheme.accent)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(EchoTheme.accent.opacity(0.13)))

                Spacer()

                Button(action: copyExecutiveNotes) {
                    HStack(spacing: 4) {
                        Image(systemName: showNotesCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                        Text(showNotesCopied ? "Copied" : "Copy")
                            .font(EchoFont.captionMedium)
                    }
                    .foregroundStyle(showNotesCopied ? EchoTheme.successGreen : EchoTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                }
                .buttonStyle(GlassButtonStyle())
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.white.opacity(0.018))
            .overlay(alignment: .bottom) {
                Rectangle().fill(EchoTheme.separator).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    decisionsCard
                    actionItemsCard
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)

            exportButton
        }
        .background(Color.white.opacity(0.012))
    }

    private var decisionsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(EchoTheme.accent)
                Text("Key Decisions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoTheme.textPrimary)
                if !decisions.isEmpty {
                    Text("\(decisions.count)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(EchoTheme.textMuted)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(EchoTheme.textFaint)
            }

            VStack(alignment: .leading, spacing: 7) {
                if decisions.isEmpty {
                    Text("Decisions and agreements reached during discussion will appear here.")
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textMuted)
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ForEach(decisions, id: \.self) { decision in
                        DecisionRow(text: decision)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard()
    }

    private var actionItemsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(EchoTheme.attendeeAccent)
                Text("Action Items")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoTheme.textPrimary)
                if !actionItems.isEmpty {
                    Text("\(actionItems.filter(\.isDone).count)/\(actionItems.count)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(EchoTheme.textMuted)
                }
                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isAddingActionItem.toggle()
                    }
                } label: {
                    Image(systemName: isAddingActionItem ? "xmark" : "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(EchoTheme.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(isAddingActionItem ? "Cancel" : "Add action item")
            }

            VStack(alignment: .leading, spacing: 7) {
                if actionItems.isEmpty && !isAddingActionItem {
                    Text("Commitments and next steps mentioned aloud will appear here.")
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textMuted)
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ForEach($actionItems) { $item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                item.isDone.toggle()
                                DatabaseManager.shared.updateActionItemDone(id: item.id, isDone: item.isDone)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.isDone ? EchoTheme.accent : EchoTheme.textFaint)
                                Text(item.text)
                                    .font(EchoFont.body)
                                    .foregroundStyle(item.isDone ? EchoTheme.textMuted : EchoTheme.textSecondary)
                                    .strikethrough(item.isDone, color: EchoTheme.textFaint)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isAddingActionItem {
                HStack(spacing: 6) {
                    TextField("New action item", text: $newActionText)
                        .textFieldStyle(.plain)
                        .font(EchoFont.caption)
                        .foregroundStyle(EchoTheme.textPrimary)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(EchoTheme.controlBackground)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(EchoTheme.borderLight, lineWidth: 1)
                        }
                        .onSubmit(commitNewActionItem)

                    Button(action: commitNewActionItem) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EchoTheme.textOnAccent)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(EchoTheme.accent))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard()
    }

    private var exportButton: some View {
        VStack(spacing: 0) {
            Divider().overlay(EchoTheme.separator)

            Button {
                onExportMarkdown?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Export Notes")
                        .font(EchoFont.bodyMedium)
                }
                .foregroundStyle(EchoTheme.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(AccentButtonStyle())
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(EchoTheme.accent)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(14)
            .disabled(coordinator.isMeetingFinalizing)
            .help("Copy the meeting summary and action items as Markdown")
        }
    }
}

// MARK: - Supporting views

struct DecisionRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(EchoTheme.accent.opacity(0.7))
                .frame(width: 3.5, height: 3.5)
                .padding(.top, 5)
            Text(text)
                .font(EchoFont.body)
                .foregroundStyle(EchoTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
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
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(EchoTheme.textMuted)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.75), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, level))))
                }
            }
            .frame(width: 38, height: 3.5)
        }
    }
}

struct WordMemoryDrawerView: View {
    @ObservedObject var memoryState: WordMemoryState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(EchoTheme.accent)
                Text("Word Memory")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoTheme.textPrimary)
                Text("\(memoryState.entries.count) hotwords")
                    .font(EchoFont.caption)
                    .foregroundStyle(EchoTheme.textMuted)
                Spacer()
                Text("Corrections are applied to new transcripts")
                    .font(EchoFont.caption)
                    .foregroundStyle(EchoTheme.textFaint)
            }

            HStack(spacing: 8) {
                memoryField("Misheard text (e.g. phone on)", text: $memoryState.newRawWord)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(EchoTheme.textMuted)

                memoryField("Remembered as (e.g. Phonon)", text: $memoryState.newPreferredWord)

                Button {
                    memoryState.add()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Remember")
                            .font(EchoFont.captionMedium)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                }
                .buttonStyle(AccentButtonStyle())
                .background {
                    RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                        .fill(EchoTheme.accent)
                }
                .clipShape(RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(memoryState.entries) { entry in
                        HStack(spacing: 5) {
                            Text(entry.rawPattern)
                                .font(EchoFont.mono)
                                .foregroundStyle(EchoTheme.textSecondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7))
                                .foregroundStyle(EchoTheme.textFaint)
                            Text(entry.preferredReplacement)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(EchoTheme.accent)

                            Button {
                                memoryState.delete(id: entry.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(EchoTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(Capsule().fill(Color.white.opacity(0.055)))
                        .overlay(Capsule().strokeBorder(EchoTheme.borderLight, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(EchoTheme.sidebarBackground.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(EchoTheme.separator).frame(height: 1)
        }
    }

    private func memoryField(_ prompt: String, text: Binding<String>) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(prompt)
                    .font(EchoFont.caption)
                    .foregroundStyle(EchoTheme.textFaint)
            }
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(EchoFont.caption)
                .foregroundStyle(EchoTheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                .fill(EchoTheme.controlBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                .strokeBorder(EchoTheme.borderLight, lineWidth: 1)
        }
    }
}

// MARK: - Button styles

private struct RecordingButtonStyle: ButtonStyle {
    let isRecording: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isRecording ? EchoTheme.recordingRed : EchoTheme.textOnAccent)
            .background {
                RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                    .fill(
                        isRecording
                            ? EchoTheme.recordingRed.opacity(isHovered ? 0.22 : 0.15)
                            : EchoTheme.accent.opacity(configuration.isPressed ? 0.82 : (isHovered ? 1.0 : 0.94))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: EchoTheme.controlRadius, style: .continuous)
                    .strokeBorder(
                        isRecording ? EchoTheme.recordingRed.opacity(0.35) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

private struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EchoFont.captionMedium)
            .foregroundStyle(EchoTheme.accent.opacity(configuration.isPressed ? 0.7 : 1.0))
    }
}
