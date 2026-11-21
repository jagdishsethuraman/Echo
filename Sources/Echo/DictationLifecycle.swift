import Foundation

struct DictationPreview: Equatable {
    let text: String
    let byteRange: Range<Int>

    init(text: String, snapshot: AudioPCMSnapshot) {
        self.text = text
        self.byteRange = (snapshot.totalByteCount - snapshot.byteCount)..<snapshot.totalByteCount
    }

    var displayText: String { byteRange.lowerBound > 0 ? "… " + text : text }
}

struct DictationTranscript: Equatable {
    let text: String
    let byteRange: Range<Int>
    let recoveredFromPreview: Bool

    var startOffset: TimeInterval {
        Double(byteRange.lowerBound) / Double(AudioPCMBufferStore.bytesPerSecond)
    }

    var duration: TimeInterval {
        Double(byteRange.count) / Double(AudioPCMBufferStore.bytesPerSecond)
    }

    init?(finalText: String, totalBytes: Int, preview: DictationPreview?) {
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self.text = trimmed
            self.byteRange = 0..<totalBytes
            self.recoveredFromPreview = false
        } else if let preview, !preview.text.isEmpty {
            self.text = "[Partial] " + preview.text
            self.byteRange = preview.byteRange
            self.recoveredFromPreview = true
        } else {
            return nil
        }
    }
}

@MainActor
final class DictationRecording {
    let id = UUID()
    let startTime = Date()
    let meetingSessionID: UUID?
    let target: FocusedDictationField?
    let audio = AudioPCMBufferStore()
    var audioLevel: Float = 0.2
    var preview: DictationPreview?
    var isDecodingPreview = false
    var lastPreviewByteCount = 0

    init(meetingSessionID: UUID?, target: FocusedDictationField?) {
        self.meetingSessionID = meetingSessionID
        self.target = target
    }

    var elapsedSeconds: Int { max(0, Int(Date().timeIntervalSince(startTime))) }
}

@MainActor
final class DictationLifecycle {
    private(set) var active: DictationRecording?
    private var latestID: UUID?

    func start(meetingSessionID: UUID?, target: FocusedDictationField?) -> DictationRecording {
        let recording = DictationRecording(meetingSessionID: meetingSessionID, target: target)
        active = recording
        latestID = recording.id
        return recording
    }

    func stop() -> DictationRecording? {
        defer { active = nil }
        return active
    }

    func acceptPreview(_ preview: DictationPreview, for id: UUID) -> Bool {
        guard let active, active.id == id else { return false }
        active.preview = preview
        return true
    }

    func ownsDelivery(_ id: UUID) -> Bool {
        latestID == id && active == nil
    }
}
