import Foundation

public struct TranscriptionResponse: Codable, Sendable {
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
}

public enum PhononClientError: LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case processError(statusCode: Int, message: String)
    case decodingError(String)
    case audioFileNotFound(String)
    case executableNotFound(String)
    case processTimedOut(TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Phonon API endpoint URL."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .serverError(let code, let msg):
            return "Server responded with HTTP \(code): \(msg)"
        case .processError(let code, let msg):
            return "Speech process exited with status \(code): \(msg)"
        case .decodingError(let msg):
            return "Failed to decode response: \(msg)"
        case .audioFileNotFound(let path):
            return "Audio file not found at path: \(path)"
        case .executableNotFound(let detail):
            return "Speech engine not found: \(detail)"
        case .processTimedOut(let seconds):
            return "Speech engine timed out after \(Int(seconds))s."
        }
    }
}
