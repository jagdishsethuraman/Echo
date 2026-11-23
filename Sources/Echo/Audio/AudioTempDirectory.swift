import Foundation

/// Owns private audio scratch files and reclaims directories only after their owner exits.
public enum AudioTempDirectory {
    private static let lock = NSLock()
    private static let processID = ProcessInfo.processInfo.processIdentifier
    // Give each run a unique directory. Older Echo versions ignore this prefix.
    private static let processDirectoryName = "echo_pid_\(processID)_\(UUID().uuidString)"

    public static var rootURL: URL {
        if let configuredRoot = ProcessInfo.processInfo.environment["ECHO_AUDIO_ROOT"], !configuredRoot.isEmpty {
            return URL(fileURLWithPath: configuredRoot, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Echo/tmp_audio", isDirectory: true)
    }

    public static var currentProcessDirectory: URL {
        let root = rootURL
        let directory = processDirectory(in: root)
        try? prepareDirectory(directory, in: root)
        return directory
    }

    public static func createTempWAVURL(prefix: String = "echo_audio") -> URL {
        currentProcessDirectory.appendingPathComponent("\(prefix)_\(UUID().uuidString).wav")
    }

    @discardableResult
    public static func writeTempWAV(data: Data, prefix: String = "echo_audio") throws -> URL {
        try writeTempWAV(data: data, prefix: prefix, root: nil)
    }

    static func writeTempWAV(data: Data, prefix: String, root: URL?) throws -> URL {
        let root = root ?? rootURL
        let directory = processDirectory(in: root)
        try prepareDirectory(directory, in: root)
        let url = directory.appendingPathComponent("\(prefix)_\(UUID().uuidString).wav")
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            try? fileManager.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
        return url
    }

    private static func processDirectory(in root: URL) -> URL {
        root.appendingPathComponent(processDirectoryName, isDirectory: true)
    }

    private static func prepareDirectory(_ directory: URL, in root: URL) throws {
        try lock.withLock {
            for path in [root, directory] {
                try FileManager.default.createDirectory(
                    at: path,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            }
        }
    }

    public static func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno != ESRCH
    }

    public static func sweepOrphanedAudioFiles() {
        sweepOrphanedAudioFiles(in: rootURL)
    }

    static func sweepOrphanedAudioFiles(in root: URL) {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else {
            return
        }
        // Loose WAVs from older versions have no ownership information.
        for entry in entries {
            guard let pid = ownerPID(of: entry.lastPathComponent),
                  let values = try? entry.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink == false,
                  !isProcessAlive(pid: pid) else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func ownerPID(of directoryName: String) -> Int32? {
        let parts = directoryName.split(separator: "_", omittingEmptySubsequences: false)
        let candidate: Substring
        if parts.count == 4, parts[0] == "echo", parts[1] == "pid", UUID(uuidString: String(parts[3])) != nil {
            candidate = parts[2]
        } else if parts.count == 2, parts[0] == "pid" {
            candidate = parts[1]
        } else {
            return nil
        }
        guard let pid = Int32(candidate), pid > 0, String(pid) == candidate else { return nil }
        return pid
    }

    /// Call after inference has drained during graceful termination.
    public static func cleanupCurrentProcess() {
        try? FileManager.default.removeItem(at: processDirectory(in: rootURL))
    }
}
