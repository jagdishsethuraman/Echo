import Foundation
import Testing
@testable import Echo

@Suite("EchoSettings", .serialized)
struct EchoSettingsTests {
    /// Tracks the previous values so each test leaves the user's defaults alone.
    private struct DefaultsBackup {
        let fermionPath: String?
        let fermionDevice: String?
        let exportDirectory: String?
        
        init(defaults: UserDefaults) {
            fermionPath = defaults.string(forKey: EchoSettings.fermionPathDefaultsKey)
            fermionDevice = defaults.string(forKey: EchoSettings.fermionDeviceDefaultsKey)
            exportDirectory = defaults.string(forKey: EchoSettings.exportDirectoryDefaultsKey)
        }
        
        func restore(defaults: UserDefaults) {
            if let fermionPath {
                defaults.set(fermionPath, forKey: EchoSettings.fermionPathDefaultsKey)
            } else {
                defaults.removeObject(forKey: EchoSettings.fermionPathDefaultsKey)
            }
            if let fermionDevice {
                defaults.set(fermionDevice, forKey: EchoSettings.fermionDeviceDefaultsKey)
            } else {
                defaults.removeObject(forKey: EchoSettings.fermionDeviceDefaultsKey)
            }
            if let exportDirectory {
                defaults.set(exportDirectory, forKey: EchoSettings.exportDirectoryDefaultsKey)
            } else {
                defaults.removeObject(forKey: EchoSettings.exportDirectoryDefaultsKey)
            }
        }
    }
    
    @Test func standaloneRetentionReadsSavedPreferenceAndDefaultsToForever() throws {
        let suite = "echo-retention-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(EchoSettings.readDictationRetention(from: defaults) == .forever)
        defaults.set("sevenDays", forKey: EchoSettings.dictationRetentionDefaultsKey)
        let retention = EchoSettings.readDictationRetention(from: defaults)
        #expect(retention == .sevenDays)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(retention.keepsDictation(at: now.addingTimeInterval(-7 * 86_400), now: now))
        #expect(!retention.keepsDictation(at: now.addingTimeInterval(-7 * 86_400 - 1), now: now))
        defaults.set("invalid", forKey: EchoSettings.dictationRetentionDefaultsKey)
        #expect(EchoSettings.readDictationRetention(from: defaults) == .forever)
    }

    @Test func defaultExportDirectoryIsInDocuments() {
        let defaults = UserDefaults.standard
        let backup = DefaultsBackup(defaults: defaults)
        defer { backup.restore(defaults: defaults) }
        
        defaults.removeObject(forKey: EchoSettings.exportDirectoryDefaultsKey)
        
        let directory = EchoSettings.exportDirectory
        #expect(directory.hasDirectoryPath)
        #expect(directory.lastPathComponent == "Echo Meetings")
        #expect(directory.deletingLastPathComponent().lastPathComponent == "Documents")
    }
    
    @Test func exportDirectoryHonorsUserDefault() throws {
        let defaults = UserDefaults.standard
        let backup = DefaultsBackup(defaults: defaults)
        let custom = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-export-\(UUID().uuidString)", isDirectory: true)
        defer {
            backup.restore(defaults: defaults)
            try? FileManager.default.removeItem(at: custom)
        }
        
        defaults.set(custom.path, forKey: EchoSettings.exportDirectoryDefaultsKey)
        #expect(EchoSettings.exportDirectory.path == custom.path)
        
        let created = try EchoSettings.ensureExportDirectory()
        #expect(created.path == custom.path)
        
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        
        let attributes = try FileManager.default.attributesOfItem(atPath: created.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
        
        // Creating it twice is safe.
        _ = try EchoSettings.ensureExportDirectory()
    }
    
    @Test func fermionPathHonorsUserDefault() throws {
        let defaults = UserDefaults.standard
        let backup = DefaultsBackup(defaults: defaults)
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-fermion-\(UUID().uuidString)")
        defer {
            backup.restore(defaults: defaults)
            try? FileManager.default.removeItem(at: executable)
        }
        
        FileManager.default.createFile(
            atPath: executable.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        
        defaults.set(executable.path, forKey: EchoSettings.fermionPathDefaultsKey)
        #expect(EchoSettings.resolveFermionPath() == executable.path)
    }
    
    @Test func fermionPathIgnoresMissingUserDefaultFile() {
        let defaults = UserDefaults.standard
        let backup = DefaultsBackup(defaults: defaults)
        defer { backup.restore(defaults: defaults) }
        
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-fermion-\(UUID().uuidString)")
            .path
        defaults.set(missing, forKey: EchoSettings.fermionPathDefaultsKey)
        
        // Falls through to the rest of the resolution chain instead of returning
        // a path that cannot be executed.
        #expect(EchoSettings.resolveFermionPath() != missing)
    }
    
    @Test func fermionHintMentionsBothOverrideMechanisms() {
        #expect(EchoSettings.fermionPathHint.contains(EchoSettings.fermionPathDefaultsKey))
        #expect(EchoSettings.fermionPathHint.contains("ECHO_FERMION_PATH"))
    }

    @Test func fermionDeviceHonorsUserDefaultAndTrims() {
        let defaults = UserDefaults.standard
        let backup = DefaultsBackup(defaults: defaults)
        defer { backup.restore(defaults: defaults) }
        
        defaults.removeObject(forKey: EchoSettings.fermionDeviceDefaultsKey)
        // Without default or env, falls back to cpu
        if ProcessInfo.processInfo.environment["ECHO_FERMION_DEVICE"] == nil {
            #expect(EchoSettings.resolveFermionDevice() == "cpu")
        }
        
        defaults.set("  MPS  ", forKey: EchoSettings.fermionDeviceDefaultsKey)
        #expect(EchoSettings.resolveFermionDevice() == "mps")
        
        defaults.set("MLX", forKey: EchoSettings.fermionDeviceDefaultsKey)
        #expect(EchoSettings.resolveFermionDevice() == "mlx")
    }
}
