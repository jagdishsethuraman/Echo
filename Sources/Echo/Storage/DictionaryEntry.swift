import Foundation

public struct DictionaryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var rawPattern: String
    public var preferredReplacement: String
    public var frequency: Int
    public var caseSensitive: Bool
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        rawPattern: String,
        preferredReplacement: String,
        frequency: Int = 1,
        caseSensitive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.rawPattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredReplacement = preferredReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frequency = frequency
        self.caseSensitive = caseSensitive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
