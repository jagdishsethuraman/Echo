import Foundation
import SQLite3
import Testing
@testable import Echo

@Suite("MeetingCoordinator", .serialized)
struct MeetingCoordinatorTests {
    @MainActor
    private func makeCoordinator(
        engine: @escaping TranscriptionService.Engine = { _ in "" },
        transcriptionService: TranscriptionService? = nil,
        startCapture: @escaping @MainActor () async throws -> Void = {},
        stopCapture: @escaping @MainActor () async -> Void = {}
    ) -> (coordinator: MeetingCoordinator, database: DatabaseManager, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-meeting-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        let coordinator = MeetingCoordinator(
            database: database,
            transcriptionService: transcriptionService ?? TranscriptionService(engine: engine),
            startCapture: startCapture,
            stopCapture: stopCapture
        )
        return (coordinator, database, directory)
    }
    
    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test @MainActor func doesNotCreateEmptySessionAtLaunch() {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }
        
        // DATA-03: no session row until the first utterance arrives.
        #expect(coordinator.activeSession == nil)
        #expect(database.fetchRecentSessions().isEmpty)
    }

    @Test @MainActor func firstDictationCreatesAndPersistsSession() async {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }

        #expect(coordinator.activeSession == nil)

        await coordinator.appendDictation(text: "first words", duration: 1.5)

        let session = coordinator.activeSession
        #expect(session?.title == "Echo Speech Stream")
        #expect(session?.segments.count == 1)
        #expect(database.fetchRecentSessions().count == 1)
        #expect(database.fetchUtterances(sessionId: session!.id).count == 1)
    }
    
    @Test @MainActor func appendDictationUpdatesSessionAndSQLite() async {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }
        
        await coordinator.appendDictation(text: "Quick note about the audio store", duration: 2.5)
        
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
    
    @Test @MainActor func appendingMultipleDictationsKeepsOrder() async {
        let (coordinator, _, directory) = makeCoordinator()
        defer { remove(directory) }
        
        for index in 0..<3 {
            await coordinator.appendDictation(text: "utterance \(index)")
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
    
    @Test @MainActor func doesNotRestoreClosedSessionFromDatabase() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-meeting-closed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { remove(directory) }
        
        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        let closedMeeting = MeetingSession(
            title: "Yesterday's Meeting",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600)
        )
        database.saveSession(closedMeeting)
        database.saveUtterance(
            TranscriptSegment(speaker: .meeting, text: "closed meeting line", durationSeconds: 5),
            sessionId: closedMeeting.id
        )
        
        let coordinator = MeetingCoordinator(
            phononRunner: PhononProcessRunner(fermionPath: "/usr/bin/true"),
            database: database
        )
        
        // Yesterday's closed session must NOT be revived as the active session,
        // and no empty replacement is persisted (DATA-03).
        #expect(coordinator.activeSession == nil)
        #expect(database.fetchRecentSessions().count == 1)
    }

    @Test @MainActor func prunesStaleEmptyOpenSessionAtLaunch() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-meeting-stale-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { remove(directory) }

        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        // Older builds persisted an open, empty stream on every launch.
        let stale = MeetingSession(title: "Echo Speech Stream", startTime: Date(timeIntervalSince1970: 1_700_000_000))
        database.saveSession(stale)
        #expect(database.fetchRecentSessions().count == 1)

        let coordinator = MeetingCoordinator(
            phononRunner: PhononProcessRunner(fermionPath: "/usr/bin/true"),
            database: database
        )

        #expect(coordinator.activeSession == nil)
        #expect(database.fetchRecentSessions().isEmpty)
    }
    
    @Test @MainActor func sessionUpdateCallbackReceivesAppendedSegment() async {
        let (coordinator, _, directory) = makeCoordinator()
        defer { remove(directory) }
        
        var received: [String] = []
        coordinator.onSessionUpdated = { session in
            received = session.segments.compactMap(\.text)
        }
        
        await coordinator.appendDictation(text: "notify me")
        #expect(received == ["notify me"])
    }
    
    @Test @MainActor func finalizationFlushesSpeechAndKeepsItInTheOriginatingMeeting() async throws {
        let allowTranscription = MeetingTestGate()
        let startedTranscription = MeetingTestGate()
        let (coordinator, database, directory) = makeCoordinator(engine: { data in
            if data.first == 1 {
                startedTranscription.signal()
                await allowTranscription.wait()
                return "last words from the first meeting"
            }
            return "words from the second meeting"
        })
        defer { remove(directory) }

        try await coordinator.startSession(title: "First meeting")
        let firstID = try #require(coordinator.activeSession?.id)
        // Speech with no trailing silence only gets submitted by the final flush.
        coordinator.micVAD.processChunk(pcmData: Data(repeating: 1, count: 16_000), rmsEnergy: 0.25)
        let stop = Task { await coordinator.stopSession() }
        await startedTranscription.wait()
        let overlappingStop = Task { await coordinator.stopSession() }

        try await Task.sleep(for: .milliseconds(5_100))
        try await coordinator.startSession(title: "Overlapping attempt")
        #expect(coordinator.activeSession?.id == firstID)
        #expect(database.fetchSession(id: firstID)?.endTime == nil)
        allowTranscription.signal()

        let finalized = try #require(await stop.value)
        let repeated = await overlappingStop.value
        #expect(repeated?.endTime == finalized.endTime)
        #expect(finalized.exportMarkdown().contains("last words from the first meeting"))
        #expect(finalized.endTime != nil)

        try await coordinator.startSession(title: "Second meeting")
        await coordinator.processSpeechSegment(track: .meeting, pcmData: Data([2]), duration: 1)
        let second = try #require(await coordinator.stopSession())
        #expect(second.id != firstID)
        #expect(second.exportMarkdown().contains("words from the second meeting"))
        #expect(!second.exportMarkdown().contains("last words from the first meeting"))

        let reopened = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        #expect(reopened.fetchSession(id: firstID)?.endTime != nil)
        #expect(reopened.fetchUtterances(sessionId: firstID).map(\.text) == ["last words from the first meeting"])
        #expect(reopened.fetchUtterances(sessionId: second.id).map(\.text) == ["words from the second meeting"])
    }

    @Test @MainActor func concurrentStartPreservesSpeechCapturedDuringStartup() async throws {
        let captureStarted = MeetingTestGate()
        let allowStart = MeetingTestGate()
        weak var recorder: MeetingCoordinator?
        let (coordinator, database, directory) = makeCoordinator(
            engine: { _ in "words recorded during startup" },
            startCapture: {
                recorder?.enqueueSegment(track: .you, pcmData: Data([1]), duration: 0.5)
                captureStarted.signal()
                await allowStart.wait()
            }
        )
        recorder = coordinator
        defer { remove(directory) }

        let start = Task { try await coordinator.startSession(title: "First start") }
        await captureStarted.wait()
        try await coordinator.startSession(title: "Overlapping start")
        #expect(database.fetchRecentSessions().isEmpty)
        allowStart.signal()
        try await start.value

        let stopped = await coordinator.stopSession()
        #expect(stopped?.title == "First start")
        #expect(stopped?.segments.map(\.text) == ["words recorded during startup"])
        #expect(database.fetchRecentSessions().count == 1)
    }

    @Test @MainActor func startupAndRecordingShareTheMeetingPCMByteBudget() async throws {
        let captureStarted = MeetingTestGate()
        let allowStart = MeetingTestGate()
        let engineStarted = MeetingTestGate()
        let allowEngine = MeetingTestGate()
        let service = TranscriptionService(
            engine: { data in
                if data.first == 1 { engineStarted.signal() }
                await allowEngine.wait()
                return "segment \(data.first ?? 0)"
            },
            maxPendingBytes: 128
        )
        let (coordinator, _, directory) = makeCoordinator(
            transcriptionService: service,
            startCapture: {
                captureStarted.signal()
                await allowStart.wait()
            }
        )
        defer { remove(directory) }

        let start = Task { try await coordinator.startSession() }
        await captureStarted.wait()
        for index in 1...10 {
            coordinator.enqueueSegment(
                track: index.isMultiple(of: 2) ? .meeting : .you,
                pcmData: Data(repeating: UInt8(index), count: 64),
                duration: 1
            )
        }
        #expect(service.currentQueuedBytes == 128)

        allowStart.signal()
        try await start.value
        await engineStarted.wait()
        #expect(service.currentQueuedBytes == 128)
        #expect(coordinator.captureError?.contains("8 meeting segments could not be transcribed") == true)
        await coordinator.processSpeechSegment(track: .meeting, pcmData: Data([99]), duration: 1)
        #expect(coordinator.captureError?.contains("9 meeting segments could not be transcribed") == true)

        allowEngine.signal()
        let session = try #require(await coordinator.stopSession())
        #expect(Set(session.segments.map(\.text)) == ["segment 1", "segment 2"])
        #expect(await service.waitUntilIdle(timeout: 2))
        #expect(service.currentQueuedBytes == 0)
    }

    @Test @MainActor func failedStartLeavesNoOpenSession() async {
        weak var recorder: MeetingCoordinator?
        let service = TranscriptionService(engine: { _ in "should not decode" }, maxPendingBytes: 1)
        let (coordinator, database, directory) = makeCoordinator(
            transcriptionService: service,
            startCapture: {
                recorder?.enqueueSegment(track: .you, pcmData: Data([1]), duration: 0.5)
                #expect(service.currentQueuedBytes == 1)
                throw TestFailure.captureUnavailable
            }
        )
        recorder = coordinator
        defer { remove(directory) }

        await #expect(throws: TestFailure.captureUnavailable) {
            try await coordinator.startSession()
        }
        #expect(coordinator.activeSession == nil)
        #expect(coordinator.captureError != nil)
        #expect(database.fetchRecentSessions().isEmpty)
        #expect(service.isIdle)
    }

    @Test @MainActor func missingEnginePreventsCaptureAndPersistence() async {
        let (_, database, directory) = makeCoordinator()
        defer { remove(directory) }
        var attemptedCapture = false
        let coordinator = MeetingCoordinator(
            phononRunner: PhononProcessRunner(fermionPath: directory.appendingPathComponent("missing-engine").path),
            database: database,
            startCapture: { attemptedCapture = true },
            stopCapture: {}
        )

        await #expect(throws: PhononClientError.self) {
            try await coordinator.startSession()
        }
        #expect(!attemptedCapture)
        #expect(coordinator.captureError?.contains("missing-engine") == true)
        #expect(database.fetchRecentSessions().isEmpty)
    }

    @Test @MainActor func failedMeetingWriteIsUnpublishedUntilRetryAndPreservesFinalizedSession() async throws {
        let (coordinator, database, directory) = makeCoordinator(engine: { _ in "retry this meeting line" })
        defer { remove(directory) }
        try await coordinator.startSession(title: "Retry meeting")
        let id = try #require(coordinator.activeSession?.id)
        try executeSQL("""
            CREATE TRIGGER reject_utterance BEFORE INSERT ON utterances
            BEGIN SELECT RAISE(ABORT, 'injected utterance write failure'); END;
            """, at: database.activeDatabasePath)

        await coordinator.processSpeechSegment(track: .meeting, pcmData: Data([1]), duration: 1)
        #expect(coordinator.activeSession?.segments.isEmpty == true)
        #expect(coordinator.unsavedTranscriptCount == 1)
        #expect(coordinator.transcriptSaveError?.contains("injected utterance write failure") == true)
        #expect(database.fetchUtterances(sessionId: id).isEmpty)

        _ = await coordinator.stopSession()
        let persistedEnd = try #require(database.fetchSession(id: id)?.endTime)
        try executeSQL("DROP TRIGGER reject_utterance;", at: database.activeDatabasePath)
        await coordinator.retryTranscriptSaves()
        await coordinator.retryTranscriptSaves()

        #expect(coordinator.unsavedTranscriptCount == 0)
        #expect(coordinator.transcriptSaveError == nil)
        #expect(coordinator.activeSession?.segments.map(\.text) == ["retry this meeting line"])
        let reopened = DatabaseManager(customPath: database.activeDatabasePath)
        #expect(reopened.fetchSession(id: id)?.endTime == persistedEnd)
        #expect(reopened.fetchUtterances(sessionId: id).map(\.text) == ["retry this meeting line"])
    }

    @Test @MainActor func failedDeleteKeepsTheActiveSessionAndItsUtterances() async throws {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }
        await coordinator.appendDictation(text: "preserve this line")
        let id = try #require(coordinator.activeSession?.id)
        try executeSQL("""
            CREATE TRIGGER reject_deletion BEFORE DELETE ON sessions
            BEGIN SELECT RAISE(ABORT, 'injected meeting deletion failure'); END;
            """, at: database.activeDatabasePath)

        if case .failed(let error) = await coordinator.deleteSession(id: id) {
            #expect(error.contains("injected meeting deletion failure"))
        } else {
            Issue.record("The coordinator should report the failed deletion")
        }
        #expect(coordinator.activeSession?.id == id)
        #expect(database.fetchUtterances(sessionId: id).map(\.text) == ["preserve this line"])

        try executeSQL("DROP TRIGGER reject_deletion;", at: database.activeDatabasePath)
        guard case .deleted = await coordinator.deleteSession(id: id) else {
            Issue.record("The coordinator should report the successful deletion")
            return
        }
        #expect(coordinator.activeSession == nil)
        #expect(database.fetchUtterances(sessionId: id).isEmpty)
    }

    @Test @MainActor func lateDictationPersistsToItsOriginalMeeting() async throws {
        let (coordinator, database, directory) = makeCoordinator()
        defer { remove(directory) }
        try await coordinator.startSession(title: "Meeting A")
        let firstID = try #require(coordinator.recordingSessionID)
        _ = await coordinator.stopSession()
        let persistedEnd = try #require(database.fetchSession(id: firstID)?.endTime)
        try await coordinator.startSession(title: "Meeting B")
        let secondID = try #require(coordinator.recordingSessionID)
        let segment = TranscriptSegment(speaker: .you, text: "Words from A", durationSeconds: 1)
        await coordinator.saveDictation(segment, meetingSessionID: firstID)

        #expect(database.fetchUtterances(sessionId: firstID).map(\.id) == [segment.id])
        #expect(database.fetchSession(id: firstID)?.endTime == persistedEnd)
        #expect(database.fetchUtterances(sessionId: secondID).isEmpty)
        #expect(coordinator.activeSession?.segments.isEmpty == true)
        _ = await coordinator.stopSession()
    }

    private func executeSQL(_ sql: String, at path: String) throws {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        try #require(sqlite3_open(path, &connection) == SQLITE_OK)
        try #require(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test @MainActor func failuresCountTowardsTheSameMeetingAndOtherSegmentsStillPersist() async throws {
        let (coordinator, database, directory) = makeCoordinator(engine: { data in
            guard data.first == 1 else { throw TestFailure.decodeFailed }
            return "successful speech"
        })
        defer { remove(directory) }

        try await coordinator.startSession()
        await coordinator.processSpeechSegment(track: .you, pcmData: Data([1]), duration: 1)
        await coordinator.processSpeechSegment(track: .meeting, pcmData: Data([2]), duration: 1)
        await coordinator.processSpeechSegment(track: .meeting, pcmData: Data([3]), duration: 1)
        let session = try #require(await coordinator.stopSession())

        #expect(coordinator.captureError?.contains("2 meeting segments could not be transcribed") == true)
        #expect(database.fetchUtterances(sessionId: session.id).map(\.text) == ["successful speech"])
    }
}

private enum TestFailure: Error {
    case captureUnavailable
    case decodeFailed
}

private final class MeetingTestGate: Sendable {
    private let group = DispatchGroup()

    init() { group.enter() }

    func signal() { group.leave() }

    func wait() async {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }
    }
}
