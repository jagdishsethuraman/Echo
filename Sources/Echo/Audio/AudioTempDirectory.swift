import Foundation

/// Centralized manager for temporary audio files with strict POSIX permissions (0700 dir, 0600 files),
/// process-level directory isolation, and PID liveness verification to prevent sweeping live recordings.
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

    /// Process-isolated scratch directory, protecting live recordings from concurrent instances or self-tests.
    public static var currentProcessDirectory: URL {
        let pid = ProcessInfo.processInfo.processIdentifier
        let dir = rootURL.appendingPathComponent("pid_\(pid)", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir
    }

    /// Generate a unique temporary WAV URL inside the current process's isolated scratch directory.
    public static func createTempWAVURL(prefix: String = "echo_audio") -> URL {
        return currentProcessDirectory.appendingPathComponent("\(prefix)_\(UUID().uuidString).wav")
    }

    /// Safely write audio data to a temporary WAV with restricted 0600 permissions
    @discardableResult
    public static func writeTempWAV(data: Data, prefix: String = "echo_audio") throws -> URL {
        let url = createTempWAVURL(prefix: prefix)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// Determine if a process PID is currently alive on macOS.
    public static func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    /// Sweeps only truly orphaned audio files left behind by terminated processes.
    /// Preserves in-flight files belonging to active processes.
    public static func sweepOrphanedAudioFiles() {
        let fileManager = FileManager.default
        let currentPid = ProcessInfo.processInfo.processIdentifier

        // 1. Sweep process directories in Application Support tmp_audio
        let dir = rootURL
        if let items = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix("pid_") {
                    let pidString = String(name.dropFirst(4))
                    if let pid = Int32(pidString) {
                        // Protect own live process and any other active running Echo instance
                        if pid == currentPid || isProcessAlive(pid: pid) {
                            continue
                        }
                    }
                    try? fileManager.removeItem(at: item)
                } else if item.pathExtension.lowercased() == "wav" {
                    // Loose legacy files
                    try? fileManager.removeItem(at: item)
                }
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

    /// Clean up the current process's temporary directory upon graceful termination.
    public static func cleanupCurrentProcess() {
        let dir = currentProcessDirectory
        try? FileManager.default.removeItem(at: dir)
    }
}
