import SwiftUI
import AppKit
import Sparkle

@main
struct PrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Prism Window", systemImage: "display.2") {
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 400)
        }
        .menuBarExtraStyle(.window)

        Window("Prism Window Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 780, minHeight: 520)
                .toolbar(.hidden)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if Bundle.main.sparkleUpdatesAreConfigured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }
}

private extension Bundle {
    var sparkleUpdatesAreConfigured: Bool {
        guard let feedURL = object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }

        return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
