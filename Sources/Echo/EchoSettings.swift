import Foundation

/// Central place for user-configurable paths and resolved defaults.
///
/// Values can be overridden per user:
/// ```sh
/// defaults write com.ragavij.echo echo.fermionPath /path/to/fermion
/// defaults write com.ragavij.echo echo.exportDirectory /path/to/Obsidian/Meetings
/// ```
/// or through `ECHO_FERMION_PATH` when launching from a terminal.
public enum EchoSettings {
    public static let fermionPathDefaultsKey = "echo.fermionPath"
    public static let exportDirectoryDefaultsKey = "echo.exportDirectory"
    
    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.ragavij.echo"
    }
    
    // MARK: - Speech Engine
    
    /// Resolve the `fermion` executable.
    ///
    /// Resolution order: explicit user setting, `ECHO_FERMION_PATH`, a bundled
    /// resource, every directory in `PATH`, then the legacy development
    /// environment used by the original prototype.
    public static func resolveFermionPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        
        if let configured = UserDefaults.standard.string(forKey: fermionPathDefaultsKey),
           !configured.isEmpty {
            candidates.append(configured)
        }
        if let fromEnvironment = environment["ECHO_FERMION_PATH"], !fromEnvironment.isEmpty {
            candidates.append(fromEnvironment)
        }
        if let bundled = Bundle.main.url(forResource: "fermion", withExtension: nil)?.path {
            candidates.append(bundled)
        }
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") where !directory.isEmpty {
                candidates.append(String(directory) + "/fermion")
            }
        }
        candidates.append(NSHomeDirectory() + "/Documents/Developer/phonon_test_env/bin/fermion")
        
        let fileManager = FileManager.default
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }
    
    /// Human-readable remediation when no engine binary can be found.
    public static var fermionPathHint: String {
        "Set the path with `defaults write \(bundleIdentifier) \(fermionPathDefaultsKey) /path/to/fermion`, "
        + "set ECHO_FERMION_PATH, or place `fermion` in PATH."
    }
    
    // MARK: - Export
    
    /// Folder used by "Export Notes to Obsidian". Defaults to
    /// `~/Documents/Echo Meetings` and can be overridden per user.
    public static var exportDirectory: URL {
        if let configured = UserDefaults.standard.string(forKey: exportDirectoryDefaultsKey),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Echo Meetings", isDirectory: true)
    }
    
    /// Create the export directory (owner-only) and return it.
    @discardableResult
    public static func ensureExportDirectory() throws -> URL {
        let directory = exportDirectory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }
}
