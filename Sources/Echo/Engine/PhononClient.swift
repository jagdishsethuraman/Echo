import Foundation

public final class PhononClient: @unchecked Sendable {
    public let endpoint: URL
    private let session: URLSession
    
    public init(endpoint: URL = URL(string: "http://127.0.0.1:8010/v1/audio/transcriptions")!) {
        self.endpoint = endpoint
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }
    
    /// Transcribe raw WAV audio data
    public func transcribe(audioData: Data, filename: String = "audio.wav") async throws -> (text: String, latencyMs: Double) {
        let clock = ContinuousClock()
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("phonon-2\r\n".data(using: .utf8)!)
        
        // file parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // boundary end
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let start = clock.now
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PhononClientError.networkError(error.localizedDescription)
        }
        
        let duration = clock.now - start
        let latencyMs = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhononClientError.networkError("Invalid non-HTTP response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw PhononClientError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        do {
            let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return (text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines), latencyMs: latencyMs)
        } catch {
            // Check if server returned raw string or alternate schema
            if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
                return (text: rawString.trimmingCharacters(in: .whitespacesAndNewlines), latencyMs: latencyMs)
            }
            throw PhononClientError.decodingError(error.localizedDescription)
        }
    }
    
    /// Transcribe audio from a local file URL
    public func transcribe(fileURL: URL) async throws -> (text: String, latencyMs: Double) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PhononClientError.audioFileNotFound(fileURL.path)
        }
        let data = try Data(contentsOf: fileURL)
        return try await transcribe(audioData: data, filename: fileURL.lastPathComponent)
    }
}
