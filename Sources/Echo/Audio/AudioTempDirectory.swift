import Foundation

/// Centralized manager for temporary audio files with strict POSIX permissions (0700 dir, 0600 files)
/// and automated cleanup/sweep of orphaned audio captures on launch and shutdown.
public enum AudioTempDirectory {
    private static let lock = NSLock()

    /// Root URL for audio capture scratchpad in Application Support (fallback to NSTemporaryDirectory)
    public static var rootURL: URL {
        lock.lock()
        defer { lock.unlock() }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Echo/tmp_audio", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        return dir
    }

    /// Generate a unique temporary WAV URL
    public static func createTempWAVURL(prefix: String = "echo_audio") -> URL {
        return rootURL.appendingPathComponent("\(prefix)_\(UUID().uuidString).wav")
    }

    /// Safely write audio data to a temporary WAV with restricted 0600 permissions
    @discardableResult
    public static func writeTempWAV(data: Data, prefix: String = "echo_audio") throws -> URL {
        let url = createTempWAVURL(prefix: prefix)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// Sweeps orphaned audio files left behind by crashes or ungraceful exits
    public static func sweepOrphanedAudioFiles() {
        let fileManager = FileManager.default

        // 1. Sweep Application Support tmp_audio
        let dir = rootURL
        if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "wav" {
                try? fileManager.removeItem(at: file)
            }
        }

        // 2. Sweep legacy NSTemporaryDirectory echo_*.wav captures
        let sysTemp = fileManager.temporaryDirectory
        if let legacyFiles = try? fileManager.contentsOfDirectory(at: sysTemp, includingPropertiesForKeys: nil) {
            for file in legacyFiles where file.lastPathComponent.hasPrefix("echo_") && file.pathExtension.lowercased() == "wav" {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
