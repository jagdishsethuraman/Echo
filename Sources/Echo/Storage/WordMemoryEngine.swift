import Foundation

public final class WordMemoryEngine: @unchecked Sendable {
    public static let shared = WordMemoryEngine()
    
    private let database: DatabaseManager
    private let lock = NSLock()
    private var entries: [DictionaryEntry] = []
    
    private struct CompiledEntry {
        let entry: DictionaryEntry
        let regex: NSRegularExpression
    }
    private var compiledEntries: [CompiledEntry] = []
    
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
        let sortedEntries = loaded.sorted { $0.rawPattern.count > $1.rawPattern.count }
        self.entries = sortedEntries
        
        var compiled: [CompiledEntry] = []
        for entry in sortedEntries {
            let escapedPattern = NSRegularExpression.escapedPattern(for: entry.rawPattern)
            let leadingBoundary = entry.rawPattern.first.map { $0.isLetter || $0.isNumber } == true ? "\\b" : ""
            let trailingBoundary = entry.rawPattern.last.map { $0.isLetter || $0.isNumber } == true ? "\\b" : ""
            let pattern = "\(leadingBoundary)\(escapedPattern)\(trailingBoundary)"
            
            var options: NSRegularExpression.Options = []
            if !entry.caseSensitive {
                options.insert(.caseInsensitive)
            }
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                compiled.append(CompiledEntry(entry: entry, regex: regex))
            }
        }
        self.compiledEntries = compiled
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
    
    /// Apply remembered vocabulary replacements to speech transcripts with word-boundary accuracy,
    /// precompiled pattern caching, template character escaping safety, and zero cascade.
    public func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        
        lock.lock()
        let items = compiledEntries
        lock.unlock()
        
        guard !items.isEmpty else { return text }
        
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        
        var claimedRanges: [NSRange] = []
        struct MatchReplacement {
            let range: NSRange
            let replacement: String
        }
        var replacements: [MatchReplacement] = []
        
        for item in items {
            let matches = item.regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                let range = match.range
                guard range.location != NSNotFound && range.length > 0 else { continue }
                
                // Prevent cascading: do not replace inside an already matched span
                let overlaps = claimedRanges.contains { existing in
                    NSIntersectionRange(existing, range).length > 0
                }
                
                if !overlaps {
                    claimedRanges.append(range)
                    replacements.append(MatchReplacement(range: range, replacement: item.entry.preferredReplacement))
                }
            }
        }
        
        guard !replacements.isEmpty else { return text }
        
        // Sort replacements in ascending text order for single-pass assembly
        replacements.sort { $0.range.location < $1.range.location }
        
        var result = ""
        var cursor = 0
        for item in replacements {
            if item.range.location > cursor {
                let subRange = NSRange(location: cursor, length: item.range.location - cursor)
                result += nsText.substring(with: subRange)
            }
            // Direct string literal insertion avoids regex template expansion ($1, \, &)
            result += item.replacement
            cursor = item.range.location + item.range.length
        }
        if cursor < nsText.length {
            let tailRange = NSRange(location: cursor, length: nsText.length - cursor)
            result += nsText.substring(with: tailRange)
        }
        
        return result
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
