import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var lastMessage = "Ready"
    @Published var isAccessibilityTrusted = false
    @Published var isHandlingMove = false
    @Published var currentAppDescriptor: AppDescriptor?
    @Published var runningApps: [AppDescriptor] = []
    @Published var displays: [DisplayInfo] = []
    @Published var rules: [DisplayRule] = []

    private let permissionManager = PermissionManager()
    private let windowMover = WindowMover()
    private let ruleStore = RuleStore()
    private var hotKeyController: GlobalHotKeyController?
    private var observers: [Any] = []

    init() {
        rules = ruleStore.loadRules()
        refreshDisplays()
        refreshRunningApps()
        refreshPermissions(prompt: false)
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

    var currentLayoutRules: [DisplayRule] {
        rules
            .filter { $0.layoutSignature == currentLayoutSignature }
            .sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return lhs.targetDisplayName < rhs.targetDisplayName
                }
                return lhs.appName < rhs.appName
            }
    }

    var savedLayouts: [SavedDisplayLayout] {
        Dictionary(grouping: rules, by: \.layoutSignature)
            .map { signature, rules in
                SavedDisplayLayout(
                    signature: signature,
                    name: rules.first?.layoutName ?? "Saved Layout",
                    rules: rules.sorted { $0.appName < $1.appName }
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

        let rule = DisplayRule(
            layoutSignature: currentLayoutSignature,
            layoutName: currentLayoutName,
            bundleIdentifier: app.bundleIdentifier,
            appName: app.displayName,
            targetDisplayPersistentID: targetDisplay.persistentID,
            targetDisplayName: targetDisplay.name,
            windowMode: mode
        )

        rules.removeAll {
            $0.layoutSignature == rule.layoutSignature &&
            $0.bundleIdentifier == rule.bundleIdentifier
        }
        rules.append(rule)
        rules.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        ruleStore.saveRules(rules)
        lastMessage = "Saved \(mode.label.lowercased()) rule for \(app.displayName) on \(targetDisplay.name)."
    }

    func removeRule(_ rule: DisplayRule) {
        rules.removeAll { $0.id == rule.id }
        ruleStore.saveRules(rules)
    }

    func updateRuleMode(_ rule: DisplayRule, to mode: DisplayWindowMode) {
        guard mode != .keepCurrent else { return }
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }

        rules[index] = DisplayRule(
            layoutSignature: rule.layoutSignature,
            layoutName: rule.layoutName,
            bundleIdentifier: rule.bundleIdentifier,
            appName: rule.appName,
            targetDisplayPersistentID: rule.targetDisplayPersistentID,
            targetDisplayName: rule.targetDisplayName,
            windowMode: mode
        )
        ruleStore.saveRules(rules)
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
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmost.bundleIdentifier,
              let rule = rules.first(where: {
                  $0.layoutSignature == currentLayoutSignature &&
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

struct SavedDisplayLayout: Identifiable {
    let signature: String
    let name: String
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
    let bundleIdentifier: String
    let appName: String
    let targetDisplayPersistentID: String
    let targetDisplayName: String
    let windowMode: DisplayWindowMode

    var id: String { "\(layoutSignature)|\(bundleIdentifier)" }
}
