import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !appState.isAccessibilityTrusted {
                permissionsCard
            }

            moveSection

            HStack {
                Button("Settings…") {
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
            Text("Move windows between displays")
                .font(.callout)
                .foregroundStyle(.secondary)
            if appState.lastMessage != "Ready" {
                Text(appState.lastMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility required", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Button("Grant Access") {
                appState.refreshPermissions(prompt: true)
            }
        }
    }

    private var moveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let displays = DisplayInfo.availableDisplays()

            ForEach(displays, id: \.id) { display in
                Button {
                    Task {
                        await appState.moveFocusedWindow(to: display.id)
                    }
                } label: {
                    Label(display.name, systemImage: "display")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(appState.isHandlingMove)
            }
        }
    }
}
