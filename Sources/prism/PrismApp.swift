import SwiftUI
import AppKit

@main
struct PrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Prism", systemImage: "display.2") {
            MenuBarView()
                .environmentObject(appState)
                .frame(width: 420)
        }
        .menuBarExtraStyle(.window)

        Window("Prism Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 780, minHeight: 520)
                .toolbar(.hidden)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
