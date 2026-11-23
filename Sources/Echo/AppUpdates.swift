import AppKit
import Sparkle

@MainActor
final class AppUpdates: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdates()
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil, !DatabaseManager.shared.isUsingTemporaryStorage,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    static func verifyStartup() throws {
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        try controller.updater.start()
    }

    func addMenuItems(to menu: NSMenu) {
        guard let controller else { return }
        let item = NSMenuItem(title: "Check for Updates…",
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        menu.addItem(item)

        let automatic = NSMenuItem(title: "Automatically Check for Updates",
                                   action: #selector(toggleAutomaticChecks(_:)),
                                   keyEquivalent: "")
        automatic.target = self
        automatic.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        menu.addItem(automatic)
    }

    @objc private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        sender.state = updater.automaticallyChecksForUpdates ? .on : .off
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard AppCoordinator.shared.isBusyForUpdate else { return false }
        AppCoordinator.shared.statusMessage = "Update ready. Echo will relaunch after recording and saving finish."
        Task { @MainActor in
            while AppCoordinator.shared.isBusyForUpdate {
                try? await Task.sleep(for: .seconds(1))
            }
            installHandler()
        }
        return true
    }
}
