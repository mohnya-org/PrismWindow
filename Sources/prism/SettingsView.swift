import ServiceManagement
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
    @State private var profileNameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(.vertical, 10)

            Divider()

            switch selectedTab {
            case .overview:
                overviewContent
            case .rules:
                rulesEditor
            case .layouts:
                savedLayoutsList
            }
        }
        .onAppear(perform: focusSettingsWindow)
        .onAppear(perform: syncSelections)
        .onChange(of: appState.runningApps) { _, _ in syncSelections() }
        .onChange(of: appState.displays) { _, _ in syncSelections() }
        .onChange(of: selectedBundleIdentifier) { _, _ in syncRuleSelection() }
        .onChange(of: appState.selectedProfileID) { _, _ in
            profileNameDraft = appState.selectedProfile.name
            syncRuleSelection()
        }
        .onChange(of: appState.currentAppDescriptor?.bundleIdentifier) { _, newValue in
            if let newValue, appState.runningApps.contains(where: { $0.bundleIdentifier == newValue }) {
                selectedBundleIdentifier = newValue
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

    private var selectedProfileName: String {
        appState.selectedProfile.name
    }

    private var currentAppName: String {
        appState.currentAppDescriptor?.displayName ?? "No focused app"
    }

    // MARK: - Overview

    private var overviewContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                overviewMetrics
                overviewStatusCard
            }
            overviewDisplaysCard
                .frame(maxHeight: .infinity)
        }
        .padding(16)
    }

    private var overviewMetrics: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                compactMetric(
                    title: "Accessibility",
                    value: appState.isAccessibilityTrusted ? "Granted" : "Missing",
                    symbol: appState.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    tint: appState.isAccessibilityTrusted ? .green : .orange
                )
                compactMetric(
                    title: "Displays",
                    value: "\(appState.displays.count)",
                    symbol: "display.2",
                    tint: .blue
                )
            }
            HStack(spacing: 10) {
                compactMetric(
                    title: "Rules",
                    value: "\(appState.currentLayoutRules.count)",
                    symbol: "square.grid.2x2.fill",
                    tint: .indigo
                )
                compactMetric(
                    title: "Focused App",
                    value: currentAppName,
                    symbol: "app.fill",
                    tint: .teal
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func compactMetric(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var overviewStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.lastMessage != "Ready" {
                HStack(spacing: 8) {
                    Text("Latest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appState.lastMessage)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }

            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at Login")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if !appState.currentLayoutRules.isEmpty {
                Toggle(isOn: $appState.autoApplyRules) {
                    Label("Auto-apply rules on focus", systemImage: "bolt.fill")
                        .font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    appState.lastMessage = "Launch at Login failed: \(error.localizedDescription)"
                }
            }
        )
    }

    private var overviewDisplaysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display Layout")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if appState.displays.isEmpty {
                Text("No displays detected.")
                    .foregroundStyle(.secondary)
            } else {
                OverviewDisplayLayoutView(displays: appState.displays)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    // MARK: - Rules Editor

    private var rulesEditor: some View {
        HStack(spacing: 0) {
            rulesSidebar
                .frame(width: 240)

            Divider()

            VStack(spacing: 0) {
                // Profile bar
                profileBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                // Rule editor + canvas
                VStack(spacing: 10) {
                    selectionCard
                    setupCanvasCard
                }
                .padding(12)
            }
        }
    }

    private var profileBar: some View {
        HStack(spacing: 8) {
            Picker("Profile", selection: selectedProfileBinding) {
                ForEach(appState.currentProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .frame(maxWidth: 180)

            TextField("Name", text: $profileNameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)

            Button("Rename") {
                appState.renameSelectedProfile(to: profileNameDraft)
                profileNameDraft = appState.selectedProfile.name
            }
            .controlSize(.small)
            .disabled(profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profileNameDraft == appState.selectedProfile.name)

            Spacer()

            Button {
                appState.createProfile()
            } label: {
                Image(systemName: "plus")
            }
            .controlSize(.small)

            Button {
                appState.deleteSelectedProfile()
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .disabled(appState.currentProfiles.count <= 1)
        }
    }

    private var rulesSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Apps")
                    .font(.headline)
                Spacer()
                Text("\(appState.currentLayoutRules.count) rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $selectedBundleIdentifier) {
                ForEach(appState.runningApps) { app in
                    let rule = appState.currentLayoutRules.first(where: { $0.bundleIdentifier == app.bundleIdentifier })

                    HStack(spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 18, height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            if rule != nil {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 2, y: 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.displayName)
                                .font(.callout)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            if let rule {
                                Text("\(rule.targetDisplayName) • \(rule.windowMode.label)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .tag(app.bundleIdentifier)
                }
            }
        }
    }

    private var selectionCard: some View {
        HStack(spacing: 12) {
            if let selectedApp {
                if let icon = selectedApp.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedApp.displayName)
                        .font(.callout.weight(.semibold))
                    if let selectedRule {
                        Text("Rule: \(selectedRule.targetDisplayName) • \(selectedRule.windowMode.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No rule — click a display below to assign")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Select an app from the sidebar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Fullscreen", isOn: fullscreenBinding)
                .toggleStyle(.switch)
                .controlSize(.small)

            if let selectedRule {
                Button("Remove") {
                    appState.removeRule(selectedRule)
                }
                .controlSize(.small)
            }

            Button("Save") {
                saveSelectedRule()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selectedDisplay == nil || selectedApp == nil)
        }
        .padding(10)
        .background(cardBackground)
    }

    private var setupCanvasCard: some View {
        DisplaySetupAssignmentCanvas(
            displays: appState.displays,
            rules: appState.currentLayoutRules,
            selectedBundleIdentifier: selectedBundleIdentifier,
            selectedDisplayPersistentID: selectedDisplayPersistentID,
            selectedMode: selectedMode,
            onSelectDisplay: selectDisplay(_:)
        )
        .frame(maxHeight: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Display Setups

    private var savedLayoutsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                if appState.savedLayouts.isEmpty {
                    Text("No saved display setups yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(appState.savedLayouts) { layout in
                        layoutDisclosure(layout)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { selectedMode == .fullscreen },
            set: { selectedMode = $0 ? .fullscreen : .windowed }
        )
    }

    private var selectedProfileBinding: Binding<String> {
        Binding(
            get: { appState.selectedProfileID },
            set: { appState.selectProfile(id: $0) }
        )
    }

    private func syncSelections() {
        profileNameDraft = appState.selectedProfile.name

        if selectedBundleIdentifier.isEmpty || !appState.runningApps.contains(where: { $0.bundleIdentifier == selectedBundleIdentifier }) {
            selectedBundleIdentifier = appState.currentAppDescriptor?.bundleIdentifier ?? appState.runningApps.first?.bundleIdentifier ?? ""
        }

        syncRuleSelection()
    }

    private func syncRuleSelection() {
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

    private func layoutDisclosure(_ layout: SavedDisplayLayout) -> some View {
        DisclosureGroup {
            if layout.rules.isEmpty {
                Text("No rules in this setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                let rulesByProfile = Dictionary(grouping: layout.rules, by: \.profileID)
                let sortedProfiles = layout.profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedProfiles) { profile in
                        let profileRules = rulesByProfile[profile.id] ?? []
                        if !profileRules.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.crop.rectangle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(profile.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if profile.id == appState.selectedProfileID && layout.signature == appState.currentLayoutSignature {
                                        Text("Selected")
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.green.opacity(0.15)))
                                            .foregroundStyle(.green)
                                    }
                                }

                                ForEach(profileRules) { rule in
                                    HStack(spacing: 10) {
                                        if let icon = icon(for: rule.bundleIdentifier) {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .interpolation(.high)
                                                .frame(width: 20, height: 20)
                                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(rule.appName)
                                                .font(.callout)
                                            Text("\(rule.targetDisplayName) • \(rule.windowMode.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            appState.removeRule(rule)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.secondary.opacity(0.06))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: layout.signature == appState.currentLayoutSignature ? "display.2" : "display")
                    .foregroundStyle(layout.signature == appState.currentLayoutSignature ? .blue : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(layout.name)
                            .font(.callout.weight(.semibold))
                        if layout.signature == appState.currentLayoutSignature {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .foregroundStyle(.blue)
                        }
                    }
                    Text("\(layout.rules.count) rules • \(layout.profiles.count) profiles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(cardBackground)
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(display.name)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if isSelectedTarget {
                                    Text(selectedMode.label)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }

                            if displayRules.isEmpty {
                                Text("No apps assigned")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(displayRules.prefix(5)) { rule in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(rule.bundleIdentifier == selectedBundleIdentifier ? Color.accentColor : Color.secondary.opacity(0.35))
                                                .frame(width: 5, height: 5)
                                            Text("\(rule.appName) • \(rule.windowMode.label)")
                                                .font(.caption2)
                                                .lineLimit(1)
                                        }
                                    }

                                    if displayRules.count > 5 {
                                        Text("+\(displayRules.count - 5) more")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelectedTarget ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelectedTarget ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelectedTarget ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .padding(10)
    }
}

private struct OverviewDisplayLayoutView: View {
    let displays: [DisplayInfo]

    var body: some View {
        GeometryReader { proxy in
            let layout = SettingsDisplayLayout(displays: displays, canvasSize: proxy.size)

            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.element.persistentID) { index, display in
                    let frame = layout.frame(for: display)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(display.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("\(Int(display.frame.width))×\(Int(display.frame.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .padding(8)
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
            width: display.frame.width * scale,
            height: display.frame.height * scale
        )
    }
}
