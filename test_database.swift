import Foundation

@main
struct DatabaseVerificationTest {
    static func main() async {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  ECHO — SQLite Backend & Word Memory Verification")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        let tempDbPath = "/tmp/echo_test_\(UUID().uuidString).sqlite"
        let db = DatabaseManager(customPath: tempDbPath)
        let memoryEngine = WordMemoryEngine(database: db)
        
        // 1. Verify Sessions
        let testSession = MeetingSession(
            title: "Executive Architecture Sync",
            startTime: Date(),
            summaryMarkdown: "## Notes\nKey choices made."
        )
        db.saveSession(testSession)
        
        let fetchedSessions = db.fetchRecentSessions()
        assert(fetchedSessions.count == 1, "Failed to fetch session from SQLite")
        assert(fetchedSessions.first?.title == "Executive Architecture Sync", "Session title mismatch")
        print("[1/5] Session persistence in SQLite: PASSED")
        
        // 2. Verify Utterances
        let utterance = TranscriptSegment(
            speaker: .you,
            text: "Hello team, let us review phonon and antigravity.",
            durationSeconds: 2.4
        )
        db.saveUtterance(utterance, sessionId: testSession.id, isDictation: false)
        
        let fetchedUtterances = db.fetchUtterances(sessionId: testSession.id)
        assert(fetchedUtterances.count == 1, "Failed to fetch utterance")
        assert(fetchedUtterances.first?.text == utterance.text, "Utterance text mismatch")
        print("[2/5] Utterance persistence in SQLite: PASSED")
        
        // 3. Verify Quick Dictation Flagging
        let dictationUtterance = TranscriptSegment(
            speaker: .you,
            text: "Push to talk quick dictation note",
            durationSeconds: 1.1
        )
        db.saveUtterance(dictationUtterance, sessionId: nil, isDictation: true)
        let dictations = db.fetchRecentDictations()
        assert(dictations.count == 1, "Dictation filter failed")
        assert(dictations.first?.text == dictationUtterance.text, "Dictation text mismatch")
        print("[3/5] Quick Dictation isolation & history: PASSED")
        
        // 4. Verify Word Memory Sanitization (Default seeds)
        let rawInput = "I am testing phone on and anti gravity on bento with ragav."
        let sanitized = memoryEngine.sanitize(rawInput)
        let expected = "I am testing Phonon and Antigravity on Bento with Ragav."
        assert(sanitized == expected, "Sanitized output mismatch! Got: '\(sanitized)'")
        print("[4/5] Default vocabulary replacement: PASSED (\"\(sanitized)\")")
        
        // 5. Verify Word Boundary Safety & Custom Learning
        // Sub-word protection: "saxophone on" should NOT replace "phone on"
        let trickyInput = "The saxophone on stage sounded crisp."
        let safeSanitized = memoryEngine.sanitize(trickyInput)
        assert(safeSanitized == trickyInput, "Word boundary check failed! Replaced sub-word in saxophone")
        
        // Learn dynamic custom word
        memoryEngine.remember(raw: "acoustics studio", preferred: "Acoustic Atelier™")
        let customInput = "Welcome to the acoustics studio today."
        let customOutput = memoryEngine.sanitize(customInput)
        assert(customOutput == "Welcome to the Acoustic Atelier™ today.", "Dynamic word memory failed")
        print("[5/5] Word boundary safety & dynamic learning: PASSED (\"\(customOutput)\")")
        
        try? FileManager.default.removeItem(atPath: tempDbPath)
        print("\n  ALL 5 DATABASE & WORD MEMORY TESTS PASSED (100%)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
