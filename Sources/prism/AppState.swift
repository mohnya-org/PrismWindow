import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var lastMessage = "Ready"
    @Published var autoApplyRules: Bool = UserDefaults.standard.object(forKey: "autoApplyRules") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoApplyRules, forKey: "autoApplyRules") }
    }
    @Published var defaultToFullscreenOnMove: Bool = UserDefaults.standard.object(forKey: "defaultToFullscreenOnMove") as? Bool ?? false {
        didSet { UserDefaults.standard.set(defaultToFullscreenOnMove, forKey: "defaultToFullscreenOnMove") }
    }
    @Published var isAccessibilityTrusted = false
    @Published var isHandlingMove = false
    @Published var currentAppDescriptor: AppDescriptor?
    @Published var runningApps: [AppDescriptor] = []
    @Published var displays: [DisplayInfo] = [] {
        didSet { invalidateLayoutCache() }
    }
    @Published var rules: [DisplayRule] = [] {
        didSet { invalidateLayoutCache() }
    }
    @Published var profiles: [DisplaySetupProfile] = [] {
        didSet { invalidateLayoutCache() }
    }
    @Published var selectedProfileIDsByLayout: [String: String] = [:] {
        didSet { invalidateLayoutCache() }
    }

    // These values depend only on layout/rule/profile inputs, not focus changes,
    // status messages, or which Settings tab is visible.
    private var cachedCurrentProfiles: [DisplaySetupProfile]?
    private var cachedCurrentLayoutRules: [DisplayRule]?
    private var cachedSavedLayouts: [SavedDisplayLayout]?

    private func invalidateLayoutCache() {
        cachedCurrentProfiles = nil
        cachedCurrentLayoutRules = nil
        cachedSavedLayouts = nil
    }

    private let permissionManager = PermissionManager()
    private let windowMover = WindowMover()
    private let ruleStore = RuleStore()
    private var observers: [Any] = []

    init() {
        let payload = ruleStore.loadPayload()
        rules = payload.rules
        profiles = payload.profiles
        selectedProfileIDsByLayout = payload.selectedProfileIDsByLayout
        refreshDisplays()
        refreshRunningApps()
        refreshPermissions(prompt: false)
        ensureProfileSelection()
        installObservers()
        refreshCurrentAppDescriptor()
    }

    var currentLayoutSignature: String {
        DisplayInfo.currentLayoutSignature(for: displays)
    }

    var currentLayoutName: String {
        if displays.isEmpty {
            return "No Displays"
        }
        return displays.map(\.name).joined(separator: " + ")
    }

    var currentProfiles: [DisplaySetupProfile] {
        if let cachedCurrentProfiles { return cachedCurrentProfiles }
        let signature = currentLayoutSignature
        let layoutProfiles = profiles
            .filter { $0.layoutSignature == signature }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let result = layoutProfiles.isEmpty ? [defaultProfileForCurrentLayout()] : layoutProfiles
        cachedCurrentProfiles = result
        return result
    }

    var selectedProfileID: String {
        selectedProfileIDsByLayout[currentLayoutSignature]
            ?? currentProfiles.first?.id ?? defaultProfileForCurrentLayout().id
    }

    var selectedProfile: DisplaySetupProfile {
        let profileID = selectedProfileID
        return currentProfiles.first(where: { $0.id == profileID }) ?? defaultProfileForCurrentLayout()
    }

    var currentLayoutRules: [DisplayRule] {
        if let cachedCurrentLayoutRules { return cachedCurrentLayoutRules }
        let signature = currentLayoutSignature
        let profileID = selectedProfileID
        let result = rules
            .filter {
                $0.layoutSignature == signature &&
                $0.profileID == profileID
            }
            .sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return lhs.targetDisplayName < rhs.targetDisplayName
                }
                return lhs.appName < rhs.appName
            }
        cachedCurrentLayoutRules = result
        return result
    }

    var defaultMoveMode: DisplayWindowMode {
        defaultToFullscreenOnMove ? .fullscreen : .windowed
    }

    var savedLayouts: [SavedDisplayLayout] {
        if let cachedSavedLayouts { return cachedSavedLayouts }
        let signature = currentLayoutSignature
        let groupedProfiles = Dictionary(grouping: profiles, by: \.layoutSignature)
        let groupedRules = Dictionary(grouping: rules, by: \.layoutSignature)
        let knownLayoutSignatures = Set(groupedRules.keys).union(groupedProfiles.keys)

        let result = knownLayoutSignatures.map { signature in
            let layoutProfiles = (groupedProfiles[signature] ?? []).sorted { $0.name < $1.name }
            let layoutRules = groupedRules[signature] ?? []
            return SavedDisplayLayout(
                signature: signature,
                name: layoutProfiles.first?.layoutName ?? layoutRules.first?.layoutName ?? "Saved Layout",
                profiles: layoutProfiles.isEmpty ? [DisplaySetupProfile(id: "default", layoutSignature: signature, layoutName: layoutRules.first?.layoutName ?? "Saved Layout", name: "Default")] : layoutProfiles,
                rules: layoutRules
            )
        }
        .sorted { lhs, rhs in
            if lhs.signature != rhs.signature {
                if lhs.signature == signature { return true }
                if rhs.signature == signature { return false }
            }
            return lhs.name < rhs.name
        }
        cachedSavedLayouts = result
        return result
    }

    func refreshPermissions(prompt: Bool) {
        isAccessibilityTrusted = permissionManager.accessibilityTrusted(prompt: prompt)
    }

    func refreshDisplays() {
        displays = DisplayInfo.availableDisplays()
        ensureProfileSelection()
    }

    func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular &&
                application.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                application.bundleIdentifier != nil
            }
            .map {
                AppDescriptor(
                    bundleIdentifier: $0.bundleIdentifier ?? $0.executableURL?.lastPathComponent ?? "unknown",
                    displayName: $0.localizedName ?? "Unknown App",
                    icon: $0.icon
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if apps != runningApps {
            runningApps = apps
        }
    }

    func selectProfile(id: String) {
        selectedProfileIDsByLayout[currentLayoutSignature] = id
        persist()
    }

    func createProfile(named name: String? = nil) {
        let baseName = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? name!.trimmingCharacters(in: .whitespacesAndNewlines) : suggestedProfileName()
        let profile = DisplaySetupProfile(
            id: UUID().uuidString,
            layoutSignature: currentLayoutSignature,
            layoutName: currentLayoutName,
            name: baseName
        )
        profiles.append(profile)
        selectedProfileIDsByLayout[currentLayoutSignature] = profile.id
        persist()
        lastMessage = "Created display setup profile '\(profile.name)'."
    }

    func renameSelectedProfile(to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastMessage = "Profile name cannot be empty."
            return
        }
        guard let profileIndex = profiles.firstIndex(where: {
            $0.layoutSignature == currentLayoutSignature &&
            $0.id == selectedProfileID
        }) else {
            return
        }

        profiles[profileIndex] = DisplaySetupProfile(
            id: profiles[profileIndex].id,
            layoutSignature: profiles[profileIndex].layoutSignature,
            layoutName: currentLayoutName,
            name: trimmedName
        )

        for index in rules.indices where rules[index].layoutSignature == currentLayoutSignature && rules[index].profileID == selectedProfileID {
            rules[index] = DisplayRule(
                layoutSignature: rules[index].layoutSignature,
                layoutName: currentLayoutName,
                profileID: rules[index].profileID,
                profileName: trimmedName,
                bundleIdentifier: rules[index].bundleIdentifier,
                appName: rules[index].appName,
                targetDisplayPersistentID: rules[index].targetDisplayPersistentID,
                targetDisplayName: rules[index].targetDisplayName,
                windowMode: rules[index].windowMode
            )
        }

        persist()
        lastMessage = "Renamed display setup profile to '\(trimmedName)'."
    }

    func deleteSelectedProfile() {
        guard currentProfiles.count > 1 else {
            lastMessage = "At least one setup profile must remain."
            return
        }
        let profile = selectedProfile
        profiles.removeAll { $0.id == profile.id }
        rules.removeAll {
            $0.layoutSignature == currentLayoutSignature &&
            $0.profileID == profile.id
        }
        selectedProfileIDsByLayout[currentLayoutSignature] = currentProfilesAfterDeletion(removedID: profile.id).first?.id
        persist()
        lastMessage = "Deleted display setup profile '\(profile.name)'."
    }

    func moveFocusedWindow(to displayID: CGDirectDisplayID) async {
        guard !isHandlingMove else { return }
        isHandlingMove = true
        defer { isHandlingMove = false }

        refreshPermissions(prompt: true)
        guard isAccessibilityTrusted else {
            lastMessage = "Accessibility permission is required."
            return
        }

        do {
            let result = try await windowMover.moveFocusedWindow(
                to: displayID,
                mode: defaultMoveMode
            )
            lastMessage = result.message
            refreshCurrentAppDescriptor()
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func moveFocusedWindowAndMaybeUpdateRule(to displayID: CGDirectDisplayID) async {
        guard !isHandlingMove else { return }
        isHandlingMove = true
        defer { isHandlingMove = false }

        refreshPermissions(prompt: true)
        guard isAccessibilityTrusted else {
            lastMessage = "Accessibility permission is required."
            return
        }

        do {
            let moveMode = defaultMoveMode
            let result = try await windowMover.moveFocusedWindow(
                to: displayID,
                mode: moveMode
            )
            lastMessage = result.message
            refreshCurrentAppDescriptor()

            guard autoApplyRules,
                  let app = currentAppDescriptor,
                  let targetDisplay = displays.first(where: { $0.id == displayID }) else {
                return
            }

            saveRule(
                app: app,
                targetDisplayID: targetDisplay.persistentID,
                mode: moveMode
            )
            lastMessage = "Moved \(app.displayName) to \(targetDisplay.name) and updated its rule."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func refreshCurrentAppDescriptor() {
        currentAppDescriptor = NSWorkspace.shared.frontmostApplication.map {
            AppDescriptor(
                bundleIdentifier: $0.bundleIdentifier ?? $0.executableURL?.lastPathComponent ?? "unknown",
                displayName: $0.localizedName ?? "Unknown App",
                icon: $0.icon
            )
        }
    }

    func saveRule(app: AppDescriptor, targetDisplayID: String, mode: DisplayWindowMode) {
        guard let targetDisplay = displays.first(where: { $0.persistentID == targetDisplayID }) else {
            lastMessage = "The target display is not available."
            return
        }

        let profile = selectedProfile
        let rule = DisplayRule(
            layoutSignature: currentLayoutSignature,
            layoutName: currentLayoutName,
            profileID: profile.id,
            profileName: profile.name,
            bundleIdentifier: app.bundleIdentifier,
            appName: app.displayName,
            targetDisplayPersistentID: targetDisplay.persistentID,
            targetDisplayName: targetDisplay.name,
            windowMode: mode
        )

        rules.removeAll {
            $0.layoutSignature == rule.layoutSignature &&
            $0.profileID == rule.profileID &&
            $0.bundleIdentifier == rule.bundleIdentifier
        }
        rules.append(rule)
        rules.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        persist()
        lastMessage = "Saved \(mode.label.lowercased()) rule for \(app.displayName) on \(targetDisplay.name) in \(profile.name)."
    }

    func removeRule(_ rule: DisplayRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
        lastMessage = "Removed the rule for \(rule.appName) in \(rule.profileName)."
    }

    func updateRuleMode(_ rule: DisplayRule, to mode: DisplayWindowMode) {
        guard mode != .keepCurrent else { return }
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }

        rules[index] = DisplayRule(
            layoutSignature: rule.layoutSignature,
            layoutName: rule.layoutName,
            profileID: rule.profileID,
            profileName: rule.profileName,
            bundleIdentifier: rule.bundleIdentifier,
            appName: rule.appName,
            targetDisplayPersistentID: rule.targetDisplayPersistentID,
            targetDisplayName: rule.targetDisplayName,
            windowMode: mode
        )
        persist()
        lastMessage = "Updated \(rule.appName) to \(mode.label.lowercased())."
    }

    func targetDisplayName(for rule: DisplayRule) -> String {
        displays.first(where: { $0.persistentID == rule.targetDisplayPersistentID })?.name ?? rule.targetDisplayName
    }

    private func installObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions(prompt: false)
                self?.refreshCurrentAppDescriptor()
                await self?.applyRuleForFrontmostAppIfNeeded()
            }
        }
        observers.append(activationObserver)

        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRunningApps()
            }
        }
        observers.append(launchObserver)

        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRunningApps()
            }
        }
        observers.append(terminateObserver)

        // Re-apply rules when Spaces change (e.g. user manually exits
        // fullscreen, which destroys the fullscreen Space).
        let spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Small delay to let the space transition settle.
                try? await Task.sleep(for: .milliseconds(500))
                await self?.applyRuleForFrontmostAppIfNeeded()
            }
        }
        observers.append(spaceObserver)

        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
            }
        }
        observers.append(screenObserver)
    }

    private func applyRuleForFrontmostAppIfNeeded() async {
        guard autoApplyRules,
              !isHandlingMove,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmost.bundleIdentifier,
              let rule = rules.first(where: {
                  $0.layoutSignature == currentLayoutSignature &&
                  $0.profileID == selectedProfileID &&
                  $0.bundleIdentifier == bundleIdentifier
              }),
              let targetDisplay = displays.first(where: { $0.persistentID == rule.targetDisplayPersistentID }) else {
            return
        }

        // Moving can activate the app or change Spaces, both of which trigger
        // this method again. Keep automatic and manual moves serialized while
        // the asynchronous fullscreen/Space transitions are in progress.
        isHandlingMove = true
        defer { isHandlingMove = false }

        do {
            if try windowMover.focusedWindowMatches(
                displayID: targetDisplay.id,
                mode: rule.windowMode
            ) {
                return
            }
            let result = try await windowMover.moveFocusedWindow(
                to: targetDisplay.id,
                mode: rule.windowMode
            )
            lastMessage = "Rule applied: \(result.message)"
        } catch {
            lastMessage = "Rule failed: \(error.localizedDescription)"
        }
    }

    private func ensureProfileSelection() {
        if profiles.isEmpty || !profiles.contains(where: { $0.layoutSignature == currentLayoutSignature }) {
            let defaultProfile = defaultProfileForCurrentLayout()
            if !profiles.contains(where: { $0.id == defaultProfile.id && $0.layoutSignature == defaultProfile.layoutSignature }) {
                profiles.append(defaultProfile)
            }
        }

        if selectedProfileIDsByLayout[currentLayoutSignature] == nil ||
            !currentProfiles.contains(where: { $0.id == selectedProfileIDsByLayout[currentLayoutSignature] }) {
            selectedProfileIDsByLayout[currentLayoutSignature] = currentProfiles.first?.id
        }

        persist()
    }

    private func defaultProfileForCurrentLayout() -> DisplaySetupProfile {
        DisplaySetupProfile(
            id: "default-\(currentLayoutSignature)",
            layoutSignature: currentLayoutSignature,
            layoutName: currentLayoutName,
            name: "Default"
        )
    }

    private func currentProfilesAfterDeletion(removedID: String) -> [DisplaySetupProfile] {
        let remaining = profiles.filter { $0.layoutSignature == currentLayoutSignature && $0.id != removedID }
        return remaining.sorted { $0.name < $1.name }
    }

    private func suggestedProfileName() -> String {
        let existingNames = Set(currentProfiles.map(\.name))
        if !existingNames.contains("New Setup") {
            return "New Setup"
        }
        var index = 2
        while existingNames.contains("New Setup \(index)") {
            index += 1
        }
        return "New Setup \(index)"
    }

    private func persist() {
        ruleStore.savePayload(
            RuleStorePayload(
                rules: rules,
                profiles: profiles,
                selectedProfileIDsByLayout: selectedProfileIDsByLayout
            )
        )
    }
}

struct AppDescriptor: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage?

    var id: String { bundleIdentifier }

    static func == (lhs: AppDescriptor, rhs: AppDescriptor) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.displayName == rhs.displayName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(displayName)
    }
}

struct DisplaySetupProfile: Codable, Identifiable, Hashable {
    let id: String
    let layoutSignature: String
    let layoutName: String
    let name: String
}

struct SavedDisplayLayout: Identifiable {
    let signature: String
    let name: String
    let profiles: [DisplaySetupProfile]
    let rules: [DisplayRule]

    var id: String { signature }
}

enum DisplayWindowMode: String, Codable, CaseIterable, Identifiable {
    case windowed
    case fullscreen
    case keepCurrent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .windowed:
            return "Window"
        case .fullscreen:
            return "Fullscreen"
        case .keepCurrent:
            return "Keep Current"
        }
    }
}

struct DisplayRule: Codable, Identifiable, Hashable {
    let layoutSignature: String
    let layoutName: String
    let profileID: String
    let profileName: String
    let bundleIdentifier: String
    let appName: String
    let targetDisplayPersistentID: String
    let targetDisplayName: String
    let windowMode: DisplayWindowMode

    var id: String { "\(layoutSignature)|\(profileID)|\(bundleIdentifier)" }

    init(
        layoutSignature: String,
        layoutName: String,
        profileID: String,
        profileName: String,
        bundleIdentifier: String,
        appName: String,
        targetDisplayPersistentID: String,
        targetDisplayName: String,
        windowMode: DisplayWindowMode
    ) {
        self.layoutSignature = layoutSignature
        self.layoutName = layoutName
        self.profileID = profileID
        self.profileName = profileName
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.targetDisplayPersistentID = targetDisplayPersistentID
        self.targetDisplayName = targetDisplayName
        self.windowMode = windowMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layoutSignature = try container.decode(String.self, forKey: .layoutSignature)
        layoutName = try container.decode(String.self, forKey: .layoutName)
        profileID = try container.decode(String.self, forKey: .profileID)
        profileName = try container.decode(String.self, forKey: .profileName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        appName = try container.decode(String.self, forKey: .appName)
        targetDisplayPersistentID = try container.decode(String.self, forKey: .targetDisplayPersistentID)
        targetDisplayName = try container.decode(String.self, forKey: .targetDisplayName)
        windowMode = try container.decode(DisplayWindowMode.self, forKey: .windowMode)
    }
}
