import SwiftUI
import AppKit

@main
struct PrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Prism Window", systemImage: "display.2") {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(appDelegate.updates)
                .frame(width: 400)
        }
        .menuBarExtraStyle(.window)

        Window("Prism Window Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appDelegate.updates)
                .frame(minWidth: 780, minHeight: 520)
                .toolbar(.hidden)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updates = UpdateController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.start()
        NSApp.setActivationPolicy(.accessory)
    }
}
