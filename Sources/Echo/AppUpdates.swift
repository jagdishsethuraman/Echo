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

    func addMenuItem(to menu: NSMenu) {
        guard let controller else { return }
        let item = NSMenuItem(title: "Check for Updates…",
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        menu.addItem(item)
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
