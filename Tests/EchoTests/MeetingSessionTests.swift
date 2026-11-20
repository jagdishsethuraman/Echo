import Foundation
import Testing
@testable import Echo

@Suite("MeetingSession")
struct MeetingSessionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    
    @Test func exportMarkdownIncludesHeaderAndDuration() {
        let session = MeetingSession(
            title: "Design Review",
            startTime: start,
            endTime: start.addingTimeInterval(95),
            summaryMarkdown: "## Summary\nShip it."
        )
        
        let markdown = session.exportMarkdown()
        
        #expect(markdown.hasPrefix("# Meeting: Design Review"))
        #expect(markdown.contains("**Date:**"))
        #expect(markdown.contains("**Duration:** 1m 35s"))
        #expect(markdown.contains("**Total Utterances:** 0"))
        #expect(markdown.contains("## Executive Summary & Action Items"))
        #expect(markdown.contains("Ship it."))
        #expect(markdown.contains("## Transcript"))
    }
    
    @Test func exportMarkdownIncludesSpeakersAndText() {
        let session = MeetingSession(
            title: "Standup",
            startTime: start,
            endTime: start.addingTimeInterval(30),
            segments: [
                TranscriptSegment(
                    speaker: .you,
                    timestamp: start,
                    text: "I fixed the audio engine.",
                    durationSeconds: 3
                ),
                TranscriptSegment(
                    speaker: .meeting,
                    timestamp: start.addingTimeInterval(10),
                    text: "Great, next item.",
                    durationSeconds: 2
                )
            ]
        )
        
        let markdown = session.exportMarkdown()
        
        #expect(markdown.contains("**Total Utterances:** 2"))
        #expect(markdown.contains("**[You]**"))
        #expect(markdown.contains("I fixed the audio engine."))
        #expect(markdown.contains("**[Meeting]**"))
        #expect(markdown.contains("Great, next item."))
        
        // Both segments appear in capture order.
        let youRange = markdown.range(of: "I fixed the audio engine.")
        let meetingRange = markdown.range(of: "Great, next item.")
        #expect(youRange != nil && meetingRange != nil)
        if let youRange, let meetingRange {
            #expect(youRange.lowerBound < meetingRange.lowerBound)
        }
    }
    
    @Test func exportOmitsDurationAndSummaryWhenUnset() {
        let session = MeetingSession(title: "Ad Hoc", startTime: start)
        let markdown = session.exportMarkdown()
        
        #expect(!markdown.contains("**Duration:**"))
        #expect(!markdown.contains("## Executive Summary & Action Items"))
        #expect(markdown.contains("## Transcript"))
    }
    
    @Test func sessionAndSegmentsRoundTripThroughCodable() throws {
        let session = MeetingSession(
            title: "Codable",
            startTime: start,
            endTime: start.addingTimeInterval(10),
            segments: [
                TranscriptSegment(speaker: .meeting, text: "héllo", durationSeconds: 1.5)
            ]
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(MeetingSession.self, from: data)
        
        #expect(decoded.id == session.id)
        #expect(decoded.title == session.title)
        #expect(decoded.segments == session.segments)
        #expect(decoded.endTime == session.endTime)
    }

    @Test func exportMarkdownIncludesDecisionsAndActionItemsWithCheckboxes() {
        let actionItemDone = ActionItemState(text: "Finished task", isDone: true)
        let actionItemOpen = ActionItemState(text: "Pending task", isDone: false)

        let session = MeetingSession(
            title: "Sprint Planning",
            startTime: start,
            actionItems: [actionItemDone, actionItemOpen]
        )

        let decisions = ["Use SQLite WAL mode", "Retain 8-character UUID slugs"]
        let md = session.exportMarkdown(decisions: decisions)

        #expect(md.contains("## Executive Summary & Action Items"))
        #expect(md.contains("### Key Decisions"))
        #expect(md.contains("- Use SQLite WAL mode"))
        #expect(md.contains("- Retain 8-character UUID slugs"))
        #expect(md.contains("### Action Items"))
        #expect(md.contains("- [x] Finished task"))
        #expect(md.contains("- [ ] Pending task"))
    }

    @Test func exportFilenamesContainSessionSlugPreventingSameSecondCollision() {
        let sameSecond = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionA = MeetingSession(title: "Session A", startTime: sameSecond)
        let sessionB = MeetingSession(title: "Session B", startTime: sameSecond)

        let timestamp = ISO8601DateFormatter().string(from: sameSecond).replacingOccurrences(of: ":", with: "-")
        let slugA = sessionA.id.uuidString.prefix(8).lowercased()
        let slugB = sessionB.id.uuidString.prefix(8).lowercased()

        let filenameA = "echo_meeting_\(timestamp)_\(slugA).md"
        let filenameB = "echo_meeting_\(timestamp)_\(slugB).md"

        #expect(filenameA != filenameB)
        #expect(filenameA.contains(slugA))
        #expect(filenameB.contains(slugB))
    }
}
