import Foundation
import Combine

public struct MeetingNotes: Equatable, Sendable {
    public var decisions: [String]
    public var actionItems: [String]
    
    public init(decisions: [String] = [], actionItems: [String] = []) {
        self.decisions = decisions
        self.actionItems = actionItems
    }
}

public enum MeetingNotesExtractor {
    
    // Indicators marking decisions and agreements (sorted by length descending)
    private static let rawDecisionTriggers: [String] = [
        "moving forward with",
        "the plan is to",
        "let's go with",
        "let us go with",
        "we will go with",
        "we'll go with",
        "we decided that",
        "we decided to",
        "we agreed that",
        "we agreed to",
        "decision is to",
        "resolved that",
        "resolved to",
        "consensus is",
        "locked in as",
        "decided that",
        "decided to",
        "decision is",
        "settled on",
        "agreed on",
        "agreed to",
        "locked as",
        "we decided",
        "we agreed",
        "approved"
    ]
    
    // Indicators marking commitments, follow-ups, and action items (sorted by length descending)
    private static let rawActionTriggers: [String] = [
        "don't forget to",
        "next step is to",
        "will investigate",
        "please ensure",
        "follow up with",
        "make sure to",
        "follow up on",
        "next step is",
        "action item:",
        "should create",
        "should build",
        "will update",
        "will deploy",
        "action item",
        "assigned to",
        "let's verify",
        "let's check",
        "we need to",
        "let's test",
        "will fix",
        "need to",
        "we will",
        "to do:",
        "i will",
        "we'll",
        "i'll"
    ]
    
    private struct TriggerPattern: @unchecked Sendable {
        let trigger: String
        let regex: NSRegularExpression
    }
    
    private static func compilePatterns(from triggers: [String]) -> [TriggerPattern] {
        // Sort descending by length so longer specific triggers take precedence over short ones
        let sorted = triggers.sorted { $0.count > $1.count }
        return sorted.compactMap { trigger in
            let start = trigger.first?.isLetter == true || trigger.first?.isNumber == true ? "\\b" : ""
            let end = trigger.last?.isLetter == true || trigger.last?.isNumber == true ? "\\b" : ""
            let pattern = "\(start)\(NSRegularExpression.escapedPattern(for: trigger))\(end)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return TriggerPattern(trigger: trigger, regex: regex)
        }
    }
    
    private static let compiledDecisionPatterns: [TriggerPattern] = compilePatterns(from: rawDecisionTriggers)
    private static let compiledActionPatterns: [TriggerPattern] = compilePatterns(from: rawActionTriggers)
    
    private static let negationRegex: NSRegularExpression = {
        let pattern = "\\b(not|never|didn't|did not|don't|do not|won't|will not|cannot|can't|haven't|have not|hasn't|has not|wouldn't|would not|refused)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
    
    /// Extract key decisions and agreements from meeting utterances
    public static func extractDecisions(from segments: [TranscriptSegment], limit: Int = 30) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        
        for segment in segments {
            if results.count >= limit { break }
            let sentences = splitIntoSentences(segment.text)
            for sentence in sentences {
                if results.count >= limit { break }
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 8 else { continue }
                
                let nsString = trimmed as NSString
                let fullRange = NSRange(location: 0, length: nsString.length)
                
                for item in compiledDecisionPatterns {
                    if let match = item.regex.firstMatch(in: trimmed, options: [], range: fullRange) {
                        // Check if the clause before the trigger contains explicit negation
                        let prefixRange = NSRange(location: 0, length: match.range.location)
                        if item.trigger.lowercased() != "refused to" && negationRegex.firstMatch(in: trimmed, options: [], range: prefixRange) != nil {
                            // Negated trigger (e.g. "We have not decided on...", "They never agreed to...")
                            break
                        }
                        
                        let candidate: String
                        let afterIndex = match.range.location + match.range.length
                        let afterString = nsString.substring(from: afterIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Guard against passive voice / dangling fragments:
                        // e.g. "The design was approved by legal" -> afterString is "by legal."
                        // e.g. "approved" with short tail (< 3 words)
                        let afterWords = afterString.split(whereSeparator: { $0.isWhitespace })
                        if afterString.lowercased().hasPrefix("by ") || afterWords.count < 3 {
                            candidate = cleanSentence(trimmed)
                        } else {
                            candidate = cleanSentence(afterString)
                        }
                        
                        let key = candidate.lowercased()
                        if !seen.contains(key) && !candidate.isEmpty {
                            seen.insert(key)
                            results.append(candidate)
                        }
                        break
                    }
                }
            }
        }
        return results
    }
    
    /// Extract actionable tasks and commitments from meeting utterances
    public static func extractActionItems(from segments: [TranscriptSegment], limit: Int = 30) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        
        for segment in segments {
            if results.count >= limit { break }
            let sentences = splitIntoSentences(segment.text)
            for sentence in sentences {
                if results.count >= limit { break }
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 6 else { continue }
                
                let nsString = trimmed as NSString
                let fullRange = NSRange(location: 0, length: nsString.length)
                
                for item in compiledActionPatterns {
                    if let match = item.regex.firstMatch(in: trimmed, options: [], range: fullRange) {
                        // Check if the clause before the trigger contains negation (e.g. "We will not...", "I don't think we need to...")
                        let prefixRange = NSRange(location: 0, length: match.range.location)
                        if item.trigger.lowercased() != "don't forget to" && negationRegex.firstMatch(in: trimmed, options: [], range: prefixRange) != nil {
                            break
                        }
                        
                        let afterIndex = match.range.location + match.range.length
                        let afterString = nsString.substring(from: afterIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                        let lowerAfter = afterString.lowercased()
                        if lowerAfter.hasPrefix("not ") || lowerAfter.hasPrefix("never ") {
                            break
                        }
                        
                        let candidate: String
                        let afterWords = afterString.split(whereSeparator: { $0.isWhitespace })
                        
                        if afterWords.count >= 2 {
                            candidate = cleanSentence(afterString)
                        } else {
                            candidate = cleanSentence(trimmed)
                        }
                        
                        let key = candidate.lowercased()
                        if !seen.contains(key) && !candidate.isEmpty {
                            seen.insert(key)
                            results.append(candidate)
                        }
                        break
                    }
                }
            }
        }
        return results
    }
    
    public static func extractAll(from segments: [TranscriptSegment], limit: Int = 30) -> MeetingNotes {
        return MeetingNotes(
            decisions: extractDecisions(from: segments, limit: limit),
            actionItems: extractActionItems(from: segments, limit: limit)
        )
    }
    
    /// Formats extracted decisions and action items into a clean Markdown document
    public static func formatMarkdown(title: String, decisions: [String], actionItems: [ActionItemState]) -> String {
        var md = "## \(title) — Notes\n\n"
        
        if !decisions.isEmpty {
            md += "### Key Decisions\n"
            for d in decisions {
                md += "- \(d)\n"
            }
            md += "\n"
        }
        
        if !actionItems.isEmpty {
            md += "### Action Items\n"
            for item in actionItems {
                md += "- [\(item.isDone ? "x" : " ")] \(item.text)\n"
            }
            md += "\n"
        }
        
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Tokenize text into natural sentences using Foundation's linguistic analyzer
    public static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return sentences
    }
    
    private static func cleanSentence(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: " :-—,\t\n"))
        guard !cleaned.isEmpty else { return "" }
        
        // Capitalize first character
        let first = cleaned.prefix(1).uppercased()
        cleaned = first + cleaned.dropFirst()
        
        // Ensure trailing period
        if !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") && !cleaned.hasSuffix("?") {
            cleaned.append(".")
        }
        return cleaned
    }
}

/// Owned by the meeting coordinator. Live callers pass only segments that changed.
public final class IncrementalNotesExtractor: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionID: UUID?
    private var entries: [UUID: (segment: TranscriptSegment, notes: MeetingNotes)] = [:]
    private var notes = MeetingNotes()
    private var decisionSet = Set<String>()
    private var actionSet = Set<String>()
    private var lastTimestamp: Date?
    struct Change {
        let sessionID: UUID
        let rebuilt: Bool
        let addedActions: [String]
    }
    let changes = PassthroughSubject<Change, Never>()

    public init() {}

    public func reset(for sessionID: UUID? = nil) {
        lock.withLock { clear(for: sessionID) }
    }

    private func clear(for sessionID: UUID?) {
        self.sessionID = sessionID
        entries.removeAll()
        notes = MeetingNotes()
        lastTimestamp = nil
        decisionSet.removeAll()
        actionSet.removeAll()
    }

    private func add(_ extracted: MeetingNotes) {
        for text in extracted.decisions where decisionSet.insert(text.lowercased()).inserted {
            notes.decisions.append(text)
        }
        for text in extracted.actionItems where actionSet.insert(text.lowercased()).inserted {
            notes.actionItems.append(text)
        }
    }

    @discardableResult
    public func update(segments: [TranscriptSegment], for id: UUID) -> (decisions: [String], newActionTexts: [String]) {
        var changed = false
        var rebuilt = false
        let result = lock.withLock { () -> ([String], [String]) in
            if sessionID != id { clear(for: id) }
            let initialCount = notes.actionItems.count
            var rebuild = false
            var addedKeys = Set<String>()
            for segment in segments {
                let previous = entries[segment.id]
                if previous?.segment == segment { continue }
                let extracted = MeetingNotesExtractor.extractAll(from: [segment], limit: Int.max)
                entries[segment.id] = (segment, extracted)
                if previous != nil || (lastTimestamp.map { segment.timestamp < $0 } == true && extracted != MeetingNotes()) {
                    rebuild = true
                }
                lastTimestamp = max(segment.timestamp, lastTimestamp ?? segment.timestamp)
                if !rebuild {
                    let before = (notes.decisions.count, notes.actionItems.count)
                    add(extracted)
                    for text in notes.actionItems.dropFirst(before.1) { addedKeys.insert(text.lowercased()) }
                    changed = changed || before != (notes.decisions.count, notes.actionItems.count)
                }
            }
            if rebuild {
                let oldActions = actionSet.subtracting(addedKeys)
                notes = MeetingNotes()
                decisionSet.removeAll()
                actionSet.removeAll()
                for entry in entries.values.sorted(by: {
                    ($0.segment.timestamp, $0.segment.id.uuidString) < ($1.segment.timestamp, $1.segment.id.uuidString)
                }) { add(entry.notes) }
                changed = true
                rebuilt = true
                return (notes.decisions, notes.actionItems.filter { !oldActions.contains($0.lowercased()) })
            }
            return (notes.decisions, Array(notes.actionItems.dropFirst(initialCount)))
        }
        if changed { changes.send(Change(sessionID: id, rebuilt: rebuilt, addedActions: result.1)) }
        return result
    }

    public var snapshot: MeetingNotes { lock.withLock { notes } }
    public var decisions: [String] { snapshot.decisions }
    public var actionTexts: [String] { snapshot.actionItems }
}
