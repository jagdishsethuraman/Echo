import Foundation
import Testing
@testable import Echo

@Suite("MeetingNotesExtractor", .serialized)
struct MeetingNotesExtractorTests {
    
    @Test func emptySegmentsProducesEmptyNotes() {
        let notes = MeetingNotesExtractor.extractAll(from: [])
        #expect(notes.decisions.isEmpty)
        #expect(notes.actionItems.isEmpty)
    }
    
    @Test func extractsDecisionsFromSegments() {
        let segments = [
            TranscriptSegment(
                speaker: .you,
                text: "Good morning team. We decided to use Phonon-2 as our primary STT.",
                durationSeconds: 4.2
            ),
            TranscriptSegment(
                speaker: .meeting,
                text: "Sounds great. We agreed that the release date will be Friday.",
                durationSeconds: 3.8
            ),
            TranscriptSegment(
                speaker: .you,
                text: "Let's go with the graphite frost design system.",
                durationSeconds: 2.5
            )
        ]
        
        let decisions = MeetingNotesExtractor.extractDecisions(from: segments)
        #expect(decisions.count == 3)
        #expect(decisions[0].contains("Phonon-2"))
        #expect(decisions[1].contains("Friday"))
        #expect(decisions[2].contains("design system"))
    }
    
    @Test func extractsActionItemsFromSegments() {
        let segments = [
            TranscriptSegment(
                speaker: .you,
                text: "I will update the unit test suite today.",
                durationSeconds: 3.1
            ),
            TranscriptSegment(
                speaker: .meeting,
                text: "We need to verify the multi-monitor HUD behavior.",
                durationSeconds: 4.0
            ),
            TranscriptSegment(
                speaker: .you,
                text: "Make sure to test the Escape key cancellation.",
                durationSeconds: 2.8
            )
        ]
        
        let actionItems = MeetingNotesExtractor.extractActionItems(from: segments)
        #expect(actionItems.count == 3)
        #expect(actionItems[0].contains("unit test"))
        #expect(actionItems[1].contains("multi-monitor"))
        #expect(actionItems[2].contains("Escape"))
    }
    
    @Test func deduplicatesIdenticalStatements() {
        let segments = [
            TranscriptSegment(speaker: .you, text: "We decided to keep local storage.", durationSeconds: 2.0),
            TranscriptSegment(speaker: .meeting, text: "Yes, we decided to keep local storage.", durationSeconds: 2.0),
            TranscriptSegment(speaker: .you, text: "I will deploy the fix.", durationSeconds: 2.0),
            TranscriptSegment(speaker: .meeting, text: "I will deploy the fix.", durationSeconds: 2.0)
        ]
        
        let notes = MeetingNotesExtractor.extractAll(from: segments)
        #expect(notes.decisions.count == 1)
        #expect(notes.actionItems.count == 1)
    }

    @Test func wordBoundariesPreventSubstringFalsePositives() {
        let segments = [
            TranscriptSegment(speaker: .meeting, text: "The team strongly disagreed on the proposed plan.", durationSeconds: 3.0),
            TranscriptSegment(speaker: .you, text: "The document is currently unapproved by compliance.", durationSeconds: 2.5),
            TranscriptSegment(speaker: .meeting, text: "I saw an ill patient today.", durationSeconds: 2.0)
        ]
        
        let decisions = MeetingNotesExtractor.extractDecisions(from: segments)
        #expect(decisions.isEmpty)
        
        let actions = MeetingNotesExtractor.extractActionItems(from: segments)
        #expect(actions.isEmpty)
    }

    @Test func filtersNegatedDecisionsAndActions() {
        let segments = [
            TranscriptSegment(speaker: .you, text: "We have not decided on the launch date yet.", durationSeconds: 3.0),
            TranscriptSegment(speaker: .meeting, text: "We never agreed to increase the scope.", durationSeconds: 2.8),
            TranscriptSegment(speaker: .you, text: "We will not deploy the build tonight.", durationSeconds: 2.5),
            TranscriptSegment(speaker: .meeting, text: "I don't think we need to refactor that module.", durationSeconds: 3.0)
        ]
        
        let decisions = MeetingNotesExtractor.extractDecisions(from: segments)
        #expect(decisions.isEmpty)
        
        let actions = MeetingNotesExtractor.extractActionItems(from: segments)
        #expect(actions.isEmpty)
    }

    @Test func preservesFullSentenceForPassiveVoiceDecisions() {
        let segments = [
            TranscriptSegment(speaker: .meeting, text: "The new architecture was approved by engineering leadership.", durationSeconds: 3.5)
        ]
        
        let decisions = MeetingNotesExtractor.extractDecisions(from: segments)
        #expect(decisions.count == 1)
        #expect(decisions[0] == "The new architecture was approved by engineering leadership.")
    }

    @Test func respectsExtractionLimits() {
        let segments = (1...10).map { i in
            TranscriptSegment(speaker: .you, text: "We decided to implement feature number \(i).", durationSeconds: 1.0)
        }
        
        let decisions = MeetingNotesExtractor.extractDecisions(from: segments, limit: 3)
        #expect(decisions.count == 3)
    }
    
    @Test func formatsMarkdownCorrectly() {
        let decisions = ["Keep local SQLite storage.", "Release version 1.3."]
        let actionItems = [
            ActionItemState(text: "Verify GitHub Actions CI", isDone: true),
            ActionItemState(text: "Add unit tests", isDone: false)
        ]
        
        let md = MeetingNotesExtractor.formatMarkdown(
            title: "Sprint Planning",
            decisions: decisions,
            actionItems: actionItems
        )
        
        #expect(md.contains("## Sprint Planning — Notes"))
        #expect(md.contains("### Key Decisions"))
        #expect(md.contains("- Keep local SQLite storage."))
        #expect(md.contains("### Action Items"))
        #expect(md.contains("- [x] Verify GitHub Actions CI"))
        #expect(md.contains("- [ ] Add unit tests"))
    }
}
