import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            permissionsCard
            shortcutCard
            rulesCard

            HStack {
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prism")
                .font(.title2.bold())
            Text(appState.lastMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                appState.isAccessibilityTrusted ? "Accessibility granted" : "Accessibility required",
                systemImage: appState.isAccessibilityTrusted ? "checkmark.shield" : "exclamationmark.triangle"
            )
            .font(.headline)

            Text("Native fullscreen windows are handled through Accessibility APIs. Screen Recording may still help debugging, but it is not required for the fallback path.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Request Accessibility Access") {
                appState.refreshPermissions(prompt: true)
            }
        }
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move focused fullscreen window")
                .font(.headline)
            Text("Shortcut: Control + Option + Command + F")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await appState.moveFocusedWindowToNextDisplay(trigger: "Manual")
                }
            } label: {
                Text(appState.isHandlingMove ? "Moving..." : "Move Now")
                    .frame(maxWidth: .infinity)
            }
            .disabled(appState.isHandlingMove)
            .buttonStyle(.borderedProminent)
        }
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin frontmost app to a display")
                .font(.headline)

            if let app = appState.currentAppDescriptor {
                Text("\(app.displayName) (`\(app.bundleIdentifier)`)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(DisplayInfo.availableDisplays(), id: \.id) { display in
                    Button("Send \(app.displayName) to \(display.name)") {
                        appState.saveRule(for: display.id)
                    }
                }

                Button("Remove Rule for \(app.displayName)") {
                    appState.saveRule(for: nil)
                }
                .foregroundStyle(.secondary)
            } else {
                Text("No active app detected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
