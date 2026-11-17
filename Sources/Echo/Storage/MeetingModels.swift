import Foundation

public struct TranscriptSegment: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let speaker: SpeakerTrack
    public let timestamp: Date
    public let text: String
    public let durationSeconds: Double
    
    public init(
        id: UUID = UUID(),
        speaker: SpeakerTrack,
        timestamp: Date = Date(),
        text: String,
        durationSeconds: Double
    ) {
        self.id = id
        self.speaker = speaker
        self.timestamp = timestamp
        self.text = text
        self.durationSeconds = durationSeconds
    }
}

public struct MeetingSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public let startTime: Date
    public var endTime: Date?
    public var segments: [TranscriptSegment]
    public var summaryMarkdown: String?
    
    public init(
        id: UUID = UUID(),
        title: String = "Untitled Meeting",
        startTime: Date = Date(),
        endTime: Date? = nil,
        segments: [TranscriptSegment] = [],
        summaryMarkdown: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.segments = segments
        self.summaryMarkdown = summaryMarkdown
    }
    
    /// Export meeting session to clean Markdown document
    public func exportMarkdown() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        var md = "# Meeting: \(title)\n\n"
        md += "**Date:** \(formatter.string(from: startTime))\n"
        if let end = endTime {
            let duration = Int(end.timeIntervalSince(startTime))
            let minutes = duration / 60
            let seconds = duration % 60
            md += "**Duration:** \(minutes)m \(seconds)s\n"
        }
        md += "**Total Utterances:** \(segments.count)\n\n"
        
        if let summary = summaryMarkdown, !summary.isEmpty {
            md += "## Executive Summary & Action Items\n\n"
            md += summary + "\n\n"
        }
        
        md += "## Transcript\n\n"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        
        for segment in segments {
            let timeStr = timeFormatter.string(from: segment.timestamp)
            let speakerBadge = segment.speaker == .you ? "**[You]**" : "**[Meeting]**"
            md += "\(speakerBadge) *(\(timeStr))* — \(segment.text)\n\n"
        }
        
        return md
    }
}
