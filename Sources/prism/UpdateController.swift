import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var startupError: String?
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController

    init() {
        // Only start when a valid update verification key is embedded.
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = Data(base64Encoded: key)?.count == 32
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard isConfigured else { return }
        do {
            try controller.updater.start()
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct SoftwareUpdateView: View {
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updates.automaticallyChecksForUpdates },
                set: { updates.setAutomaticallyChecksForUpdates($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!updates.isConfigured)

            Button("Check for Updates…") {
                updates.checkForUpdates()
            }
            .disabled(!updates.canCheckForUpdates)
            .help(updates.isConfigured ? "Check for a new version" : "Updates are unavailable in this development build")

            if !updates.isConfigured {
                Text("Updates are unavailable in this build. Install the official release to enable updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Download Latest Release", destination: URL(string: "https://github.com/mohnya-org/PrismWindow/releases/latest")!)
            } else if let error = updates.startupError {
                Text("Could not start updates: \(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
