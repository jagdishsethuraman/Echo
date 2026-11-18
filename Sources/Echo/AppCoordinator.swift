import AppKit
import Foundation

@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()
    
    // Core Engine Subsystems
    public let phononRunner: PhononProcessRunner
    public let textInjector: TextInjector
    public let hotkeyManager: HotkeyManager
    public let floatingPill: FloatingPillPanel
    public let audioHub: AudioHub
    public let micEngine: AudioEngineManager
    public let meetingCoordinator: MeetingCoordinator
    
    // State Tracking
    @Published public var isDictating: Bool = false
    @Published public var isMeetingActive: Bool = false
    @Published public var statusMessage: String = "Echo Ready (Phonon-2 Local)"
    @Published public var lastTranscript: String = ""
    
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
    
    private var elapsedSeconds: Int {
        guard let start = dictationStartTime else { return 0 }
        return max(0, Int(Date().timeIntervalSince(start)))
    }
    
    public init() {
        let runner = PhononProcessRunner()
        let hub = AudioHub()
        
        self.phononRunner = runner
        self.textInjector = TextInjector()
        self.hotkeyManager = HotkeyManager()
        self.floatingPill = FloatingPillPanel()
        self.audioHub = hub
        self.micEngine = hub.micEngine
        self.meetingCoordinator = MeetingCoordinator(
            dualChannel: DualChannelCoordinator(hub: hub),
            phononRunner: runner
        )
        
        setupHotkeyWiring()
        setupMicWiring()
        setupPillWiring()
    }
    
    private func setupPillWiring() {
        floatingPill.onStopRequested = { [weak self] in
            Task { @MainActor in
                await self?.finishDictation()
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
        guard !isDictating else { return }
        isDictating = true
        statusMessage = "Listening..."
        currentLivePartial = ""
        isTranscribingPartial = false
        lastPartialByteCount = 0
        MenuBarManager.shared.updateMenuBarIcon(state: .dictating)
        
        dictationBuffer.removeAll()
        
        dictationStartTime = Date()
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
            MenuBarManager.shared.updateMenuBarIcon(state: isMeetingActive ? .meetingRecording : .idle)
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
        defer { isTranscribingPartial = false }
        
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
    
    /// Write raw PCM to a temporary WAV file, transcribe it, and clean up.
    private func transcribePCM(_ pcmData: Data) async throws -> String {
        let wavData = AudioBufferConverter.packageWAV(pcmData: pcmData, sampleRate: 16000, channels: 1)
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo_audio_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try wavData.write(to: tempFile)
        let (transcript, _) = try await phononRunner.transcribe(fileURL: tempFile)
        return transcript
    }
    
    public func finishDictation() async {
        guard isDictating else { return }
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
        lastPartialByteCount = 0
        
        guard capturedData.count >= 3200 else { // Minimum 100ms
            floatingPill.hide()
            statusMessage = "Echo Ready (Phonon-2 Local)"
            MenuBarManager.shared.updateMenuBarIcon(state: isMeetingActive ? .meetingRecording : .idle)
            return
        }
        
        do {
            let transcript = try await transcribePCM(capturedData)
            
            var trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !currentLivePartial.isEmpty {
                // The live partial is only a window of the recording.
                trimmed = currentLivePartial
                    .replacingOccurrences(of: "… ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if !trimmed.isEmpty {
                // Apply custom vocabulary & word memory replacements
                let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
                self.lastTranscript = sanitized
                
                // 1. Separate quick dictations from meeting sessions:
                // Only append to meeting timeline if a meeting is actively in progress;
                // otherwise persist to SQLite as standalone dictation.
                let durationSec = Double(capturedData.count) / Double(AudioPCMBufferStore.bytesPerSecond)
                if isMeetingActive {
                    meetingCoordinator.appendDictation(text: sanitized, duration: durationSec)
                } else {
                    let segment = TranscriptSegment(
                        speaker: .you,
                        timestamp: Date(),
                        text: sanitized,
                        durationSeconds: durationSec
                    )
                    DatabaseManager.shared.saveUtterance(segment, sessionId: nil, isDictation: true)
                }
                
                // 2. Direct injection into active text cursor + clipboard placement
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
                
                floatingPill.updateState(.success(preview: "\(feedbackBadge): \"\(trimmed.prefix(25))...\""))
                statusMessage = "Injected: \"\(trimmed.prefix(30))...\""
            } else {
                floatingPill.hide()
                statusMessage = "Echo Ready (Phonon-2 Local)"
            }
        } catch {
            floatingPill.updateState(.error(message: error.localizedDescription))
            statusMessage = "Transcription failed"
        }
        
        MenuBarManager.shared.updateMenuBarIcon(state: isMeetingActive ? .meetingRecording : .idle)
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
        if isMeetingActive {
            let session = await meetingCoordinator.stopSession()
            isMeetingActive = false
            statusMessage = "Meeting Ended (\(session?.segments.count ?? 0) utterances)"
            MenuBarManager.shared.updateMenuBarIcon(state: .idle)
        } else {
            do {
                try await meetingCoordinator.startSession()
                isMeetingActive = true
                statusMessage = "Recording Meeting..."
                MenuBarManager.shared.updateMenuBarIcon(state: .meetingRecording)
            } catch {
                statusMessage = "Failed to start meeting: \(error.localizedDescription)"
                MenuBarManager.shared.updateMenuBarIcon(state: .idle)
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
    
    public func exportLastMeetingMarkdown() {
        let session = meetingCoordinator.activeSession ?? MeetingSession(title: "Echo Meeting Session")
        let md = session.exportMarkdown()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(md, forType: .string)
        
        do {
            let directory = try EchoSettings.ensureExportDirectory()
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let filename = "echo_meeting_\(timestamp).md"
            let url = directory.appendingPathComponent(filename)
            try md.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported to \(url.path)"
            print("Meeting exported to clipboard and \(url.path)")
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            presentExportError(error)
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
