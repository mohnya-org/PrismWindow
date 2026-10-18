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
    private let controller: SPUStandardUpdaterController?

    init() {
        // Local builds and forks have no updater unless explicitly configured.
        isConfigured = UpdateConfiguration.isConfigured(info: Bundle.main.infoDictionary ?? [:])
        guard isConfigured else {
            controller = nil
            return
        }
        let configuredController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        controller = configuredController
        configuredController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        configuredController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard let controller else { return }
        do {
            try controller.updater.start()
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

struct SoftwareUpdateView: View {
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        if updates.isConfigured {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                Button("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
                .help("Check for a new version")

                if let error = updates.startupError {
                    Text("Could not start updates: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
