import AppKit
import Foundation

@MainActor
final class EchoAppDelegate: NSObject, NSApplicationDelegate {
    private var terminationRequested = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateLater }
        terminationRequested = true
        Task {
            let coordinator = AppCoordinator.shared
            var ready = await coordinator.prepareToQuit()
            while !ready {
                let meeting = coordinator.meetingCoordinator
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Some speech is still unsaved"
                alert.informativeText = meeting.transcriptSaveError ?? "Echo is holding unsaved speech in memory."
                alert.addButton(withTitle: "Retry Save")
                alert.addButton(withTitle: "Cancel Quit")
                alert.addButton(withTitle: "Discard Unsaved Speech and Quit")
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    await meeting.retryTranscriptSaves()
                    ready = meeting.unsavedTranscriptCount == 0
                case .alertThirdButtonReturn:
                    ready = true
                default:
                    coordinator.cancelPendingQuit()
                    terminationRequested = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            await coordinator.shutdownGracefully()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct EchoMain {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("--test") {
            do {
                try await verifyAssembly(arguments: args)
                return
            } catch {
                fputs("Echo verification failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        // Clean any leftover audio files from prior sessions or unexpected terminations
        AudioTempDirectory.sweepOrphanedAudioFiles()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        
        let delegate = EchoAppDelegate()
        app.delegate = delegate
        
        #if DEBUG
        if SnapshotHarness.renderIfRequested() {
            return
        }
        #endif

        let database = DatabaseManager.shared
        while let error = database.startupError {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Echo couldn't open its database"
            alert.informativeText = error.message + "\n" + error.path
            alert.addButton(withTitle: "Retry Durable Storage")
            alert.addButton(withTitle: "Quit")
            if database.canUseTemporaryStorage {
                alert.informativeText += "\nTemporary mode keeps new transcripts in memory only. They disappear when Echo quits."
                alert.addButton(withTitle: "Use Temporary Storage")
            } else {
                alert.addButton(withTitle: "Show in Finder")
            }
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                _ = database.retryDurableStorage()
            case .alertThirdButtonReturn where database.canUseTemporaryStorage:
                _ = database.useTemporaryStorage()
            case .alertThirdButtonReturn:
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: error.path)])
                return
            default:
                return
            }
        }

        // Normal Launch: Initialize Menu Bar and run live event loop
        MenuBarManager.shared.setupMenuBar()
        let coordinator = AppCoordinator.shared
        
        // Open Meeting Studio window on launch so user immediately sees the UI screen
        DispatchQueue.main.async {
            coordinator.showMeetingStudio()
        }
        
        print("Echo Speech Intelligence running. Hold \(KeyboardShortcuts.shared[.pushToTalk].label) to dictate. Meeting Studio opened.")
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Run before creating production singletons, opening user storage, or sweeping live audio.
    private static func verifyAssembly(arguments: [String]) async throws {
        func failure(_ message: String) -> NSError {
            NSError(domain: "Echo.Assembly", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let bundle = Bundle.main
        guard bundle.bundleIdentifier == "com.ragavij.echo",
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "Echo",
              bundle.url(forResource: "AppIcon", withExtension: "icns") != nil else {
            throw failure("Run this check from an assembled Echo.app containing its executable, Info.plist and AppIcon.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("echo-smoke-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = DatabaseManager(customPath: folder.appendingPathComponent("smoke.sqlite").path)
        if let error = db.startupError { throw error }
        print("Echo bundle and isolated database checks passed.")
        let runner = PhononProcessRunner()
        if let index = arguments.firstIndex(of: "--verify-speech") {
            guard index + 1 < arguments.count else { throw failure("Provide a speech WAV after --verify-speech.") }
            let url = URL(fileURLWithPath: arguments[index + 1])
            guard FileManager.default.fileExists(atPath: url.path) else { throw failure("Speech fixture is missing.") }
            let (text, _) = try await runner.transcribe(fileURL: url)
            guard !text.isEmpty else { throw failure("The engine returned an empty transcript.") }
            print("Speech verification passed: " + text)
        } else if arguments.contains("--require-engine") {
            try runner.checkReadiness()
            print("Engine executable is available. Speech inference was not exercised.")
        } else {
            print("Speech inference was not exercised. Use --test --verify-speech <wav> to check the engine and model.")
        }
    }
}
