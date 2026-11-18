import SwiftUI

@MainActor
public final class WordMemoryState: ObservableObject {
    public static let shared = WordMemoryState()
    
    @Published public var isVisible: Bool = false
    @Published public var newRawWord: String = ""
    @Published public var newPreferredWord: String = ""
    @Published public var entries: [DictionaryEntry] = []
    
    public init() {
        self.entries = WordMemoryEngine.shared.allEntries()
    }
    
    public func reload() {
        DispatchQueue.main.async {
            self.entries = WordMemoryEngine.shared.allEntries()
        }
    }
    
    public func add() {
        let raw = newRawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let pref = newPreferredWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !pref.isEmpty else { return }
        
        WordMemoryEngine.shared.remember(raw: raw, preferred: pref)
        newRawWord = ""
        newPreferredWord = ""
        reload()
    }
    
    public func delete(id: UUID) {
        WordMemoryEngine.shared.delete(id: id)
        reload()
    }
}
