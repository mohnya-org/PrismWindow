import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Current status") {
                    LabeledContent("Accessibility") {
                        Text(appState.isAccessibilityTrusted ? "Granted" : "Missing")
                    }
                    LabeledContent("Shortcut") {
                        Text("Ctrl + Opt + Cmd + F")
                    }
                    LabeledContent("Latest result") {
                        Text(appState.lastMessage)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Rules") {
                    if appState.rules.isEmpty {
                        Text("No rules configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.rules) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.appName)
                                    Text(rule.bundleIdentifier)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(appState.targetDisplayName(for: rule))
                                    .foregroundStyle(.secondary)
                                Button("Remove") {
                                    appState.removeRule(rule)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Prism Settings")
        }
    }
}
