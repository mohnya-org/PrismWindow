import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var lastMessage = "Ready"
    @Published var isAccessibilityTrusted = false
    @Published var isHandlingMove = false
    @Published var currentAppDescriptor: AppDescriptor?
    @Published var rules: [DisplayRule] = []

    private let permissionManager = PermissionManager()
    private let windowMover = WindowMover()
    private let ruleStore = RuleStore()
    private var hotKeyController: GlobalHotKeyController?
    private var observers: [Any] = []

    init() {
        rules = ruleStore.loadRules()
        refreshPermissions(prompt: false)
        hotKeyController = GlobalHotKeyController { [weak self] in
            Task { @MainActor in
                await self?.moveFocusedWindowToNextDisplay(trigger: "Global shortcut")
            }
        }
        installObservers()
        refreshCurrentAppDescriptor()
    }

    func refreshPermissions(prompt: Bool) {
        isAccessibilityTrusted = permissionManager.accessibilityTrusted(prompt: prompt)
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
            let result = try await windowMover.moveFocusedWindow(to: displayID)
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
                displayName: $0.localizedName ?? "Unknown App"
            )
        }
    }

    func saveRule(for displayID: CGDirectDisplayID?) {
        refreshCurrentAppDescriptor()
        guard let descriptor = currentAppDescriptor else {
            lastMessage = "No frontmost app found."
            return
        }

        if let displayID {
            let rule = DisplayRule(
                bundleIdentifier: descriptor.bundleIdentifier,
                appName: descriptor.displayName,
                targetDisplayID: displayID
            )
            rules.removeAll { $0.bundleIdentifier == rule.bundleIdentifier }
            rules.append(rule)
            rules.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
            ruleStore.saveRules(rules)
            lastMessage = "Saved rule for \(descriptor.displayName)."
        } else {
            rules.removeAll { $0.bundleIdentifier == descriptor.bundleIdentifier }
            ruleStore.saveRules(rules)
            lastMessage = "Removed rule for \(descriptor.displayName)."
        }
    }

    func removeRule(_ rule: DisplayRule) {
        rules.removeAll { $0.id == rule.id }
        ruleStore.saveRules(rules)
    }

    func targetDisplayName(for rule: DisplayRule) -> String {
        DisplayInfo.availableDisplays().first(where: { $0.id == rule.targetDisplayID })?.name ?? "Missing Display"
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
                await self?.applyRuleForFrontmostAppIfNeeded()
            }
        }
        observers.append(activationObserver)

        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
        observers.append(screenObserver)
    }

    private func applyRuleForFrontmostAppIfNeeded() async {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmost.bundleIdentifier,
              let rule = rules.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }

        do {
            let result = try await windowMover.moveFocusedWindow(to: rule.targetDisplayID)
            lastMessage = "Rule applied: \(result.message)"
        } catch {
            lastMessage = "Rule failed: \(error.localizedDescription)"
        }
    }
}

struct AppDescriptor: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

struct DisplayRule: Codable, Identifiable, Hashable {
    let bundleIdentifier: String
    let appName: String
    let targetDisplayID: CGDirectDisplayID

    var id: String { bundleIdentifier }
}
