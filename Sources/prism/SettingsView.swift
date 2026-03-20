import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable {
        case overview
        case rules
        case layouts

        var title: String {
            switch self {
            case .overview:
                return "Overview"
            case .rules:
                return "Rules"
            case .layouts:
                return "Display Setups"
            }
        }
    }

    @EnvironmentObject private var appState: AppState

    @State private var selectedBundleIdentifier = ""
    @State private var selectedDisplayPersistentID = ""
    @State private var selectedMode: DisplayWindowMode = .windowed
    @State private var selectedTab: SettingsTab = .overview

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Settings section", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                switch selectedTab {
                case .overview:
                    overviewContent
                case .rules:
                    rulesEditor
                case .layouts:
                    List { savedLayoutsSection }
                }
            }
            .navigationTitle("Prism Settings")
            .onAppear(perform: focusSettingsWindow)
            .onAppear(perform: syncSelections)
            .onChange(of: appState.runningApps) { _, _ in syncSelections() }
            .onChange(of: appState.displays) { _, _ in syncSelections() }
            .onChange(of: appState.currentAppDescriptor?.bundleIdentifier) { _, newValue in
                if let newValue, appState.runningApps.contains(where: { $0.bundleIdentifier == newValue }) {
                    selectedBundleIdentifier = newValue
                }
            }
        }
    }

    private var selectedApp: AppDescriptor? {
        appState.runningApps.first(where: { $0.bundleIdentifier == selectedBundleIdentifier })
    }

    private var selectedRule: DisplayRule? {
        guard let selectedApp else { return nil }
        return appState.currentLayoutRules.first(where: { $0.bundleIdentifier == selectedApp.bundleIdentifier })
    }

    private var selectedDisplay: DisplayInfo? {
        appState.displays.first(where: { $0.persistentID == selectedDisplayPersistentID })
    }

    private var currentAppName: String {
        appState.currentAppDescriptor?.displayName ?? "No focused app"
    }

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewHero
                overviewMetrics
                overviewStatusCard
                overviewDisplaysCard
            }
            .padding(16)
        }
    }

    private var overviewHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workspace Overview")
                .font(.largeTitle.weight(.semibold))
            Text("Current display setup, permissions, and active placement context.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.18), Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var overviewMetrics: some View {
        HStack(alignment: .top, spacing: 14) {
            overviewMetricCard(
                title: "Accessibility",
                value: appState.isAccessibilityTrusted ? "Granted" : "Missing",
                symbol: appState.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                tint: appState.isAccessibilityTrusted ? .green : .orange
            )
            overviewMetricCard(
                title: "Displays",
                value: "\(appState.displays.count)",
                symbol: "display.2",
                tint: .blue
            )
            overviewMetricCard(
                title: "Rules",
                value: "\(appState.currentLayoutRules.count)",
                symbol: "square.grid.2x2.fill",
                tint: .indigo
            )
            overviewMetricCard(
                title: "Focused App",
                value: currentAppName,
                symbol: "app.fill",
                tint: .teal
            )
        }
    }

    private func overviewMetricCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
    }

    private var overviewStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Status")
                .font(.headline)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Ctrl + Opt + Cmd + F")
                        .font(.headline)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.currentLayoutName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Latest result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.lastMessage)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var overviewDisplaysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Display Setup")
                .font(.headline)

            if appState.displays.isEmpty {
                Text("No displays detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appState.displays.enumerated()), id: \.element.persistentID) { index, display in
                    HStack(spacing: 12) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Display \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(display.name)
                                .font(.headline)
                            Text("\(Int(display.frame.width)) × \(Int(display.frame.height))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var rulesEditor: some View {
        HStack(spacing: 0) {
            rulesSidebar
                .frame(width: 260)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectionCard
                    setupCanvasCard
                    currentLayoutAssignmentsCard
                }
                .padding(16)
            }
        }
    }

    private var rulesSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps")
                    .font(.headline)
                Text("Choose an app to edit its placement rule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            List(selection: $selectedBundleIdentifier) {
                ForEach(appState.runningApps) { app in
                    let rule = appState.currentLayoutRules.first(where: { $0.bundleIdentifier == app.bundleIdentifier })

                    HStack(spacing: 10) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .lineLimit(1)
                            Text(rule.map { "\($0.targetDisplayName) • \($0.windowMode.label)" } ?? "No rule")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(app.bundleIdentifier)
                }
            }
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rule Editor")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fullscreen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedMode == .fullscreen ? "The app will be placed in fullscreen." : "The app will be placed as a normal window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Fullscreen", isOn: fullscreenBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if let selectedApp {
                HStack(spacing: 10) {
                    if let icon = selectedApp.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedApp.displayName)
                            .font(.headline)
                        if let selectedDisplay {
                            Text("Pending: \(selectedDisplay.name) • \(selectedMode.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let selectedRule {
                            Text("Current rule: \(selectedRule.targetDisplayName) • \(selectedRule.windowMode.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No rule saved for this app in the current display setup.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let selectedRule {
                        Button("Remove Rule") {
                            appState.removeRule(selectedRule)
                        }
                    }

                    Button("Save") {
                        saveSelectedRule()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDisplay == nil)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var setupCanvasCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click a display to assign the selected app")
                .font(.headline)

            Text("The canvas matches the current display setup. Select an app and mode, then click the target display.")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisplaySetupAssignmentCanvas(
                displays: appState.displays,
                rules: appState.currentLayoutRules,
                selectedBundleIdentifier: selectedBundleIdentifier,
                selectedDisplayPersistentID: selectedDisplayPersistentID,
                selectedMode: selectedMode,
                onSelectDisplay: selectDisplay(_: )
            )
            .frame(height: 280)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var currentLayoutAssignmentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assignments in this display setup")
                .font(.headline)

            if appState.currentLayoutRules.isEmpty {
                Text("No rules configured for the current display setup.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.currentLayoutRules) { rule in
                    HStack(alignment: .top) {
                        HStack(spacing: 10) {
                            if let icon = icon(for: rule.bundleIdentifier) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.appName)
                                Text("\(rule.targetDisplayName) • \(rule.windowMode.label)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Toggle("Fullscreen", isOn: assignmentModeBinding(for: rule))
                                .labelsHidden()
                                .toggleStyle(.switch)

                            Button("Remove") {
                                appState.removeRule(rule)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var savedLayoutsSection: some View {
        Section("All saved display setups") {
            if appState.savedLayouts.isEmpty {
                Text("No saved display setups yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.savedLayouts) { layout in
                    layoutBlock(layout)
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { selectedMode == .fullscreen },
            set: { selectedMode = $0 ? .fullscreen : .windowed }
        )
    }

    private func assignmentModeBinding(for rule: DisplayRule) -> Binding<Bool> {
        Binding(
            get: { rule.windowMode == .fullscreen },
            set: { isFullscreen in
                appState.updateRuleMode(rule, to: isFullscreen ? .fullscreen : .windowed)
                if selectedBundleIdentifier == rule.bundleIdentifier {
                    selectedMode = isFullscreen ? .fullscreen : .windowed
                }
            }
        )
    }

    private func syncSelections() {
        if selectedBundleIdentifier.isEmpty || !appState.runningApps.contains(where: { $0.bundleIdentifier == selectedBundleIdentifier }) {
            selectedBundleIdentifier = appState.currentAppDescriptor?.bundleIdentifier ?? appState.runningApps.first?.bundleIdentifier ?? ""
        }

        if let selectedRule {
            selectedDisplayPersistentID = selectedRule.targetDisplayPersistentID
            selectedMode = selectedRule.windowMode
        } else if selectedDisplayPersistentID.isEmpty || !appState.displays.contains(where: { $0.persistentID == selectedDisplayPersistentID }) {
            selectedDisplayPersistentID = appState.displays.first?.persistentID ?? ""
        }
    }

    private func selectDisplay(_ display: DisplayInfo) {
        selectedDisplayPersistentID = display.persistentID
    }

    private func saveSelectedRule() {
        guard let selectedApp, let selectedDisplay else { return }
        appState.saveRule(
            app: selectedApp,
            targetDisplayID: selectedDisplay.persistentID,
            mode: selectedMode
        )
    }

    private func focusSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
    }

    private func icon(for bundleIdentifier: String) -> NSImage? {
        appState.runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier })?.icon
            ?? (appState.currentAppDescriptor?.bundleIdentifier == bundleIdentifier ? appState.currentAppDescriptor?.icon : nil)
    }

    @ViewBuilder
    private func layoutBlock(_ layout: SavedDisplayLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name)
                        .font(.headline)
                    if layout.signature == appState.currentLayoutSignature {
                        Text("Current setup")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(layout.rules.count) rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(layout.rules) { rule in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.appName)
                        Text("\(rule.targetDisplayName) • \(rule.windowMode.label)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove") {
                        appState.removeRule(rule)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DisplaySetupAssignmentCanvas: View {
    let displays: [DisplayInfo]
    let rules: [DisplayRule]
    let selectedBundleIdentifier: String
    let selectedDisplayPersistentID: String
    let selectedMode: DisplayWindowMode
    let onSelectDisplay: (DisplayInfo) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = SettingsDisplayLayout(displays: displays, canvasSize: proxy.size)

            ZStack(alignment: .topLeading) {
                ForEach(displays, id: \.persistentID) { display in
                    let frame = layout.frame(for: display)
                    let displayRules = rules.filter { $0.targetDisplayPersistentID == display.persistentID }
                    let isSelectedTarget = selectedDisplayPersistentID == display.persistentID

                    Button {
                        onSelectDisplay(display)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(display.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                if isSelectedTarget {
                                    Text(selectedMode.label)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }

                            if displayRules.isEmpty {
                                Text("No app assigned")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(displayRules.prefix(4)) { rule in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(rule.bundleIdentifier == selectedBundleIdentifier ? Color.accentColor : Color.secondary.opacity(0.35))
                                                .frame(width: 6, height: 6)
                                            Text("\(rule.appName) • \(rule.windowMode.label)")
                                                .font(.caption)
                                                .lineLimit(1)
                                        }
                                    }

                                    if displayRules.count > 4 {
                                        Text("+\(displayRules.count - 4) more")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer(minLength: 0)

                            Text("Click to assign selected app here")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isSelectedTarget ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSelectedTarget ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelectedTarget ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .padding(12)
    }
}

private struct SettingsDisplayLayout {
    private let bounds: CGRect
    private let scale: CGFloat
    private let xInset: CGFloat
    private let yInset: CGFloat

    init(displays: [DisplayInfo], canvasSize: CGSize, padding: CGFloat = 12) {
        let fallback = CGRect(x: 0, y: 0, width: 1, height: 1)
        let combinedBounds = displays.dropFirst().reduce(displays.first?.frame ?? fallback) { partial, display in
            partial.union(display.frame)
        }
        let usableWidth = max(canvasSize.width - (padding * 2), 1)
        let usableHeight = max(canvasSize.height - (padding * 2), 1)
        let scale = min(usableWidth / max(combinedBounds.width, 1), usableHeight / max(combinedBounds.height, 1))
        let contentWidth = combinedBounds.width * scale
        let contentHeight = combinedBounds.height * scale

        bounds = combinedBounds
        self.scale = scale
        xInset = (canvasSize.width - contentWidth) / 2
        yInset = (canvasSize.height - contentHeight) / 2
    }

    func frame(for display: DisplayInfo) -> CGRect {
        CGRect(
            x: xInset + ((display.frame.minX - bounds.minX) * scale),
            y: yInset + ((display.frame.minY - bounds.minY) * scale),
            width: max(display.frame.width * scale, 120),
            height: max(display.frame.height * scale, 100)
        )
    }
}
