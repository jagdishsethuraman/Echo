import Foundation

public final class WordMemoryEngine: @unchecked Sendable {
    public static let shared = WordMemoryEngine()
    
    private let database: DatabaseManager
    private let lock = NSLock()
    private var entries: [DictionaryEntry] = []
    
    public init(database: DatabaseManager = .shared) {
        self.database = database
        reloadFromDatabase()
        seedDefaultsIfNeeded()
    }
    
    // MARK: - Cache & Database Sync
    
    public func reloadFromDatabase() {
        lock.lock()
        defer { lock.unlock() }
        
        let loaded = database.fetchDictionaryEntries()
        // Sort descending by raw pattern length so longer phrases match before substrings
        self.entries = loaded.sorted { $0.rawPattern.count > $1.rawPattern.count }
    }
    
    private func seedDefaultsIfNeeded() {
        lock.lock()
        let count = entries.count
        lock.unlock()
        
        guard count == 0 else { return }
        
        let defaults: [(raw: String, pref: String)] = [
            ("phone on", "Phonon"),
            ("phonon", "Phonon"),
            ("anti gravity", "Antigravity"),
            ("antigravity", "Antigravity"),
            ("para keet", "Parakeet"),
            ("parakeet", "Parakeet"),
            ("meetily", "Meetily"),
            ("bento", "Bento"),
            ("ragav", "Ragav"),
            ("swiss atelier", "Swiss Atelier")
        ]
        
        for item in defaults {
            database.saveOrIncrementDictionaryWord(raw: item.raw, preferred: item.pref)
        }
        
        reloadFromDatabase()
    }
    
    // MARK: - Core Sanitization / Replacement Engine
    
    /// Apply remembered vocabulary replacements to speech transcripts with word-boundary accuracy
    public func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        
        lock.lock()
        let currentEntries = entries
        lock.unlock()
        
        guard !currentEntries.isEmpty else { return text }
        
        var processed = text
        
        for entry in currentEntries {
            let escapedPattern = NSRegularExpression.escapedPattern(for: entry.rawPattern)
            // Use unicode word boundaries (\b) to avoid replacing sub-parts of larger words
            let regexPattern = "\\b\(escapedPattern)\\b"
            
            var options: NSRegularExpression.Options = []
            if !entry.caseSensitive {
                options.insert(.caseInsensitive)
            }
            
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: options) {
                let range = NSRange(location: 0, length: (processed as NSString).length)
                processed = regex.stringByReplacingMatches(
                    in: processed,
                    options: [],
                    range: range,
                    withTemplate: entry.preferredReplacement
                )
            }
        }
        
        return processed
    }
    
    // MARK: - Learning & Mutation
    
    @discardableResult
    public func remember(raw: String, preferred: String, caseSensitive: Bool = false) -> DictionaryEntry {
        let entry = database.saveOrIncrementDictionaryWord(
            raw: raw,
            preferred: preferred,
            caseSensitive: caseSensitive
        )
        reloadFromDatabase()
        return entry
    }
    
    public func delete(id: UUID) {
        database.deleteDictionaryEntry(id: id)
        reloadFromDatabase()
    }
    
    public func allEntries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
