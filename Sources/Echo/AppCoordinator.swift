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
    var isBusyForUpdate: Bool {
        isDictating || isMeetingActive || isMeetingTransitioning || isMeetingFinalizing ||
        meetingCoordinator.unsavedTranscriptCount > 0 || dictationWork.wait(timeout: .now()) == .timedOut
    }
    private var dictationRetentionTimer: Timer?

    private let dictation = DictationLifecycle()
    private var partialTimer: Timer?
    private var durationTimer: Timer?
    private var micLevelToken: UUID?
    private var micBufferToken: UUID?
    private var audioErrorToken: UUID?
    private var lastDictationRecoveryText: String?

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
        setupPillWiring()
        setupAudioErrorWiring()

        if let err = DatabaseManager.shared.startupError {
            self.statusMessage = "Storage error: \(err.message)"
        } else if DatabaseManager.shared.isUsingTemporaryStorage {
            self.statusMessage = "Temporary storage. Quit Echo and any changes made this launch will be lost."
        } else if DatabaseManager.shared.isUsingFallbackStorage {
            self.statusMessage = "Warning: Storage running on fallback directory (\(DatabaseManager.shared.activeDatabasePath))"
        }

        DatabaseManager.shared.onError = { [weak self] message in
            Task { @MainActor in
                self?.statusMessage = "Storage error: \(message)"
            }
        }
        Task { [weak self] in await self?.pruneStandaloneDictations() }
        dictationRetentionTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pruneStandaloneDictations() }
        }
    }
    
    private func setupAudioErrorWiring() {
        audioErrorToken = audioHub.addErrorObserver { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                self.statusMessage = "Audio error: \(error.localizedDescription)"
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
                guard let self, let recording = self.dictation.active else { return }
                self.updateListeningPill(for: recording, isLocked: isLocked)
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
                self?.copyLastTranscriptToClipboard()
            }
        }
        
        hotkeyManager.onToggleMeetingRecording = { [weak self] in
            Task { @MainActor in
                await self?.toggleMeetingSession()
            }
        }
        
        hotkeyManager.startMonitoring()
    }
    
    private func setupMicWiring(for recording: DictationRecording) {
        let recordingID = recording.id
        let audio = recording.audio
        micLevelToken = audioHub.addMicLevelObserver { [weak self] level in
            Task { @MainActor in
                guard let self, let active = self.dictation.active, active.id == recordingID else { return }
                active.audioLevel = level
                self.updateListeningPill(for: active)
            }
        }

        micBufferToken = audioHub.addMicBufferObserver { pcmBuffer in
            guard let canonical = AudioBufferConverter.resampleTo16kMono(pcmBuffer),
                  let int16Data = AudioBufferConverter.int16PCM(from: canonical) else { return }
            audio.append(int16Data)
        }
    }

    private func updateListeningPill(for recording: DictationRecording, isLocked: Bool? = nil) {
        floatingPill.updateState(.listening(
            audioLevel: recording.audioLevel,
            livePartial: recording.preview?.displayText ?? "",
            isLocked: isLocked ?? hotkeyManager.isLocked,
            elapsedSeconds: recording.elapsedSeconds
        ))
    }

    // MARK: - Mode 1: Quick Dictation with Live Streamed Partial Transcription

    public func toggleDictation() {
        if isDictating {
            Task { await finishDictation() }
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

        let recording = dictation.start(
            meetingSessionID: meetingCoordinator.recordingSessionID,
            target: FocusedDictationField.current()
        )
        isDictating = true
        statusMessage = "Listening..."
        MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)

        floatingPill.show(state: .listening(
            audioLevel: recording.audioLevel,
            livePartial: "",
            isLocked: hotkeyManager.isLocked,
            elapsedSeconds: 0
        ))

        setupMicWiring(for: recording)
        do {
            try audioHub.retainMicrophone()
        } catch {
            _ = stopDictationCapture(releaseMicrophone: false)
            let message = "Microphone unavailable: \(error.localizedDescription)"
            floatingPill.updateState(.error(message: message))
            statusMessage = message
            return
        }

        let recordingID = recording.id
        partialTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollLivePartialTranscription(for: recordingID)
            }
        }

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let active = self.dictation.active, active.id == recordingID else { return }
                if Date().timeIntervalSince(active.startTime) >= Self.maximumDictationSeconds {
                    await self.finishDictation()
                    return
                }
                self.updateListeningPill(for: active)
            }
        }
    }

    private func pollLivePartialTranscription(for id: UUID) async {
        guard let recording = dictation.active, recording.id == id, !recording.isDecodingPreview else { return }

        let snapshot = recording.audio.snapshot(maxBytes: Self.partialWindowBytes)
        guard snapshot.byteCount >= Self.minimumPartialBytes,
              snapshot.totalByteCount != recording.lastPreviewByteCount else { return }
        recording.lastPreviewByteCount = snapshot.totalByteCount
        recording.isDecodingPreview = true
        dictationWork.enter()
        defer {
            recording.isDecodingPreview = false
            dictationWork.leave()
        }

        do {
            let text = try await transcriptionService.transcribe(pcmData: snapshot.pcm)
            guard dictation.active?.id == id else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
            let formatted = TextInjector.formatSentencePunctuationAndCapitalization(sanitized)
            let preview = DictationPreview(text: formatted, snapshot: snapshot)
            guard dictation.acceptPreview(preview, for: id) else { return }
            updateListeningPill(for: recording)
        } catch {
            // Another preview can be attempted once new audio arrives.
        }
    }

    public func finishDictation() async {
        guard !isShuttingDown, let recording = stopDictationCapture() else { return }
        dictationWork.enter()
        defer { dictationWork.leave() }

        let captured = recording.audio.takeAll()
        guard captured.byteCount >= 3200 else {
            floatingPill.hide()
            statusMessage = "Echo Ready (Phonon-2 Local)"
            return
        }
        floatingPill.updateState(.transcribing)

        let finalText: String
        let finalError: Error?
        do {
            finalText = try await transcriptionService.transcribe(pcmData: captured.pcm)
            finalError = nil
        } catch {
            finalText = ""
            finalError = error
        }

        guard let transcript = DictationTranscript(
            finalText: finalText,
            totalBytes: captured.byteCount,
            preview: recording.preview
        ) else {
            guard dictation.ownsDelivery(recording.id), !isShuttingDown else { return }
            if let finalError {
                floatingPill.updateState(.error(message: finalError.localizedDescription))
                statusMessage = "Transcription failed: \(finalError.localizedDescription)"
            } else {
                floatingPill.hide()
                statusMessage = "Echo Ready (Phonon-2 Local)"
            }
            return
        }

        let sanitized = transcript.recoveredFromPreview ? transcript.text : WordMemoryEngine.shared.sanitize(transcript.text)
        let segment = TranscriptSegment(
            speaker: .you,
            timestamp: recording.startTime.addingTimeInterval(transcript.startOffset),
            text: sanitized,
            durationSeconds: transcript.duration
        )
        await meetingCoordinator.saveDictation(segment, meetingSessionID: recording.meetingSessionID)

        guard !isShuttingDown, dictation.ownsDelivery(recording.id) else { return }
        lastTranscript = sanitized
        lastDictationRecoveryText = nil

        if transcript.recoveredFromPreview {
            let message = "Partial available. Copy with ⇧⌘C"
            statusMessage = finalError.map { "Transcription failed: \($0.localizedDescription). \(message)" } ?? message
            floatingPill.updateState(.notice(message: message))
            return
        }

        let delivery = await textInjector.injectDictation(
            text: sanitized,
            target: recording.target,
            stillOwnsDelivery: { !self.isShuttingDown && self.dictation.ownsDelivery(recording.id) }
        )
        guard !isShuttingDown, dictation.ownsDelivery(recording.id) else { return }
        lastDictationRecoveryText = delivery.remainingText
        showDictationDelivery(delivery)
    }

    private func showDictationDelivery(_ result: InjectionResult) {
        let feedback: String
        switch result.method {
        case .accessibilityDirect:
            feedback = "Inserted at cursor"
        case .directTyping:
            feedback = "Typing sent. Copy with ⇧⌘C"
        case .syntheticPaste:
            feedback = "Paste requested. Copy with ⇧⌘C"
        case .partialTyping:
            feedback = result.clipboardReady ? "Typing interrupted. Remainder copied" : "Typing interrupted. Copy remainder with ⇧⌘C"
        case .clipboardOnly:
            let recovery = result.clipboardReady ? "Copied to clipboard" : "Copy with ⇧⌘C"
            feedback = result.focusChanged ? "Field changed or unavailable. \(recovery)" : recovery
        }
        statusMessage = feedback
        if result.insertionConfirmed || (result.method == .clipboardOnly && result.clipboardReady) {
            floatingPill.updateState(.success(preview: feedback))
        } else {
            floatingPill.updateState(.notice(message: feedback))
        }
    }

    private func stopDictationCapture(releaseMicrophone: Bool = true) -> DictationRecording? {
        guard let recording = dictation.stop() else { return nil }
        isDictating = false
        partialTimer?.invalidate()
        partialTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        if let token = micLevelToken { audioHub.removeObserver(token) }
        if let token = micBufferToken { audioHub.removeObserver(token) }
        micLevelToken = nil
        micBufferToken = nil
        if releaseMicrophone { audioHub.releaseMicrophone() }
        hotkeyManager.unlock()
        MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
        return recording
    }

    public func cancelDictation() {
        guard stopDictationCapture() != nil else { return }
        floatingPill.hide()
        statusMessage = "Dictation Cancelled"
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
        guard textInjector.writeToClipboard(lastDictationRecoveryText ?? lastTranscript) != nil else {
            statusMessage = "Could not write to the clipboard"
            return
        }
        statusMessage = lastDictationRecoveryText == nil ? "Copied last dictation to clipboard" : "Copied remainder to clipboard"
    }
    
    /// Delete one saved session; the database cascades its utterances.
    public func deleteSession(id: UUID) async {
        switch await meetingCoordinator.deleteSession(id: id) {
        case .deleted:
            statusMessage = "Deleted meeting session"
        case .notFound:
            statusMessage = "That meeting session no longer exists in storage"
        case .busy:
            statusMessage = "Wait for the current storage operation before deleting this meeting"
        case .recording:
            statusMessage = "Stop the meeting before deleting it"
        case .failed(let error):
            showStorageError("Couldn’t delete the meeting", details: error)
        }
    }

    /// Remove empty sessions and compact the WAL.
    public func deleteEmptySessions() async {
        do {
            let removed = try await meetingCoordinator.deleteEmptySessions()
            statusMessage = removed == 0
                ? "No empty sessions to remove"
                : "Removed \(removed) empty session\(removed == 1 ? "" : "s")"
        } catch {
            showStorageError("Couldn’t delete empty meetings", details: error.localizedDescription)
        }
    }

    /// Clear stored dictations outside of meetings.
    public func deleteStandaloneDictations() async {
        do {
            let removed = try await meetingCoordinator.clearStandaloneDictationHistory()
            statusMessage = removed == 0
                ? "No standalone dictations in storage"
                : "Removed \(removed) standalone dictation snippet\(removed == 1 ? "" : "s")"
        } catch {
            showStorageError("Couldn’t clear dictation history", details: error.localizedDescription)
        }
    }

    func setDictationRetention(_ retention: EchoSettings.DictationRetention) async {
        EchoSettings.dictationRetention = retention
        await pruneStandaloneDictations(showError: true)
    }

    private func pruneStandaloneDictations(showError: Bool = false) async {
        do {
            try await meetingCoordinator.pruneStandaloneDictations(EchoSettings.dictationRetention)
        } catch {
            if showError {
                showStorageError("Couldn’t apply dictation history retention", details: error.localizedDescription)
            } else {
                statusMessage = "Dictation history cleanup failed. \(error.localizedDescription)"
            }
        }
    }

    private func showStorageError(_ message: String, details: String) {
        statusMessage = "\(message). \(details)"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
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
        Task { @MainActor in
            await exportSessionMarkdown(session)
        }
    }
    
    @discardableResult
    public func exportSession(id: UUID) async -> URL? {
        guard !isMeetingFinalizing || meetingCoordinator.activeSession?.id != id else { return nil }
        guard let session = await DatabaseManager.shared.fetchSessionAsync(id: id) else {
            statusMessage = "Session not found"
            return nil
        }
        let segments = await DatabaseManager.shared.fetchUtterancesAsync(sessionId: id)
        var fullSession = session
        fullSession.segments = segments
        return await exportSessionMarkdown(fullSession)
    }
    
    func markdown(for session: MeetingSession, includeTranscript: Bool = true) async -> String {
        await session.markdown(using: .shared, includeTranscript: includeTranscript)
    }

    @discardableResult
    public func exportSessionMarkdown(_ session: MeetingSession) async -> URL? {
        guard !isMeetingFinalizing || meetingCoordinator.activeSession?.id != session.id else { return nil }
        let md = await markdown(for: session)
        
        do {
            let directory = try EchoSettings.ensureExportDirectory()
            let timestamp = ISO8601DateFormatter().string(from: session.startTime).replacingOccurrences(of: ":", with: "-")
            let sessionSlug = session.id.uuidString.lowercased()
            let filename = "echo_meeting_\(timestamp)_\(sessionSlug).md"
            let url = directory.appendingPathComponent(filename)
            try await Task.detached {
                try md.write(to: url, atomically: true, encoding: .utf8)
            }.value
            statusMessage = "Exported to \(url.lastPathComponent)"
            print("Meeting exported to \(url.path)")
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
        
        To choose a writable folder, run:
        defaults write \(Bundle.main.bundleIdentifier ?? "com.ragavij.echo") echo.exportDirectory /path/to/folder
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Quiesce capture and wait for pending writes before deciding whether to quit.
    public func prepareToQuit() async -> Bool {
        if !isShuttingDown {
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
        }
        await meetingCoordinator.waitForTranscriptRetry()
        return meetingCoordinator.unsavedTranscriptCount == 0
    }

    public func cancelPendingQuit() {
        isShuttingDown = false
        hotkeyManager.startMonitoring()
        MenuBarManager.shared.updateMenuBarIcon(state: captureMenuState)
    }

    /// Finish teardown once the termination delegate is ready to exit.
    public func shutdownGracefully() async {
        _ = await prepareToQuit()
        dictationRetentionTimer?.invalidate()
        DatabaseManager.shared.checkpointWAL()
        AudioTempDirectory.cleanupCurrentProcess()
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
