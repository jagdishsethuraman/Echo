import Foundation

public struct MeetingNotes: Equatable, Sendable {
    public var decisions: [String]
    public var actionItems: [String]
    
    public init(decisions: [String] = [], actionItems: [String] = []) {
        self.decisions = decisions
        self.actionItems = actionItems
    }
}

public enum MeetingNotesExtractor {
    
    // Indicators marking decisions and agreements
    private static let decisionTriggers: [String] = [
        "we decided to",
        "we decided that",
        "we decided",
        "decided to",
        "decided that",
        "decision is to",
        "decision is",
        "agreed to",
        "agreed on",
        "we agreed to",
        "we agreed that",
        "we agreed",
        "let's go with",
        "let us go with",
        "we will go with",
        "we'll go with",
        "approved",
        "consensus is",
        "moving forward with",
        "settled on",
        "locked in as",
        "locked as",
        "the plan is to",
        "resolved to",
        "resolved that"
    ]
    
    // Indicators marking commitments, follow-ups, and action items
    private static let actionTriggers: [String] = [
        "action item:",
        "action item",
        "i will",
        "i'll",
        "we will",
        "we'll",
        "we need to",
        "need to",
        "make sure to",
        "follow up on",
        "follow up with",
        "let's check",
        "let's verify",
        "let's test",
        "next step is to",
        "next step is",
        "to do:",
        "assigned to",
        "don't forget to",
        "please ensure",
        "should create",
        "should build",
        "will update",
        "will fix",
        "will deploy",
        "will investigate"
    ]
    
    /// Extract key decisions and agreements from meeting utterances
    public static func extractDecisions(from segments: [TranscriptSegment]) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        
        for segment in segments {
            let sentences = splitIntoSentences(segment.text)
            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 8 else { continue }
                let lower = trimmed.lowercased()
                
                for trigger in decisionTriggers {
                    if let range = lower.range(of: trigger) {
                        let candidate: String
                        let after = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        if after.count >= 6 {
                            candidate = cleanSentence(after)
                        } else {
                            candidate = cleanSentence(trimmed)
                        }
                        
                        let key = candidate.lowercased()
                        if !seen.contains(key) {
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
    public static func extractActionItems(from segments: [TranscriptSegment]) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        
        for segment in segments {
            let sentences = splitIntoSentences(segment.text)
            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 6 else { continue }
                let lower = trimmed.lowercased()
                
                for trigger in actionTriggers {
                    if let range = lower.range(of: trigger) {
                        let candidate: String
                        let after = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        if after.count >= 5 {
                            candidate = cleanSentence(after)
                        } else {
                            candidate = cleanSentence(trimmed)
                        }
                        
                        let key = candidate.lowercased()
                        if !seen.contains(key) {
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
    
    public static func extractAll(from segments: [TranscriptSegment]) -> MeetingNotes {
        return MeetingNotes(
            decisions: extractDecisions(from: segments),
            actionItems: extractActionItems(from: segments)
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
