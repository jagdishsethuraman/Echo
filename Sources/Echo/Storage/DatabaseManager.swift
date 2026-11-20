import Foundation
import SQLite3

public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()

    public struct StartupError: LocalizedError, Sendable {
        public let path: String
        public let message: String
        public var errorDescription: String? { message }
    }

    public enum DatabaseError: LocalizedError, Sendable {
        case unavailable(String)
        case executionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable(let message): return "Database unavailable: \(message)"
            case .executionFailed(let message): return "Database operation failed: \(message)"
            }
        }
    }

    /// The database is unavailable when opening, migration, or validation fails.
    public private(set) var startupError: StartupError?
    
    private var db: OpaquePointer?
    private let lock = NSLock()
    private var dbPath: String
    private var _isUsingFallback: Bool = false
    private let dbQueue = DispatchQueue(label: "com.echo.database", qos: .utility)
    
    public var isUsingFallbackStorage: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isUsingFallback
    }

    public var activeDatabasePath: String {
        lock.lock()
        defer { lock.unlock() }
        return dbPath
    }
    
    /// Callback for surfacing runtime SQLite failures to the UI. Invoked on the main
    /// queue; kept outside `lock` so a handler that reads the database cannot
    /// deadlock the caller.
    public typealias ErrorHandler = (String) -> Void
    private let errorLock = NSLock()
    private var _onError: ErrorHandler?

    public var onError: ErrorHandler? {
        get { errorLock.withLock { _onError } }
        set { errorLock.withLock { _onError = newValue } }
    }

    /// SQLite treats a NULL destructor as `SQLITE_STATIC`: it keeps the pointer
    /// passed to `sqlite3_bind_text` after the call returns. Swift `String` and
    /// `NSString` buffers are temporaries, so every bind must use
    /// `SQLITE_TRANSIENT` to have SQLite copy the value instead.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
    
    /// Single place for surfacing SQLite failures: log once and notify the
    /// optional UI handler without touching any database state under `lock`.
    private func reportError(_ context: String) {
        guard startupError == nil else { return }
        let message = String(cString: sqlite3_errmsg(db))
        print("Echo DatabaseManager: \(context): \(message)")
        if let handler = onError {
            DispatchQueue.main.async {
                handler("\(context): \(message)")
            }
        }
    }

    public init(customPath: String? = nil) {
        if let path = customPath {
            self.dbPath = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let echoDir = appSupport.appendingPathComponent("Echo", isDirectory: true)
            try? FileManager.default.createDirectory(at: echoDir, withIntermediateDirectories: true)
            self.dbPath = echoDir.appendingPathComponent("echo.sqlite").path
        }
        
        do {
            try openDatabase(allowFallback: customPath == nil)
            try configurePragmas()
            try applyMigrations()
        } catch {
            let failure = (error as? StartupError) ?? StartupError(path: dbPath, message: error.localizedDescription)
            startupError = failure
            print("Echo DatabaseManager: \(failure.message) (\(failure.path))")
            closeDatabase()
        }
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        closeDatabase()
    }
    
    // MARK: - Lifecycle & Initialization
    
    private func configurePragmas() throws {
        try executeStartupSQL("""
            PRAGMA busy_timeout = 3000;
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            """, context: "Could not configure the database")
    }
    
    private func openDatabase(allowFallback: Bool) throws {
        if sqlite3_open(dbPath, &db) == SQLITE_OK { return }

        let openError = sqliteStartupError("Could not open the database")
        closeDatabase()
        guard allowFallback else { throw openError }

        // Sandbox-safe fallback to a per-user directory that does not depend on
        // where the source tree happens to live.
        let fallbackDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".echo", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: fallbackDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fallbackPath = fallbackDirectory.appendingPathComponent("echo.sqlite").path
        
        if sqlite3_open(fallbackPath, &db) == SQLITE_OK {
            dbPath = fallbackPath
            _isUsingFallback = true
            print("Echo DatabaseManager: Initialized at fallback: \(fallbackPath)")
            return
        }
        closeDatabase()

        let tempPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("echo.sqlite").path
        guard sqlite3_open(tempPath, &db) == SQLITE_OK else { throw openError }
        dbPath = tempPath
        _isUsingFallback = true
        print("Echo DatabaseManager: Initialized at temp fallback: \(tempPath)")
    }

    private func closeDatabase() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    public func userVersion() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return (try? readUserVersion()) ?? 0
    }
    
    private func readUserVersion() throws -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            throw sqliteStartupError("Could not read the database schema version")
        }
        return sqlite3_column_int(stmt, 0)
    }

    private func sqliteStartupError(_ context: String) -> StartupError {
        StartupError(path: dbPath, message: "\(context): \(String(cString: sqlite3_errmsg(db)))")
    }

    private func executeStartupSQL(_ sql: String, context: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteStartupError(context)
        }
    }
    
    /// SQLite's query plan for `sql`; used by migration tests to prove an index
    /// is actually considered.
    func explainQueryPlan(_ sql: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "EXPLAIN QUERY PLAN \(sql)", -1, &stmt, nil) == SQLITE_OK else {
            reportError("EXPLAIN QUERY PLAN")
            sqlite3_finalize(stmt)
            return ""
        }
        var lines: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let detail = sqlite3_column_text(stmt, 3) {
                lines.append(String(cString: detail))
            }
        }
        sqlite3_finalize(stmt)
        return lines.joined(separator: "\n")
    }

    private static let validateCoreSchemaSQL = """
        SELECT id, title, start_time, end_time, summary_markdown, created_at FROM sessions LIMIT 0;
        SELECT id, session_id, speaker, timestamp, text, duration_seconds, is_dictation FROM utterances LIMIT 0;
        SELECT id, raw_pattern, preferred_replacement, frequency, case_sensitive, created_at, updated_at
            FROM dictionary LIMIT 0;
        """

    private func applyMigrations() throws {
        let version = try readUserVersion()
        if version < 1 {
            let schemaSQL = """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL,
                summary_markdown TEXT,
                created_at REAL NOT NULL
            );
            
            CREATE TABLE IF NOT EXISTS utterances (
                id TEXT PRIMARY KEY,
                session_id TEXT,
                speaker TEXT NOT NULL,
                timestamp REAL NOT NULL,
                text TEXT NOT NULL,
                duration_seconds REAL NOT NULL,
                is_dictation INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            );
            
            CREATE INDEX IF NOT EXISTS idx_utterances_session ON utterances(session_id);
            CREATE INDEX IF NOT EXISTS idx_utterances_timestamp ON utterances(timestamp);
            
            CREATE TABLE IF NOT EXISTS dictionary (
                id TEXT PRIMARY KEY,
                raw_pattern TEXT NOT NULL UNIQUE,
                preferred_replacement TEXT NOT NULL,
                frequency INTEGER NOT NULL DEFAULT 1,
                case_sensitive INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            \(Self.validateCoreSchemaSQL)
            """

            try migrate(to: 1, sql: schemaSQL)
        }

        // An earlier release could mark a partially created database as v2.
        try executeStartupSQL(Self.validateCoreSchemaSQL, context: "Could not validate the database schema")

        // v2: the history/retention queries order sessions by start time.
        if version < 2 {
            try migrate(to: 2, sql: "CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_time DESC);")
        }

        // v3: action items table for meeting studio persistence and export integrity
        if version < 3 {
            let actionItemsSQL = """
            CREATE TABLE IF NOT EXISTS action_items (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                text TEXT NOT NULL,
                is_done INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_action_items_session ON action_items(session_id);
            """
            try migrate(to: 3, sql: actionItemsSQL)
        }
    }

    private func migrate(to version: Int32, sql: String) throws {
        let context = "Could not migrate the database to v\(version)"
        try executeStartupSQL("BEGIN IMMEDIATE;", context: context)
        do {
            // Read the version under the write lock in case another process upgraded it.
            if try readUserVersion() < version {
                try executeStartupSQL(sql, context: context)
                try executeStartupSQL("PRAGMA user_version = \(version);", context: context)
            }
            try executeStartupSQL("COMMIT;", context: context)
        } catch {
            if sqlite3_get_autocommit(db) == 0 {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
            throw error
        }
    }
    
    // MARK: - Sessions & Utterances
    
    private func saveSessionLocked(_ session: MeetingSession) throws {
        guard let db else {
            throw DatabaseError.unavailable("Database pointer is nil")
        }
        let sql = """
        INSERT INTO sessions (id, title, start_time, end_time, summary_markdown, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            end_time = excluded.end_time,
            summary_markdown = excluded.summary_markdown;
        """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("saveSession prepare failed: \(msg)")
        }
        
        bindText(stmt, 1, session.id.uuidString)
        bindText(stmt, 2, session.title)
        sqlite3_bind_double(stmt, 3, session.startTime.timeIntervalSince1970)
        
        if let end = session.endTime {
            sqlite3_bind_double(stmt, 4, end.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        
        bindText(stmt, 5, session.summaryMarkdown)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("saveSession step failed: \(msg)")
        }
    }

    private func saveUtteranceLocked(_ segment: TranscriptSegment, sessionId: UUID?, isDictation: Bool) throws {
        guard let db else {
            throw DatabaseError.unavailable("Database pointer is nil")
        }
        let sql = """
        INSERT INTO utterances (id, session_id, speaker, timestamp, text, duration_seconds, is_dictation)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            text = excluded.text;
        """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("saveUtterance prepare failed: \(msg)")
        }
        
        bindText(stmt, 1, segment.id.uuidString)
        bindText(stmt, 2, sessionId?.uuidString)
        
        let speakerStr = segment.speaker == .you ? "you" : "meeting"
        bindText(stmt, 3, speakerStr)
        sqlite3_bind_double(stmt, 4, segment.timestamp.timeIntervalSince1970)
        bindText(stmt, 5, segment.text)
        sqlite3_bind_double(stmt, 6, segment.durationSeconds)
        sqlite3_bind_int(stmt, 7, isDictation ? 1 : 0)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("saveUtterance step failed: \(msg)")
        }
    }

    public func saveSession(_ session: MeetingSession) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try saveSessionLocked(session)
        } catch {
            reportError("saveSession")
        }
    }
    
    public func saveUtterance(_ segment: TranscriptSegment, sessionId: UUID? = nil, isDictation: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try saveUtteranceLocked(segment, sessionId: sessionId, isDictation: isDictation)
        } catch {
            reportError("saveUtterance")
        }
    }

    /// Atomically persists both session metadata and an utterance in a single immediate transaction.
    public func saveSessionAndUtterance(
        _ session: MeetingSession,
        segment: TranscriptSegment,
        isDictation: Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let db else {
            throw DatabaseError.unavailable("Database pointer is nil")
        }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            reportError("saveSessionAndUtterance BEGIN")
            throw DatabaseError.executionFailed("BEGIN TRANSACTION failed: \(msg)")
        }

        do {
            try saveSessionLocked(session)
            try saveUtteranceLocked(segment, sessionId: session.id, isDictation: isDictation)
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.executionFailed("COMMIT failed: \(msg)")
            }
        } catch {
            if sqlite3_get_autocommit(db) == 0 {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
            reportError("saveSessionAndUtterance")
            throw error
        }
    }
    
    public func deleteSession(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "DELETE FROM sessions WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                reportError("deleteSession")
            }
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Action Items

    private func saveActionItemLocked(_ item: ActionItemState, sessionId: UUID) throws {
        guard let db else {
            throw DatabaseError.unavailable("Database pointer is nil")
        }
        let sql = """
        INSERT INTO action_items (id, session_id, text, is_done, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            text = excluded.text,
            is_done = excluded.is_done;
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("saveActionItem prepare failed: \(msg)")
        }

        bindText(stmt, 1, item.id.uuidString)
        bindText(stmt, 2, sessionId.uuidString)
        bindText(stmt, 3, item.text)
        sqlite3_bind_int(stmt, 4, item.isDone ? 1 : 0)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("saveActionItem step failed: \(msg)")
        }
    }

    private func fetchActionItemsLocked(sessionId: UUID) -> [ActionItemState] {
        guard let db else { return [] }
        let sql = "SELECT id, text, is_done FROM action_items WHERE session_id = ? ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        var results: [ActionItemState] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, sessionId.uuidString)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let textCString = sqlite3_column_text(stmt, 1),
                      let id = UUID(uuidString: String(cString: idCString)) else {
                    continue
                }
                let text = String(cString: textCString)
                let isDone = sqlite3_column_int(stmt, 2) != 0
                results.append(ActionItemState(id: id, text: text, isDone: isDone))
            }
        }
        return results
    }

    public func saveActionItem(_ item: ActionItemState, sessionId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try saveActionItemLocked(item, sessionId: sessionId)
        } catch {
            reportError("saveActionItem")
        }
    }

    public func saveActionItems(_ items: [ActionItemState], sessionId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        do {
            for item in items {
                try saveActionItemLocked(item, sessionId: sessionId)
            }
        } catch {
            reportError("saveActionItems")
        }
    }

    public func updateActionItemDone(id: UUID, isDone: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let sql = "UPDATE action_items SET is_done = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isDone ? 1 : 0)
            bindText(stmt, 2, id.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                reportError("updateActionItemDone")
            }
        }
    }

    public func fetchActionItems(sessionId: UUID) -> [ActionItemState] {
        lock.lock()
        defer { lock.unlock() }
        return fetchActionItemsLocked(sessionId: sessionId)
    }

    public func deleteActionItem(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let sql = "DELETE FROM action_items WHERE id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            if sqlite3_step(stmt) != SQLITE_DONE {
                reportError("deleteActionItem")
            }
        }
    }
    
    /// Retention: remove sessions that never captured an utterance.
    /// - Parameters:
    ///   - includingOpen: at launch, stale open sessions from a previous
    ///     process are junk too; pass `false` to keep an in-progress session.
    ///   - keeping: session to protect even when it has no utterances yet.
    @discardableResult
    public func deleteEmptySessions(includingOpen: Bool = true, keeping: UUID? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var sql = "DELETE FROM sessions WHERE "
        if !includingOpen {
            sql += "end_time IS NOT NULL AND "
        }
        if keeping != nil {
            sql += "id != ? AND "
        }
        sql += """
        NOT EXISTS (
            SELECT 1 FROM utterances WHERE utterances.session_id = sessions.id
        );
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            reportError("deleteEmptySessions prepare")
            sqlite3_finalize(stmt)
            return 0
        }
        if let keeping {
            bindText(stmt, 1, keeping.uuidString)
        }
        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        guard rc == SQLITE_DONE else {
            reportError("deleteEmptySessions")
            return 0
        }
        return Int(sqlite3_changes(db))
    }

    /// Standalone dictation retention: remove all utterances not tied to a meeting session.
    @discardableResult
    public func deleteStandaloneDictations() -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return 0 }
        let sql = "DELETE FROM utterances WHERE session_id IS NULL;"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            reportError("deleteStandaloneDictations")
            return 0
        }
        return Int(sqlite3_changes(db))
    }

    public func checkpointWAL() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var logSize: Int32 = 0
        var framesCheckpointed: Int32 = 0
        let rc = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, &logSize, &framesCheckpointed)
        if rc != SQLITE_OK {
            reportError("WAL checkpoint")
        }
    }
    
    // MARK: - Asynchronous Background Wrappers
    
    public func saveSessionAsync(_ session: MeetingSession) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.saveSession(session)
                continuation.resume()
            }
        }
    }
    
    public func saveUtteranceAsync(_ segment: TranscriptSegment, sessionId: UUID? = nil, isDictation: Bool = false) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.saveUtterance(segment, sessionId: sessionId, isDictation: isDictation)
                continuation.resume()
            }
        }
    }
    
    /// Persist session metadata and utterance atomically in a single SQLite transaction.
    @discardableResult
    public func saveSessionAndUtteranceAsync(
        _ session: MeetingSession,
        segment: TranscriptSegment,
        isDictation: Bool
    ) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                do {
                    try self.saveSessionAndUtterance(session, segment: segment, isDictation: isDictation)
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    @discardableResult
    public func deleteStandaloneDictationsAsync() async -> Int {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                let removed = self.deleteStandaloneDictations()
                if removed > 0 {
                    self.checkpointWAL()
                }
                continuation.resume(returning: removed)
            }
        }
    }

    public func deleteSessionAsync(id: UUID) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.deleteSession(id: id)
                continuation.resume()
            }
        }
    }

    /// Prune empty sessions and compact the WAL in one background hop.
    @discardableResult
    public func deleteEmptySessionsAsync(includingOpen: Bool = true, keeping: UUID? = nil) async -> Int {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                let removed = self.deleteEmptySessions(includingOpen: includingOpen, keeping: keeping)
                if removed > 0 {
                    self.checkpointWAL()
                }
                continuation.resume(returning: removed)
            }
        }
    }

    public func fetchRecentSessionsAsync(limit: Int = 20) async -> [MeetingSession] {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                let sessions = self.fetchRecentSessions(limit: limit)
                continuation.resume(returning: sessions)
            }
        }
    }
    
    public func fetchSessionAsync(id: UUID) async -> MeetingSession? {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                let session = self.fetchSession(id: id)
                continuation.resume(returning: session)
            }
        }
    }

    public func fetchUtterancesAsync(sessionId: UUID) async -> [TranscriptSegment] {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                let utterances = self.fetchUtterances(sessionId: sessionId)
                continuation.resume(returning: utterances)
            }
        }
    }

    public func saveActionItemAsync(_ item: ActionItemState, sessionId: UUID) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.saveActionItem(item, sessionId: sessionId)
                continuation.resume()
            }
        }
    }

    public func saveActionItemsAsync(_ items: [ActionItemState], sessionId: UUID) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.saveActionItems(items, sessionId: sessionId)
                continuation.resume()
            }
        }
    }

    public func updateActionItemDoneAsync(id: UUID, isDone: Bool) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.updateActionItemDone(id: id, isDone: isDone)
                continuation.resume()
            }
        }
    }

    public func fetchActionItemsAsync(sessionId: UUID) async -> [ActionItemState] {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                let items = self.fetchActionItems(sessionId: sessionId)
                continuation.resume(returning: items)
            }
        }
    }

    public func deleteActionItemAsync(id: UUID) async {
        await withCheckedContinuation { continuation in
            dbQueue.async {
                self.deleteActionItem(id: id)
                continuation.resume()
            }
        }
    }
    
    public func fetchSession(id: UUID) -> MeetingSession? {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT id, title, start_time, end_time, summary_markdown FROM sessions WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var result: MeetingSession? = nil
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let titleCString = sqlite3_column_text(stmt, 1) {
                    let title = String(cString: titleCString)
                    let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                    var endTime: Date? = nil
                    if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                        endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                    }
                    var summary: String? = nil
                    if let sumCString = sqlite3_column_text(stmt, 4) {
                        summary = String(cString: sumCString)
                    }
                    let actionItems = fetchActionItemsLocked(sessionId: id)
                    result = MeetingSession(
                        id: id,
                        title: title,
                        startTime: startTime,
                        endTime: endTime,
                        segments: [],
                        summaryMarkdown: summary,
                        actionItems: actionItems
                    )
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    public func fetchRecentSessions(limit: Int = 20) -> [MeetingSession] {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT id, title, start_time, end_time, summary_markdown FROM sessions ORDER BY start_time DESC LIMIT ?;"
        var stmt: OpaquePointer?
        var results: [MeetingSession] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let titleCString = sqlite3_column_text(stmt, 1) else {
                    continue
                }
                
                let idStr = String(cString: idCString)
                let title = String(cString: titleCString)
                let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                
                var endTime: Date? = nil
                if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                    endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                }
                
                var summary: String? = nil
                if let sumCString = sqlite3_column_text(stmt, 4) {
                    summary = String(cString: sumCString)
                }
                
                if let uuid = UUID(uuidString: idStr) {
                    results.append(MeetingSession(
                        id: uuid,
                        title: title,
                        startTime: startTime,
                        endTime: endTime,
                        segments: [],
                        summaryMarkdown: summary
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    public func fetchUtterances(sessionId: UUID) -> [TranscriptSegment] {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT id, speaker, timestamp, text, duration_seconds FROM utterances WHERE session_id = ? ORDER BY timestamp ASC;"
        var stmt: OpaquePointer?
        var results: [TranscriptSegment] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, sessionId.uuidString)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let speakerCString = sqlite3_column_text(stmt, 1),
                      let textCString = sqlite3_column_text(stmt, 3) else {
                    continue
                }
                
                let idStr = String(cString: idCString)
                let speakerStr = String(cString: speakerCString)
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                let text = String(cString: textCString)
                let duration = sqlite3_column_double(stmt, 4)
                
                let track: SpeakerTrack = (speakerStr == "you") ? .you : .meeting
                if let uuid = UUID(uuidString: idStr) {
                    results.append(TranscriptSegment(
                        id: uuid,
                        speaker: track,
                        timestamp: timestamp,
                        text: text,
                        durationSeconds: duration
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    public func fetchRecentDictations(limit: Int = 30) -> [TranscriptSegment] {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT id, speaker, timestamp, text, duration_seconds FROM utterances WHERE is_dictation = 1 ORDER BY timestamp DESC LIMIT ?;"
        var stmt: OpaquePointer?
        var results: [TranscriptSegment] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let textCString = sqlite3_column_text(stmt, 3) else {
                    continue
                }
                
                let idStr = String(cString: idCString)
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                let text = String(cString: textCString)
                let duration = sqlite3_column_double(stmt, 4)
                
                if let uuid = UUID(uuidString: idStr) {
                    results.append(TranscriptSegment(
                        id: uuid,
                        speaker: .you,
                        timestamp: timestamp,
                        text: text,
                        durationSeconds: duration
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    // MARK: - Dictionary & Word Memory
    
    @discardableResult
    public func saveOrIncrementDictionaryWord(
        raw: String,
        preferred: String,
        caseSensitive: Bool = false
    ) -> DictionaryEntry {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPref = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date().timeIntervalSince1970
        let newId = UUID()
        
        let sql = """
        INSERT INTO dictionary (id, raw_pattern, preferred_replacement, frequency, case_sensitive, created_at, updated_at)
        VALUES (?, ?, ?, 1, ?, ?, ?)
        ON CONFLICT(raw_pattern) DO UPDATE SET
            preferred_replacement = excluded.preferred_replacement,
            frequency = frequency + 1,
            case_sensitive = excluded.case_sensitive,
            updated_at = excluded.updated_at;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, newId.uuidString)
            bindText(stmt, 2, trimmedRaw)
            bindText(stmt, 3, trimmedPref)
            sqlite3_bind_int(stmt, 4, caseSensitive ? 1 : 0)
            sqlite3_bind_double(stmt, 5, now)
            sqlite3_bind_double(stmt, 6, now)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                reportError("dictionary upsert")
            }
        }
        sqlite3_finalize(stmt)
        
        // Read back the persisted row: on conflict the upsert updates an existing
        // row, so the freshly generated UUID and frequency above can be stale.
        if let stored = fetchDictionaryEntryLocked(rawPattern: trimmedRaw) {
            return stored
        }
        
        return DictionaryEntry(
            id: newId,
            rawPattern: trimmedRaw,
            preferredReplacement: trimmedPref,
            frequency: 1,
            caseSensitive: caseSensitive,
            createdAt: Date(timeIntervalSince1970: now),
            updatedAt: Date(timeIntervalSince1970: now)
        )
    }
    
    /// Assumes the caller already holds `lock`.
    private func fetchDictionaryEntryLocked(rawPattern: String) -> DictionaryEntry? {
        let sql = "SELECT id, raw_pattern, preferred_replacement, frequency, case_sensitive, created_at, updated_at FROM dictionary WHERE raw_pattern = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var result: DictionaryEntry?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, rawPattern)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = dictionaryEntry(from: stmt)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    private func dictionaryEntry(from stmt: OpaquePointer?) -> DictionaryEntry? {
        guard let idCString = sqlite3_column_text(stmt, 0),
              let rawCString = sqlite3_column_text(stmt, 1),
              let prefCString = sqlite3_column_text(stmt, 2),
              let uuid = UUID(uuidString: String(cString: idCString)) else {
            return nil
        }
        
        return DictionaryEntry(
            id: uuid,
            rawPattern: String(cString: rawCString),
            preferredReplacement: String(cString: prefCString),
            frequency: Int(sqlite3_column_int(stmt, 3)),
            caseSensitive: sqlite3_column_int(stmt, 4) == 1,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        )
    }
    
    public func fetchDictionaryEntries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT id, raw_pattern, preferred_replacement, frequency, case_sensitive, created_at, updated_at FROM dictionary ORDER BY frequency DESC, updated_at DESC;"
        var stmt: OpaquePointer?
        var results: [DictionaryEntry] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let entry = dictionaryEntry(from: stmt) {
                    results.append(entry)
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    public func deleteDictionaryEntry(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "DELETE FROM dictionary WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
}
