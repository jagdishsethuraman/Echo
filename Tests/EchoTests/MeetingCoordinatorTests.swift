import Foundation
import Testing
@testable import Echo

@Suite("MeetingCoordinator", .serialized)
struct MeetingCoordinatorTests {
    private func makeCoordinator() -> (coordinator: MeetingCoordinator, database: DatabaseManager, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-meeting-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        let coordinator = MeetingCoordinator(
            phononRunner: PhononProcessRunner(fermionPath: "/usr/bin/true"),
            database: database
        )
        return (coordinator, database, directory)
    }
    
    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test @MainActor func createsInitialSessionWhenDatabaseIsEmpty() {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }
        
        let session = coordinator.activeSession
        #expect(session != nil)
        #expect(session?.title == "Echo Speech Stream")
        #expect(session?.segments.isEmpty == true)
        #expect(database.fetchRecentSessions().count == 1)
    }
    
    @Test @MainActor func appendDictationUpdatesSessionAndSQLite() {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }
        
        coordinator.appendDictation(text: "Quick note about the audio store", duration: 2.5)
        
        let session = coordinator.activeSession
        #expect(session?.segments.count == 1)
        #expect(session?.segments.last?.text == "Quick note about the audio store")
        #expect(session?.segments.last?.speaker == .you)
        #expect(session?.segments.last?.durationSeconds == 2.5)
        
        let dictations = database.fetchRecentDictations(limit: 5)
        #expect(dictations.count == 1)
        #expect(dictations.first?.text == "Quick note about the audio store")
        
        let persisted = session.map { database.fetchUtterances(sessionId: $0.id) } ?? []
        #expect(persisted.count == 1)
    }
    
    @Test @MainActor func appendingMultipleDictationsKeepsOrder() {
        let (coordinator, _, directory) = makeCoordinator()
        defer { remove(directory) }
        
        for index in 0..<3 {
            coordinator.appendDictation(text: "utterance \(index)")
        }
        
        let texts = coordinator.activeSession?.segments.compactMap(\.text)
        #expect(texts == ["utterance 0", "utterance 1", "utterance 2"])
    }
    
    @Test @MainActor func restoresMostRecentSessionFromDatabase() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-meeting-restore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { remove(directory) }
        
        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        let older = MeetingSession(title: "Older", startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = MeetingSession(title: "Newer", startTime: Date(timeIntervalSince1970: 1_700_000_600))
        database.saveSession(older)
        database.saveSession(newer)
        database.saveUtterance(
            TranscriptSegment(speaker: .meeting, text: "persisted line", durationSeconds: 1),
            sessionId: newer.id
        )
        
        let coordinator = MeetingCoordinator(
            phononRunner: PhononProcessRunner(fermionPath: "/usr/bin/true"),
            database: database
        )
        
        #expect(coordinator.activeSession?.id == newer.id)
        #expect(coordinator.activeSession?.title == "Newer")
        #expect(coordinator.activeSession?.segments.count == 1)
        #expect(coordinator.activeSession?.segments.first?.text == "persisted line")
    }
    
    @Test @MainActor func sessionUpdateCallbackReceivesAppendedSegment() {
        let (coordinator, _, directory) = makeCoordinator()
        defer { remove(directory) }
        
        var received: [String] = []
        coordinator.onSessionUpdated = { session in
            received = session.segments.compactMap(\.text)
        }
        
        coordinator.appendDictation(text: "notify me")
        #expect(received == ["notify me"])
    }
    
    @Test @MainActor func stopSessionWaitsForInFlightTranscriptions() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-meeting-drain-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { remove(directory) }
        
        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        let service = TranscriptionService(engine: { _ in
            try await Task.sleep(for: .milliseconds(80))
            return "final line"
        })
        let coordinator = MeetingCoordinator(
            phononRunner: PhononProcessRunner(fermionPath: "/usr/bin/true"),
            database: database,
            transcriptionService: service
        )
        
        coordinator.enqueueSegment(
            track: .you,
            pcmData: Data(repeating: 1, count: 3_200),
            duration: 0.1
        )
        
        let session = await coordinator.stopSession()
        
        #expect(session?.segments.compactMap(\.text) == ["final line"])
    }
}
