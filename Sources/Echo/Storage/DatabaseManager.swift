import Foundation
import SQLite3

public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let dbPath: String
    
    public init(customPath: String? = nil) {
        if let path = customPath {
            self.dbPath = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let echoDir = appSupport.appendingPathComponent("Echo", isDirectory: true)
            try? FileManager.default.createDirectory(at: echoDir, withIntermediateDirectories: true)
            self.dbPath = echoDir.appendingPathComponent("echo.sqlite").path
        }
        
        openDatabase()
        createTables()
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Lifecycle & Initialization
    
    private func openDatabase() {
        lock.lock()
        defer { lock.unlock() }
        
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            // Enable WAL mode for high concurrency & performance
            sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
            return
        }
        
        // Sandbox fallback to local workspace data directory
        let fallbackPath = "/Users/ragavij/Documents/Developer/Echo/data/echo.sqlite"
        let fallbackDir = URL(fileURLWithPath: "/Users/ragavij/Documents/Developer/Echo/data")
        try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        
        if sqlite3_open(fallbackPath, &db) == SQLITE_OK {
            sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
            print("Echo DatabaseManager: Initialized at workspace fallback: \(fallbackPath)")
        } else {
            print("Echo DatabaseManager: Failed to open SQLite DB at \(dbPath) or \(fallbackPath)")
        }
    }
    
    private func createTables() {
        lock.lock()
        defer { lock.unlock() }
        
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
            is_dictation INTEGER NOT NULL DEFAULT 0
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
        
        CREATE INDEX IF NOT EXISTS idx_dictionary_pattern ON dictionary(raw_pattern);
        """
        
        if sqlite3_exec(db, schemaSQL, nil, nil, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("Echo DatabaseManager: Table creation error: \(errMsg)")
        }
    }
    
    // MARK: - Sessions & Utterances
    
    public func saveSession(_ session: MeetingSession) {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
        INSERT INTO sessions (id, title, start_time, end_time, summary_markdown, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            end_time = excluded.end_time,
            summary_markdown = excluded.summary_markdown;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let idStr = session.id.uuidString
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (session.title as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 3, session.startTime.timeIntervalSince1970)
            
            if let end = session.endTime {
                sqlite3_bind_double(stmt, 4, end.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            if let summary = session.summaryMarkdown {
                sqlite3_bind_text(stmt, 5, (summary as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            
            sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
            
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    public func saveUtterance(_ segment: TranscriptSegment, sessionId: UUID? = nil, isDictation: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = """
        INSERT INTO utterances (id, session_id, speaker, timestamp, text, duration_seconds, is_dictation)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            text = excluded.text;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let idStr = segment.id.uuidString
            sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
            
            if let sid = sessionId {
                sqlite3_bind_text(stmt, 2, (sid.uuidString as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            
            let speakerStr = segment.speaker == .you ? "you" : "meeting"
            sqlite3_bind_text(stmt, 3, (speakerStr as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 4, segment.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 5, (segment.text as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 6, segment.durationSeconds)
            sqlite3_bind_int(stmt, 7, isDictation ? 1 : 0)
            
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
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
            sqlite3_bind_text(stmt, 1, (sessionId.uuidString as NSString).utf8String, -1, nil)
            
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
            sqlite3_bind_text(stmt, 1, (newId.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (trimmedRaw as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (trimmedPref as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, caseSensitive ? 1 : 0)
            sqlite3_bind_double(stmt, 5, now)
            sqlite3_bind_double(stmt, 6, now)
            
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
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
    
    public func fetchDictionaryEntries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        
        let sql = "SELECT id, raw_pattern, preferred_replacement, frequency, case_sensitive, created_at, updated_at FROM dictionary ORDER BY frequency DESC, updated_at DESC;"
        var stmt: OpaquePointer?
        var results: [DictionaryEntry] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let rawCString = sqlite3_column_text(stmt, 1),
                      let prefCString = sqlite3_column_text(stmt, 2) else {
                    continue
                }
                
                let idStr = String(cString: idCString)
                let raw = String(cString: rawCString)
                let pref = String(cString: prefCString)
                let freq = Int(sqlite3_column_int(stmt, 3))
                let caseSens = sqlite3_column_int(stmt, 4) == 1
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                
                if let uuid = UUID(uuidString: idStr) {
                    results.append(DictionaryEntry(
                        id: uuid,
                        rawPattern: raw,
                        preferredReplacement: pref,
                        frequency: freq,
                        caseSensitive: caseSens,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    ))
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
            sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
}
