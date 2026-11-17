import Foundation

public struct TranscriptionResponse: Codable, Sendable {
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
}

public struct BenchmarkResult: Sendable {
    public let audioDurationSeconds: Double
    public let roundTripTimeMs: Double
    public let realTimeFactor: Double
    public let transcript: String
    public let success: Bool
}

public enum PhononClientError: LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case audioFileNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Phonon API endpoint URL."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .serverError(let code, let msg):
            return "Server responded with HTTP \(code): \(msg)"
        case .decodingError(let msg):
            return "Failed to decode response: \(msg)"
        case .audioFileNotFound(let path):
            return "Audio file not found at path: \(path)"
        }
    }
}
