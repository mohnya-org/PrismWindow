import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var lastMessage = "Ready"
    @Published var autoApplyRules: Bool = UserDefaults.standard.object(forKey: "autoApplyRules") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoApplyRules, forKey: "autoApplyRules") }
    }
    @Published var isAccessibilityTrusted = false
    @Published var isHandlingMove = false
    @Published var currentAppDescriptor: AppDescriptor?
    @Published var runningApps: [AppDescriptor] = []
    @Published var displays: [DisplayInfo] = []
    @Published var rules: [DisplayRule] = []
    @Published var profiles: [DisplaySetupProfile] = []
    @Published var selectedProfileIDsByLayout: [String: String] = [:]

    private let permissionManager = PermissionManager()
    private let windowMover = WindowMover()
    private let ruleStore = RuleStore()
    private var hotKeyController: GlobalHotKeyController?
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
        hotKeyController = GlobalHotKeyController { [weak self] in
            Task { @MainActor in
                await self?.moveFocusedWindowToNextDisplay(trigger: "Global shortcut")
            }
        }
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
        let layoutProfiles = profiles
            .filter { $0.layoutSignature == currentLayoutSignature }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if layoutProfiles.isEmpty {
            return [defaultProfileForCurrentLayout()]
        }
        return layoutProfiles
    }

    var selectedProfileID: String {
        let fallback = currentProfiles.first?.id ?? defaultProfileForCurrentLayout().id
        return selectedProfileIDsByLayout[currentLayoutSignature] ?? fallback
    }

    var selectedProfile: DisplaySetupProfile {
        currentProfiles.first(where: { $0.id == selectedProfileID }) ?? defaultProfileForCurrentLayout()
    }

    var currentLayoutRules: [DisplayRule] {
        rules
            .filter {
                $0.layoutSignature == currentLayoutSignature &&
                $0.profileID == selectedProfileID
            }
            .sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return lhs.targetDisplayName < rhs.targetDisplayName
                }
                return lhs.appName < rhs.appName
            }
    }

    var savedLayouts: [SavedDisplayLayout] {
        let groupedProfiles = Dictionary(grouping: profiles, by: \.layoutSignature)
        let knownLayoutSignatures = Set(rules.map(\.layoutSignature)).union(groupedProfiles.keys)

        return knownLayoutSignatures.map { signature in
            let layoutProfiles = (groupedProfiles[signature] ?? []).sorted { $0.name < $1.name }
            let layoutRules = rules.filter { $0.layoutSignature == signature }
            return SavedDisplayLayout(
                signature: signature,
                name: layoutProfiles.first?.layoutName ?? layoutRules.first?.layoutName ?? "Saved Layout",
                profiles: layoutProfiles.isEmpty ? [DisplaySetupProfile(id: "default", layoutSignature: signature, layoutName: layoutRules.first?.layoutName ?? "Saved Layout", name: "Default")] : layoutProfiles,
                rules: layoutRules
            )
        }
        .sorted { lhs, rhs in
            if lhs.signature == currentLayoutSignature { return true }
            if rhs.signature == currentLayoutSignature { return false }
            return lhs.name < rhs.name
        }
    }

    func refreshPermissions(prompt: Bool) {
        isAccessibilityTrusted = permissionManager.accessibilityTrusted(prompt: prompt)
    }

    func refreshDisplays() {
        displays = DisplayInfo.availableDisplays()
        ensureProfileSelection()
    }

    func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
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

    func moveFocusedWindowToNextDisplay(trigger: String = "Manual") async {
        guard !isHandlingMove else { return }
        isHandlingMove = true
        defer { isHandlingMove = false }

        refreshPermissions(prompt: true)
        guard isAccessibilityTrusted else {
            lastMessage = "Accessibility permission is required."
            return
        }

        do {
            let result = try await windowMover.moveFocusedWindowToNextDisplay()
            lastMessage = "\(trigger): \(result.message)"
            refreshCurrentAppDescriptor()
        } catch {
            lastMessage = error.localizedDescription
        }
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
            let result = try await windowMover.moveFocusedWindow(to: displayID, mode: .keepCurrent)
            lastMessage = result.message
            refreshCurrentAppDescriptor()
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
                self?.refreshCurrentAppDescriptor()
                self?.refreshRunningApps()
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

        do {
            if try windowMover.focusedWindowMatches(displayID: targetDisplay.id, mode: rule.windowMode) {
                return
            }
            let result = try await windowMover.moveFocusedWindow(to: targetDisplay.id, mode: rule.windowMode)
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
            return "Windowed"
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
}
