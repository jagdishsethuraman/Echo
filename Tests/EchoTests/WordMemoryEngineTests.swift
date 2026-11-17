import Foundation
import Testing
@testable import Echo

@Suite("WordMemoryEngine", .serialized)
struct WordMemoryEngineTests {
    private func makeEngine() -> (engine: WordMemoryEngine, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-memory-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = DatabaseManager(customPath: directory.appendingPathComponent("echo.sqlite").path)
        return (WordMemoryEngine(database: database), directory)
    }
    
    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test func seedsDefaultVocabulary() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        let entries = engine.allEntries()
        #expect(entries.count >= 10)
        #expect(entries.contains { $0.rawPattern == "phone on" && $0.preferredReplacement == "Phonon" })
        #expect(entries.contains { $0.rawPattern == "antigravity" })
    }
    
    @Test func emptyInputIsReturnedUnchanged() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        #expect(engine.sanitize("") == "")
    }
    
    @Test func replacesWholeWordsCaseInsensitively() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        #expect(engine.sanitize("PHONE ON tomorrow") == "Phonon tomorrow")
        #expect(engine.sanitize("use the Phone on feature") == "use the Phonon feature")
    }
    
    @Test func doesNotReplaceSubstrings() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        // The pattern must match on word boundaries, not inside longer words.
        #expect(engine.sanitize("phononophone") == "phononophone")
        #expect(engine.sanitize("xantigravity") == "xantigravity")
    }
    
    @Test func longerPhrasesWinOverSubstrings() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        engine.remember(raw: "new york", preferred: "NYC")
        engine.remember(raw: "new", preferred: "fresh")
        
        #expect(engine.sanitize("new york and new ideas") == "NYC and fresh ideas")
    }
    
    @Test func respectsCaseSensitiveEntries() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        engine.remember(raw: "Echo", preferred: "ECHO", caseSensitive: true)
        
        #expect(engine.sanitize("echo Echo ECHO") == "echo ECHO ECHO")
    }
    
    @Test func rememberReloadsAndIncrementsFrequency() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        let first = engine.remember(raw: "zed", preferred: "Zed")
        #expect(first.frequency == 1)
        
        let second = engine.remember(raw: "zed", preferred: "Zed")
        #expect(second.frequency == 2)
        #expect(engine.allEntries().filter { $0.rawPattern == "zed" }.count == 1)
        
        #expect(engine.sanitize("zed") == "Zed")
    }
    
    @Test func deleteRemovesEntryAndStopsReplacement() {
        let (engine, directory) = makeEngine()
        defer { remove(directory) }
        
        let entry = engine.remember(raw: "quasar", preferred: "Quasar")
        #expect(engine.sanitize("quasar") == "Quasar")
        
        engine.delete(id: entry.id)
        #expect(engine.sanitize("quasar") == "quasar")
        #expect(!engine.allEntries().contains { $0.rawPattern == "quasar" })
    }
}
