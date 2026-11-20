import AppKit
import AVFoundation
import Foundation

@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()
    
    // Core Engine Subsystems
    public let phononRunner: PhononProcessRunner
    public let transcriptionService: TranscriptionService
    public let textInjector: TextInjector
    public let hotkeyManager: HotkeyManager
    public let floatingPill: FloatingPillPanel
    public let audioHub: AudioHub
    public let micEngine: AudioEngineManager
    public let meetingCoordinator: MeetingCoordinator
    
    // State Tracking
    @Published public var isDictating: Bool = false
    @Published public private(set) var isMeetingActive = false
    @Published public private(set) var isMeetingFinalizing = false
    @Published public var statusMessage: String = "Echo Ready (Phonon-2 Local)"
    @Published public var lastTranscript: String = ""
    
    private var isMeetingTransitioning = false
    private var isShuttingDown = false
    private let dictationWork = DispatchGroup()

    public struct DictationSession: Sendable {
        public let id: UUID
        public let startTime: Date
        public let meetingSessionID: UUID?
        public let targetBundleID: String?
        public let targetAppName: String?
        public let targetPID: pid_t?

        public init(
            id: UUID = UUID(),
            startTime: Date = Date(),
            meetingSessionID: UUID? = nil,
            targetBundleID: String? = nil,
            targetAppName: String? = nil,
            targetPID: pid_t? = nil
        ) {
            self.id = id
            self.startTime = startTime
            self.meetingSessionID = meetingSessionID
            self.targetBundleID = targetBundleID
            self.targetAppName = targetAppName
            self.targetPID = targetPID
        }
    }

    private var activeDictationSession: DictationSession?

    // Live Progressive Dictation State
    private let dictationBuffer = AudioPCMBufferStore()
    private var partialTimer: Timer?
    private var durationTimer: Timer?
    private var dictationStartTime: Date?
    private var currentAudioLevel: Float = 0.2
    private var currentLivePartial: String = ""
    private var isTranscribingPartial: Bool = false
    /// Thread-safe gate read from the audio callback thread.
    private let dictationCaptureActive = CaptureFlag()
    private var micLevelToken: UUID?
    private var micBufferToken: UUID?
    private var audioErrorToken: UUID?
    /// Byte count at the last partial attempt, used to skip decodes when no
    /// new audio has arrived since the previous partial.
    private var lastPartialByteCount: Int = 0
    
    /// Live partials decode only the most recent 12 seconds of audio, so the
    /// cost of a partial stays constant instead of growing with the recording.
    private static let partialWindowBytes = 12 * AudioPCMBufferStore.bytesPerSecond
    /// 400 ms of audio is the minimum worth decoding.
    private static let minimumPartialBytes = 12_800
    /// Safety cap that finishes a run-away hands-free dictation.
    private static let maximumDictationSeconds: TimeInterval = 600
    
    private var captureMenuState: MenuBarManager.MenuState {
        if isMeetingFinalizing { return .meetingFinalizing }
        if isDictating { return .dictating }
        return isMeetingActive ? .meetingRecording : .idle
    }

    private var elapsedSeconds: Int {
        guard let start = dictationStartTime else { return 0 }
        return max(0, Int(Date().timeIntervalSince(start)))
    }
    
    public init() {
        let runner = PhononProcessRunner()
        let hub = AudioHub()
        let service = TranscriptionService(runner: runner)
        
        self.phononRunner = runner
        self.transcriptionService = service
        self.textInjector = TextInjector()
        self.hotkeyManager = HotkeyManager()
        self.floatingPill = FloatingPillPanel()
        self.audioHub = hub
        self.micEngine = hub.micEngine
        self.meetingCoordinator = MeetingCoordinator(
            dualChannel: DualChannelCoordinator(hub: hub),
            phononRunner: runner,
            transcriptionService: service
        )
        
        setupHotkeyWiring()
        setupMicWiring()
        setupPillWiring()
        setupAudioErrorWiring()

        if let err = DatabaseManager.shared.startupError {
            self.statusMessage = "Storage error: \(err.message)"
        } else if DatabaseManager.shared.isUsingFallbackStorage {
            self.statusMessage = "Warning: Storage running on fallback directory (\(DatabaseManager.shared.activeDatabasePath))"
        }

        DatabaseManager.shared.onError = { [weak self] message in
            Task { @MainActor in
                self?.statusMessage = "Storage error: \(message)"
            }
        }
    }
    
    private func setupAudioErrorWiring() {
        audioErrorToken = audioHub.addErrorObserver { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                self.statusMessage = "Audio error: \(error.localizedDescription)"
                if self.isDictating {
                    self.floatingPill.updateState(.error(message: error.localizedDescription))
                }
            }
        }
    }
    
    private func setupPillWiring() {
        floatingPill.onStopRequested = { [weak self] in
            Task { @MainActor in
                await self?.finishDictation()
            }
        }
        
        floatingPill.onCancelRequested = { [weak self] in
            Task { @MainActor in
                self?.cancelDictation()
            }
        }
    }
    
    private func setupHotkeyWiring() {
        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startDictation()
            }
        }
        
        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                await self?.finishDictation()
            }
        }
        
        hotkeyManager.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelDictation()
            }
        }
        
        hotkeyManager.onLockStateChanged = { [weak self] isLocked in
            Task { @MainActor in
                guard let self = self else { return }
                self.floatingPill.updateState(.listening(
                    audioLevel: self.currentAudioLevel,
                    livePartial: self.currentLivePartial,
                    isLocked: isLocked,
                    elapsedSeconds: self.elapsedSeconds
                ))
            }
        }
        
        hotkeyManager.onOpenMeetingStudio = { [weak self] in
            Task { @MainActor in
                self?.showMeetingStudio()
            }
        }
        
        hotkeyManager.onToggleDictation = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isDictating {
                    await self.finishDictation()
                } else {
                    self.startDictation()
                }
            }
        }
        
        hotkeyManager.onCopyLastDictation = { [weak self] in
            Task { @MainActor in
                guard let self = self, !self.lastTranscript.isEmpty else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(self.lastTranscript, forType: .string)
            }
        }
        
        hotkeyManager.onToggleMeetingRecording = { [weak self] in
            Task { @MainActor in
                await self?.toggleMeetingSession()
            }
        }
        
        hotkeyManager.startMonitoring()
    }
    
    private func setupMicWiring() {
        micLevelToken = audioHub.addMicLevelObserver { [weak self] level in
            Task { @MainActor in
                guard let self = self, self.dictationCaptureActive.isSet else { return }
                self.currentAudioLevel = level
                self.floatingPill.updateState(.listening(
                    audioLevel: level,
                    livePartial: self.currentLivePartial,
                    isLocked: self.hotkeyManager.isLocked,
                    elapsedSeconds: self.elapsedSeconds
                ))
            }
        }
        
        micBufferToken = audioHub.addMicBufferObserver { [weak self] pcmBuffer in
            guard let self = self, self.dictationCaptureActive.isSet else { return }
            guard let canonical = AudioBufferConverter.resampleTo16kMono(pcmBuffer),
                  let int16Data = AudioBufferConverter.int16PCM(from: canonical) else { return }
            self.dictationBuffer.append(int16Data)
        }
    }
    
    // MARK: - Mode 1: Quick Dictation with Live Streamed Partial Transcription
    
    public func toggleDictation() {
        if isDictating {
            Task {
                await finishDictation()
            }
        } else {
            startDictation()
        }
    }
    
    public func startDictation() {
        guard !isDictating, !isShuttingDown else { return }
        
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus == .denied || authStatus == .restricted {
            floatingPill.show(state: .error(message: "Microphone access denied in System Settings"))
            statusMessage = "Microphone access denied in System Settings"
            return
        }
        
        isDictating = true
        statusMessage = "Listening..."
        currentLivePartial = ""
        isTranscribingPartial = false
        lastPartialByteCount = 0
        MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
        
        dictationBuffer.removeAll()
        
        let now = Date()
        dictationStartTime = now
        let frontApp = NSWorkspace.shared.frontmostApplication
        activeDictationSession = DictationSession(
            id: UUID(),
            startTime: now,
            meetingSessionID: meetingCoordinator.recordingSessionID,
            targetBundleID: frontApp?.bundleIdentifier,
            targetAppName: frontApp?.localizedName,
            targetPID: frontApp?.processIdentifier
        )
        floatingPill.show(state: .listening(
            audioLevel: 0.2,
            livePartial: "",
            isLocked: hotkeyManager.isLocked,
            elapsedSeconds: 0
        ))
        
        dictationCaptureActive.set(true)
        do {
            try audioHub.retainMicrophone()
        } catch {
            dictationCaptureActive.set(false)
            isDictating = false
            floatingPill.updateState(.error(message: "Microphone unavailable: \(error.localizedDescription)"))
            statusMessage = "Microphone unavailable: \(error.localizedDescription)"
            MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
            return
        }
        
        // Start live progressive partial transcription loop (every 650ms)
        partialTimer?.invalidate()
        partialTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollLivePartialTranscription()
            }
        }
        
        // Start 1.0s elapsed timer
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isDictating else { return }
                if let start = self.dictationStartTime,
                   Date().timeIntervalSince(start) >= Self.maximumDictationSeconds {
                    await self.finishDictation()
                    return
                }
                self.floatingPill.updateState(.listening(
                    audioLevel: self.currentAudioLevel,
                    livePartial: self.currentLivePartial,
                    isLocked: self.hotkeyManager.isLocked,
                    elapsedSeconds: self.elapsedSeconds
                ))
            }
        }
    }
    
    private func pollLivePartialTranscription() async {
        guard isDictating, !isTranscribingPartial else { return }
        
        let snapshot = dictationBuffer.snapshot(maxBytes: Self.partialWindowBytes)
        
        // Minimum 400ms of audio before first partial decode
        guard snapshot.pcm.count >= Self.minimumPartialBytes else { return }
        // Nothing new since the last attempt: decoding again would produce the
        // same text and burn a full inference per timer tick.
        guard snapshot.totalByteCount != lastPartialByteCount else { return }
        lastPartialByteCount = snapshot.totalByteCount
        
        isTranscribingPartial = true
        dictationWork.enter()
        defer {
            isTranscribingPartial = false
            dictationWork.leave()
        }
        
        do {
            let partialText = try await transcribePCM(snapshot.pcm)
            let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, self.isDictating else { return }
            
            let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
            let formatted = TextInjector.formatSentencePunctuationAndCapitalization(sanitized)
            // A truncated window starts mid-sentence, so mark it as such.
            let display = snapshot.isTruncated ? "… " + formatted : formatted
            self.currentLivePartial = display
            self.floatingPill.updateState(.listening(
                audioLevel: self.currentAudioLevel,
                livePartial: display,
                isLocked: self.hotkeyManager.isLocked,
                elapsedSeconds: self.elapsedSeconds
            ))
        } catch {
            // A failed partial is not fatal: the next tick retries once new
            // audio arrives. The final transcription still uses full audio.
        }
    }
    
    /// Transcribe raw PCM via the coordinated TranscriptionService.
    private func transcribePCM(_ pcmData: Data) async throws -> String {
        return try await transcriptionService.transcribe(pcmData: pcmData)
    }
    
    public func finishDictation() async {
        guard isDictating, !isShuttingDown else { return }
        guard let session = activeDictationSession else { return }
        activeDictationSession = nil
        dictationWork.enter()
        defer { dictationWork.leave() }
        isDictating = false
        dictationCaptureActive.set(false)
        partialTimer?.invalidate()
        partialTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        dictationStartTime = nil
        isTranscribingPartial = false
        
        audioHub.releaseMicrophone()
        floatingPill.updateState(.transcribing)
        
        hotkeyManager.unlock()
        
        let captured = dictationBuffer.takeAll()
        let capturedData = captured.pcm
        let fallbackPartial = currentLivePartial
        let fallbackTruncated = (capturedData.count > Self.partialWindowBytes)
        currentLivePartial = ""
        lastPartialByteCount = 0
        
        guard capturedData.count >= 3200 else { // Minimum 100ms
            floatingPill.hide()
            statusMessage = "Echo Ready (Phonon-2 Local)"
            MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
            return
        }
        
        do {
            let transcript = try await transcribePCM(capturedData)
            
            var trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            var wasRecoveredFromPartial = false

            if trimmed.isEmpty && !fallbackPartial.isEmpty {
                let cleaned = fallbackPartial
                    .replacingOccurrences(of: "… ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    trimmed = fallbackTruncated ? "[Partial] " + cleaned : cleaned
                    wasRecoveredFromPartial = true
                }
            }
            
            if !trimmed.isEmpty {
                // Apply custom vocabulary & word memory replacements
                let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
                self.lastTranscript = sanitized
                
                // 1. Separate quick dictations from meeting sessions:
                // Only append to meeting timeline if a meeting is actively in progress;
                // otherwise persist to SQLite as standalone dictation.
                let rawDurationSec = Double(capturedData.count) / Double(AudioPCMBufferStore.bytesPerSecond)
                let durationSec = wasRecoveredFromPartial && fallbackTruncated ? min(rawDurationSec, 12.0) : rawDurationSec
                
                if !isShuttingDown, let meetingSessionID = session.meetingSessionID, meetingSessionID == meetingCoordinator.recordingSessionID {
                    await meetingCoordinator.appendDictation(text: sanitized, duration: durationSec)
                } else {
                    let segment = TranscriptSegment(
                        speaker: .you,
                        timestamp: session.startTime,
                        text: sanitized,
                        durationSeconds: durationSec
                    )
                    await DatabaseManager.shared.saveUtteranceAsync(segment, sessionId: nil, isDictation: true)
                }
                
                guard !isShuttingDown else { return }
                
                // 2. Focus validation: Ensure active application hasn't changed during recognition
                let currentFront = NSWorkspace.shared.frontmostApplication
                let focusChanged = (session.targetBundleID != nil && currentFront?.bundleIdentifier != session.targetBundleID)

                if focusChanged {
                    // Safe fallback: Do not inject private text into the wrong newly-focused app!
                    _ = textInjector.writeToClipboard(sanitized)
                    let newAppName = currentFront?.localizedName ?? "another application"
                    floatingPill.updateState(.success(preview: "✓ Focus Changed: Copied to Clipboard"))
                    statusMessage = "Focus changed to \(newAppName): Copied to clipboard"
                } else {
                    let injectionResult = await textInjector.inject(text: sanitized)
                    
                    let feedbackBadge: String
                    switch injectionResult.method {
                    case .accessibilityDirect:
                        feedbackBadge = "✓ Injected at cursor"
                    case .directTyping:
                        feedbackBadge = "✓ Typed into field"
                    case .syntheticPaste:
                        feedbackBadge = "✓ Auto-Pasted"
                    case .clipboardOnly:
                        feedbackBadge = "✓ Copied to Clipboard"
                    }
                    
                    if wasRecoveredFromPartial {
                        floatingPill.updateState(.success(preview: "✓ Recovered Partial: \"\(trimmed.prefix(25))...\""))
                        statusMessage = "Recovered partial: \"\(trimmed.prefix(30))...\""
                    } else {
                        floatingPill.updateState(.success(preview: "\(feedbackBadge): \"\(trimmed.prefix(25))...\""))
                        statusMessage = "Injected: \"\(trimmed.prefix(30))...\""
                    }
                }
            } else {
                floatingPill.hide()
                statusMessage = "Echo Ready (Phonon-2 Local)"
            }
        } catch {
            floatingPill.updateState(.error(message: error.localizedDescription))
            statusMessage = "Transcription failed"
        }
        
        MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
    }
    
    public func cancelDictation() {
        guard isDictating else { return }
        activeDictationSession = nil
        isDictating = false
        dictationCaptureActive.set(false)
        partialTimer?.invalidate()
        partialTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        dictationStartTime = nil
        currentLivePartial = ""
        isTranscribingPartial = false
        lastPartialByteCount = 0
        
        audioHub.releaseMicrophone()
        hotkeyManager.unlock()
        
        dictationBuffer.removeAll()
        lastPartialByteCount = 0
        currentLivePartial = ""
        
        floatingPill.hide()
        statusMessage = "Dictation Cancelled"
        MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
    }
    
    // MARK: - Mode 2: Meeting Studio (Meetily Style)
    
    public func showMeetingStudio() {
        MeetingStudioWindow.shared.showWindow()
    }
    
    public func toggleMeetingRecording() {
        Task {
            await toggleMeetingSession()
        }
    }
    
    public func toggleMeetingSession() async {
        guard !isMeetingTransitioning, !isShuttingDown else { return }
        isMeetingTransitioning = true
        defer { isMeetingTransitioning = false }

        if isMeetingActive {
            isMeetingFinalizing = true
            statusMessage = "Finalizing meeting…"
            MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
            let session = await meetingCoordinator.stopSession()
            isMeetingActive = false
            isMeetingFinalizing = false
            guard !isShuttingDown else { return }
            statusMessage = "Meeting Ended (\(session?.segments.count ?? 0) utterances)"
            MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
        } else {
            do {
                try await meetingCoordinator.startSession()
                guard !isShuttingDown else { return }
                isMeetingActive = true
                statusMessage = "Recording Meeting..."
                MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
            } catch {
                guard !isShuttingDown else { return }
                statusMessage = "Failed to start meeting: \(error.localizedDescription)"
                MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
            }
        }
    }

    public func copyLastTranscriptToClipboard() {
        guard !lastTranscript.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastTranscript, forType: .string)
        statusMessage = "Copied last dictation to clipboard"
    }
    
    /// Delete one saved session; the database cascades its utterances.
    public func deleteSession(id: UUID) async {
        let deleted = await meetingCoordinator.deleteSession(id: id)
        statusMessage = deleted ? "Deleted meeting session" : "Stop the meeting before deleting it"
    }

    /// Remove empty sessions (retention) and compact the WAL.
    public func deleteEmptySessions() async {
        let removed = await meetingCoordinator.deleteEmptySessions()
        statusMessage = removed == 0
            ? "No empty sessions to remove"
            : "Removed \(removed) empty session\(removed == 1 ? "" : "s")"
    }

    /// Standalone dictation retention: remove all utterances not tied to a meeting session.
    @discardableResult
    public func deleteStandaloneDictations() async -> Int {
        let removed = await DatabaseManager.shared.deleteStandaloneDictationsAsync()
        statusMessage = removed == 0
            ? "No standalone dictations to remove"
            : "Removed \(removed) standalone dictation snippet\(removed == 1 ? "" : "s")"
        return removed
    }

    public func exportLastMeetingMarkdown() {
        guard !isMeetingFinalizing else { return }
        guard let session = meetingCoordinator.activeSession, !session.segments.isEmpty else {
            statusMessage = "No active meeting session to export"
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "No Active Meeting"
            alert.informativeText = "There is no recorded active meeting session to export. To export previous meetings, use the Meeting History menu."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        _ = exportSessionMarkdown(session)
    }
    
    @discardableResult
    public func exportSession(id: UUID) -> URL? {
        guard !isMeetingFinalizing || meetingCoordinator.activeSession?.id != id else { return nil }
        guard let session = DatabaseManager.shared.fetchSession(id: id) else {
            statusMessage = "Session not found"
            return nil
        }
        let segments = DatabaseManager.shared.fetchUtterances(sessionId: id)
        var fullSession = session
        fullSession.segments = segments
        return exportSessionMarkdown(fullSession)
    }
    
    @discardableResult
    public func exportSessionMarkdown(_ session: MeetingSession) -> URL? {
        guard !isMeetingFinalizing || meetingCoordinator.activeSession?.id != session.id else { return nil }
        let md = session.exportMarkdown()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(md, forType: .string)
        
        do {
            let directory = try EchoSettings.ensureExportDirectory()
            let timestamp = ISO8601DateFormatter().string(from: session.startTime).replacingOccurrences(of: ":", with: "-")
            let filename = "echo_meeting_\(timestamp).md"
            let url = directory.appendingPathComponent(filename)
            try md.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported to \(url.lastPathComponent)"
            print("Meeting exported to clipboard and \(url.path)")
            return url
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            presentExportError(error)
            return nil
        }
    }
    
    private func presentExportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't export meeting notes"
        alert.informativeText = """
        \(error.localizedDescription)
        
        The Markdown was copied to the clipboard. To choose a writable folder, run:
        defaults write \(Bundle.main.bundleIdentifier ?? "com.ragavij.echo") echo.exportDirectory /path/to/folder
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Finish capture and persistence before the termination delegate lets AppKit exit.
    public func shutdownGracefully() async {
        isShuttingDown = true
        hotkeyManager.stopMonitoring()
        cancelDictation()

        isMeetingFinalizing = isMeetingActive || isMeetingTransitioning
        if isMeetingFinalizing {
            statusMessage = "Finalizing meeting…"
            MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
        }
        _ = await meetingCoordinator.stopSession()
        isMeetingActive = false
        isMeetingFinalizing = false

        await audioHub.stopAll()
        await withCheckedContinuation { continuation in
            dictationWork.notify(queue: .global()) { continuation.resume() }
        }
        DatabaseManager.shared.checkpointWAL()
        AudioTempDirectory.sweepOrphanedAudioFiles()
    }

    public func openAccessibilitySettings() {
        // Trigger system dialog once when user explicitly requests it
        _ = TextInjector.isAccessibilityTrusted(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Small thread-safe latch for state read by the CoreAudio callback thread.
private final class CaptureFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    
    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    
    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
