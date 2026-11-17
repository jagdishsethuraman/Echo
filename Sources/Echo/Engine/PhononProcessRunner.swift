import Foundation

public final class PhononProcessRunner: @unchecked Sendable {
    public let fermionPath: String
    
    public init(fermionPath: String = "/Users/ragavij/Documents/Developer/phonon_test_env/bin/fermion") {
        self.fermionPath = fermionPath
    }
    
    public func transcribe(fileURL: URL) async throws -> (text: String, latencyMs: Double) {
        let clock = ContinuousClock()
        let start = clock.now
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fermionPath)
        process.arguments = ["transcribe", "phonon-2", fileURL.path]
        
        var env = ProcessInfo.processInfo.environment
        env["FERMION_DEVICE"] = "cpu"
        process.environment = env
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        process.waitUntilExit()
        
        let duration = clock.now - start
        let latencyMs = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        guard process.terminationStatus == 0 else {
            let errMsg = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
            throw PhononClientError.serverError(statusCode: Int(process.terminationStatus), message: errMsg)
        }
        
        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        return (text: output.trimmingCharacters(in: .whitespacesAndNewlines), latencyMs: latencyMs)
    }
}
