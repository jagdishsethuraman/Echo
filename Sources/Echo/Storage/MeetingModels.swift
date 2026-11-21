import Foundation
import CryptoKit

public struct ActionItemState: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var text: String
    public var isDone: Bool

    public init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

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
    public var actionItems: [ActionItemState]
    
    public init(
        id: UUID = UUID(),
        title: String = "Untitled Meeting",
        startTime: Date = Date(),
        endTime: Date? = nil,
        segments: [TranscriptSegment] = [],
        summaryMarkdown: String? = nil,
        actionItems: [ActionItemState] = []
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.segments = segments
        self.summaryMarkdown = summaryMarkdown
        self.actionItems = actionItems
    }

    enum CodingKeys: String, CodingKey {
        case id, title, startTime, endTime, segments, summaryMarkdown, actionItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.startTime = try container.decode(Date.self, forKey: .startTime)
        self.endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        self.segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        self.summaryMarkdown = try container.decodeIfPresent(String.self, forKey: .summaryMarkdown)
        self.actionItems = try container.decodeIfPresent([ActionItemState].self, forKey: .actionItems) ?? []
    }
    
    /// Persisted edits take precedence over inferred tasks, including pre-upgrade UUIDs.
    func resolvedActionItems(saved: [ActionItemState], inferred: [String]) -> [ActionItemState] {
        var result = saved
        var seen = Set(saved.map { $0.text.lowercased() })
        for text in inferred where seen.insert(text.lowercased()).inserted {
            // Unsaved inferred items keep their SwiftUI identity across relaunches.
            let digest = SHA256.hash(data: Data((id.uuidString + text.lowercased()).utf8))
            let uuid = digest.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }
            result.append(ActionItemState(id: UUID(uuid: uuid), text: text))
        }
        return result
    }

    /// Resolve saved checkbox edits for every export surface before formatting off the UI actor.
    func markdown(using database: DatabaseManager, includeTranscript: Bool = true) async -> String {
        let persisted = await database.fetchActionItemsAsync(sessionId: id)
        return await Task.detached {
            notesDocument(savedItems: persisted.isEmpty ? actionItems : persisted, includeTranscript: includeTranscript)
        }.value
    }

    func notesDocument(savedItems: [ActionItemState], includeTranscript: Bool = true) -> String {
        let extracted = MeetingNotesExtractor.extractAll(from: segments, limit: Int.max)
        let items = resolvedActionItems(saved: savedItems, inferred: extracted.actionItems)
        return exportMarkdown(decisions: extracted.decisions, actionItems: items, includeTranscript: includeTranscript)
    }

    /// Export meeting session to clean Markdown document.
    /// Uses passed or persistent decisions and action items to guarantee unified output.
    public func exportMarkdown(
        decisions: [String]? = nil,
        actionItems: [ActionItemState]? = nil,
        includeTranscript: Bool = true
    ) -> String {
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
        
        let itemsToExport = actionItems ?? self.actionItems
        let hasDecisions = decisions != nil && !decisions!.isEmpty
        let hasActionItems = !itemsToExport.isEmpty
        let hasSummary = summaryMarkdown != nil && !summaryMarkdown!.isEmpty
        
        if hasSummary || hasDecisions || hasActionItems {
            md += "## Executive Summary & Action Items\n\n"
            if let summary = summaryMarkdown, !summary.isEmpty {
                md += summary + "\n\n"
            }
            if let decisions, !decisions.isEmpty {
                md += "### Key Decisions\n"
                for d in decisions {
                    md += "- \(d)\n"
                }
                md += "\n"
            }
            if !itemsToExport.isEmpty {
                md += "### Action Items\n"
                for item in itemsToExport {
                    md += "- [\(item.isDone ? "x" : " ")] \(item.text)\n"
                }
                md += "\n"
            }
        }
        
        guard includeTranscript else { return md }
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
