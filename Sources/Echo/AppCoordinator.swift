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
    public let micEngine: AudioEngineManager
    public let meetingCoordinator: MeetingCoordinator
    
    // State Tracking
    @Published public var isDictating: Bool = false
    @Published public var isMeetingActive: Bool = false
    @Published public var statusMessage: String = "Echo Ready (Phonon-2 Local)"
    @Published public var lastTranscript: String = ""
    
    // Live Progressive Dictation State
    private var dictationPCMBuffer = Data()
    private let bufferQueue = DispatchQueue(label: "com.echo.dictation.buffer")
    private var partialTimer: Timer?
    private var currentAudioLevel: Float = 0.2
    private var currentLivePartial: String = ""
    private var isTranscribingPartial: Bool = false
    
    public init() {
        self.phononRunner = PhononProcessRunner()
        self.textInjector = TextInjector()
        self.hotkeyManager = HotkeyManager()
        self.floatingPill = FloatingPillPanel()
        self.micEngine = AudioEngineManager()
        self.meetingCoordinator = MeetingCoordinator(phononRunner: phononRunner)
        
        setupHotkeyWiring()
        setupMicWiring()
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
                    isLocked: isLocked
                ))
            }
        }
        
        hotkeyManager.startMonitoring()
    }
    
    private func setupMicWiring() {
        micEngine.onVolumeLevel = { [weak self] level in
            Task { @MainActor in
                guard let self = self, self.isDictating else { return }
                self.currentAudioLevel = level
                self.floatingPill.updateState(.listening(
                    audioLevel: level,
                    livePartial: self.currentLivePartial,
                    isLocked: self.hotkeyManager.isLocked
                ))
            }
        }
        
        micEngine.onAudioBuffer = { [weak self] pcmBuffer in
            guard let self = self, self.isDictating else { return }
            guard let channelData = pcmBuffer.floatChannelData?[0] else { return }
            let frameCount = Int(pcmBuffer.frameLength)
            
            var int16Data = Data(count: frameCount * 2)
            int16Data.withUnsafeMutableBytes { (rawBuffer: UnsafeMutableRawBufferPointer) in
                let ptr = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<frameCount {
                    let floatVal = max(-1.0, min(1.0, channelData[i]))
                    ptr[i] = Int16(floatVal * 32767.0)
                }
            }
            
            bufferQueue.sync {
                self.dictationPCMBuffer.append(int16Data)
            }
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
        MenuBarManager.shared.updateMenuBarIcon(state: .dictating)
        
        bufferQueue.sync {
            dictationPCMBuffer.removeAll()
        }
        
        floatingPill.show(state: .listening(audioLevel: 0.2, livePartial: "", isLocked: hotkeyManager.isLocked))
        try? micEngine.startCapture()
        
        // Start live progressive partial transcription loop (every 650ms)
        partialTimer?.invalidate()
        partialTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollLivePartialTranscription()
            }
        }
    }
    
    private func pollLivePartialTranscription() async {
        guard isDictating, !isTranscribingPartial else { return }
        
        let snapshotData: Data = bufferQueue.sync {
            return dictationPCMBuffer
        }
        
        // Minimum 400ms of audio before first partial decode
        guard snapshotData.count >= 12800 else { return }
        
        isTranscribingPartial = true
        let wavData = AudioBufferConverter.packageWAV(pcmData: snapshotData, sampleRate: 16000, channels: 1)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("echo_partial_\(UUID().uuidString).wav")
        
        do {
            try wavData.write(to: tempFile)
            let (partialText, _) = try await phononRunner.transcribe(fileURL: tempFile)
            try? FileManager.default.removeItem(at: tempFile)
            
            let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && self.isDictating {
                let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
                let formatted = TextInjector.formatSentencePunctuationAndCapitalization(sanitized)
                self.currentLivePartial = formatted
                self.floatingPill.updateState(.listening(
                    audioLevel: self.currentAudioLevel,
                    livePartial: formatted,
                    isLocked: self.hotkeyManager.isLocked
                ))
            }
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        self.isTranscribingPartial = false
    }
    
    public func finishDictation() async {
        guard isDictating else { return }
        isDictating = false
        partialTimer?.invalidate()
        partialTimer = nil
        isTranscribingPartial = false
        
        micEngine.stopCapture()
        floatingPill.updateState(.transcribing)
        
        hotkeyManager.unlock()
        
        let capturedData: Data = bufferQueue.sync {
            let data = dictationPCMBuffer
            dictationPCMBuffer.removeAll()
            return data
        }
        
        guard capturedData.count >= 3200 else { // Minimum 100ms
            floatingPill.hide()
            statusMessage = "Echo Ready (Phonon-2 Local)"
            MenuBarManager.shared.updateMenuBarIcon(state: isMeetingActive ? .meetingRecording : .idle)
            return
        }
        
        let wavData = AudioBufferConverter.packageWAV(pcmData: capturedData, sampleRate: 16000, channels: 1)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("echo_dictate_\(UUID().uuidString).wav")
        
        do {
            try wavData.write(to: tempFile)
            let (transcript, _) = try await phononRunner.transcribe(fileURL: tempFile)
            try? FileManager.default.removeItem(at: tempFile)
            
            var trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !currentLivePartial.isEmpty {
                trimmed = currentLivePartial
            }
            
            if !trimmed.isEmpty {
                // Apply custom vocabulary & word memory replacements
                let sanitized = WordMemoryEngine.shared.sanitize(trimmed)
                self.lastTranscript = sanitized
                
                // 1. Add directly to Meeting Studio conversation stream & SQLite
                let durationSec = Double(capturedData.count) / 32000.0
                meetingCoordinator.appendDictation(text: sanitized, duration: durationSec)
                
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
            try? FileManager.default.removeItem(at: tempFile)
            floatingPill.updateState(.error(message: error.localizedDescription))
            statusMessage = "Transcription failed"
        }
        
        MenuBarManager.shared.updateMenuBarIcon(state: isMeetingActive ? .meetingRecording : .idle)
    }
    
    // MARK: - Mode 2: Meeting Studio (Meetily Style)
    
    public func showMeetingStudio() {
        MeetingStudioWindow.shared.toggleVisibility()
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
        
        let devDocsDir = "/Users/ragavij/Documents/Developer/dev_docs"
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "echo_meeting_\(timestamp).md"
        let outPath = "\(devDocsDir)/\(filename)"
        try? md.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("Meeting exported to clipboard and \(outPath)")
    }
    
    public func openAccessibilitySettings() {
        // Trigger system dialog once when user explicitly requests it
        _ = TextInjector.isAccessibilityTrusted(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
