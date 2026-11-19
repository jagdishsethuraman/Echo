import Foundation
import Testing
@testable import Echo

@Suite("DatabaseManager", .serialized)
struct DatabaseManagerTests {
    private func makeDatabase() -> (db: DatabaseManager, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-db-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        return (db, directory)
    }
    
    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test func sessionRoundTrip() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = MeetingSession(
            title: "Quarterly Review",
            startTime: start,
            endTime: start.addingTimeInterval(95),
            summaryMarkdown: "## Notes\nWe decided things."
        )
        db.saveSession(session)
        
        let fetched = db.fetchRecentSessions()
        #expect(fetched.count == 1)
        let stored = fetched.first
        #expect(stored?.id == session.id)
        #expect(stored?.title == "Quarterly Review")
        #expect(stored?.startTime.timeIntervalSince1970 == start.timeIntervalSince1970)
        #expect(stored?.endTime?.timeIntervalSince1970 == start.addingTimeInterval(95).timeIntervalSince1970)
        #expect(stored?.summaryMarkdown == "## Notes\nWe decided things.")
        #expect(stored?.segments.isEmpty == true)
    }
    
    @Test func sessionUpsertKeepsOneRowAndUpdatesFields() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        var session = MeetingSession(title: "Draft", startTime: Date(timeIntervalSince1970: 1_700_000_000))
        db.saveSession(session)
        
        session.title = "Final"
        session.endTime = Date(timeIntervalSince1970: 1_700_000_120)
        db.saveSession(session)
        
        let fetched = db.fetchRecentSessions()
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Final")
        #expect(fetched.first?.endTime != nil)
    }
    
    @Test func sessionsAreNewestFirstAndLimited() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in 0..<3 {
            db.saveSession(MeetingSession(
                title: "Session \(offset)",
                startTime: base.addingTimeInterval(Double(offset) * 60)
            ))
        }
        
        let all = db.fetchRecentSessions(limit: 10)
        #expect(all.map(\.title) == ["Session 2", "Session 1", "Session 0"])
        
        let limited = db.fetchRecentSessions(limit: 2)
        #expect(limited.map(\.title) == ["Session 2", "Session 1"])
    }
    
    @Test func utteranceRoundTripsPunctuationAndUnicode() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let session = MeetingSession(title: "Encoding")
        db.saveSession(session)
        
        // Apostrophes, em dashes, curly quotes and CJK all stressed the old
        // SQLITE_STATIC bind path.
        let text = "It's déjà vu — \"quoted\" 你好 🎙️"
        let segment = TranscriptSegment(
            speaker: .meeting,
            timestamp: Date(timeIntervalSince1970: 1_700_000_010),
            text: text,
            durationSeconds: 2.5
        )
        db.saveUtterance(segment, sessionId: session.id)
        
        let fetched = db.fetchUtterances(sessionId: session.id)
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == segment.id)
        #expect(fetched.first?.text == text)
        #expect(fetched.first?.speaker == .meeting)
        #expect(fetched.first?.durationSeconds == 2.5)
        #expect(fetched.first?.timestamp.timeIntervalSince1970 == 1_700_000_010)
    }
    
    @Test func utterancesAreOrderedByTimestamp() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let session = MeetingSession(title: "Ordering")
        db.saveSession(session)
        
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in [2.0, 0.0, 1.0] {
            db.saveUtterance(
                TranscriptSegment(
                    speaker: .you,
                    timestamp: base.addingTimeInterval(offset),
                    text: "at \(offset)",
                    durationSeconds: 1
                ),
                sessionId: session.id
            )
        }
        
        let fetched = db.fetchUtterances(sessionId: session.id)
        #expect(fetched.map(\.text) == ["at 0.0", "at 1.0", "at 2.0"])
    }
    
    @Test func dictationsAreSeparateFromSessionQueries() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let session = MeetingSession(title: "Mixed")
        db.saveSession(session)
        
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        db.saveUtterance(
            TranscriptSegment(speaker: .you, timestamp: base, text: "meeting line", durationSeconds: 1),
            sessionId: session.id
        )
        db.saveUtterance(
            TranscriptSegment(
                speaker: .you,
                timestamp: base.addingTimeInterval(10),
                text: "quick dictation",
                durationSeconds: 1
            ),
            sessionId: session.id,
            isDictation: true
        )
        
        #expect(db.fetchUtterances(sessionId: session.id).count == 2)
        let dictations = db.fetchRecentDictations(limit: 10)
        #expect(dictations.count == 1)
        #expect(dictations.first?.text == "quick dictation")
        #expect(dictations.first?.speaker == .you)
    }
    
    @Test func dictionaryUpsertReturnsPersistedRow() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let first = db.saveOrIncrementDictionaryWord(raw: "phone on", preferred: "Phonon")
        #expect(first.rawPattern == "phone on")
        #expect(first.preferredReplacement == "Phonon")
        #expect(first.frequency == 1)
        #expect(first.caseSensitive == false)
        
        // A second save updates the existing row: same id, incremented frequency.
        let second = db.saveOrIncrementDictionaryWord(raw: "phone on", preferred: "Fermion")
        #expect(second.id == first.id)
        #expect(second.frequency == 2)
        #expect(second.preferredReplacement == "Fermion")
        #expect(db.fetchDictionaryEntries().count == 1)
    }
    
    @Test func dictionaryEntriesSortByFrequency() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        db.saveOrIncrementDictionaryWord(raw: "rare", preferred: "Rare")
        db.saveOrIncrementDictionaryWord(raw: "common", preferred: "Common")
        db.saveOrIncrementDictionaryWord(raw: "common", preferred: "Common")
        db.saveOrIncrementDictionaryWord(raw: "common", preferred: "Common")
        
        let entries = db.fetchDictionaryEntries()
        #expect(entries.first?.rawPattern == "common")
        #expect(entries.first?.frequency == 3)
        #expect(entries.last?.rawPattern == "rare")
    }
    
    @Test func dictionaryDeleteRemovesEntry() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let entry = db.saveOrIncrementDictionaryWord(raw: "custom", preferred: "Custom")
        db.deleteDictionaryEntry(id: entry.id)
        #expect(db.fetchDictionaryEntries().isEmpty)
    }
    
    @Test func schemaVersionIsTracked() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        #expect(db.userVersion() >= 2)
    }

    @Test func migrationAddsSessionStartIndex() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }

        // Re-opening an existing v2 database must be idempotent.
        let reopened = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        #expect(reopened.userVersion() == 2)

        // The v2 index exists and the query plan uses it.
        let plan = db.explainQueryPlan(
            "SELECT id FROM sessions ORDER BY start_time DESC LIMIT 5;"
        )
        #expect(plan.contains("idx_sessions_start"))
    }

    @Test func deleteEmptySessionsKeepsSessionsWithUtterances() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }

        let emptyClosed = MeetingSession(
            title: "Empty",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_060)
        )
        let populated = MeetingSession(title: "Populated", startTime: Date(timeIntervalSince1970: 1_700_000_100))
        db.saveSession(emptyClosed)
        db.saveSession(populated)
        db.saveUtterance(
            TranscriptSegment(speaker: .you, text: "kept", durationSeconds: 1),
            sessionId: populated.id
        )

        // An open (end_time NULL) session must survive the closed-only pass.
        let emptyOpen = MeetingSession(title: "Still recording", startTime: Date(timeIntervalSince1970: 1_700_000_200))
        db.saveSession(emptyOpen)

        let removed = db.deleteEmptySessions(includingOpen: false)

        #expect(removed == 1)
        let remaining = Set(db.fetchRecentSessions(limit: 10).map(\.title))
        #expect(remaining == ["Populated", "Still recording"])
    }

    @Test func launchRetentionRemovesStaleOpenSessionsButHonoursKeepId() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }

        let staleOpen = MeetingSession(
            title: "Echo Speech Stream",
            startTime: Date(timeIntervalSince1970: 1_700_000_000)
        )
        db.saveSession(staleOpen)

        // Protecting an in-progress recording keeps its empty open row.
        #expect(db.deleteEmptySessions(includingOpen: true, keeping: staleOpen.id) == 0)
        #expect(db.fetchRecentSessions().count == 1)

        // At launch nothing is protected, so the stale row is pruned.
        #expect(db.deleteEmptySessions(includingOpen: true) == 1)
        #expect(db.fetchRecentSessions().isEmpty)
    }
    
    @Test func deleteSessionCascadesToUtterances() {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let session = MeetingSession(title: "Cascading Test")
        db.saveSession(session)
        
        let seg1 = TranscriptSegment(speaker: .you, text: "line 1", durationSeconds: 1.0)
        let seg2 = TranscriptSegment(speaker: .meeting, text: "line 2", durationSeconds: 1.5)
        db.saveUtterance(seg1, sessionId: session.id)
        db.saveUtterance(seg2, sessionId: session.id)
        
        #expect(db.fetchUtterances(sessionId: session.id).count == 2)
        
        // Deleting the session must cascade and delete all associated utterances
        db.deleteSession(id: session.id)
        
        #expect(db.fetchRecentSessions().filter { $0.id == session.id }.isEmpty)
        #expect(db.fetchUtterances(sessionId: session.id).isEmpty)
    }
    
    @Test func asyncOperationsPersistData() async {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let session = MeetingSession(title: "Async Session")
        await db.saveSessionAsync(session)
        
        let seg = TranscriptSegment(speaker: .you, text: "async utterance", durationSeconds: 2.0)
        await db.saveUtteranceAsync(seg, sessionId: session.id)
        
        let sessions = await db.fetchRecentSessionsAsync()
        #expect(sessions.contains { $0.id == session.id })
        
        let utterances = db.fetchUtterances(sessionId: session.id)
        #expect(utterances.count == 1)
        #expect(utterances.first?.text == "async utterance")
    }

    @Test func fetchSessionByIdReturnsTargetSession() async {
        let (db, directory) = makeDatabase()
        defer { remove(directory) }
        
        let session = MeetingSession(title: "Architecture Sync")
        db.saveSession(session)
        
        let fetched = db.fetchSession(id: session.id)
        #expect(fetched?.id == session.id)
        #expect(fetched?.title == "Architecture Sync")
        
        let fetchedAsync = await db.fetchSessionAsync(id: session.id)
        #expect(fetchedAsync?.id == session.id)
        #expect(fetchedAsync?.title == "Architecture Sync")
        
        let nonExistent = db.fetchSession(id: UUID())
        #expect(nonExistent == nil)
    }
}
