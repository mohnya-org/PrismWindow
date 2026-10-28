#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/Tests.swift" <<'SWIFT'
import AppKit

// Use in-memory persistence so tests never load or modify the user's rules.
struct RuleStorePayload {
    var rules: [DisplayRule]
    var profiles: [DisplaySetupProfile]
    var selectedProfileIDsByLayout: [String: String]
}
struct RuleStore {
    func loadPayload() -> RuleStorePayload {
        RuleStorePayload(rules: [], profiles: [], selectedProfileIDsByLayout: [:])
    }
    func savePayload(_ payload: RuleStorePayload) {}
}

@main
struct SettingsDataTests {
    @MainActor static func main() {
        let state = AppState()
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let display = DisplayInfo(id: 1, name: "Test", frame: frame, visibleFrame: frame)
        state.displays = [display]
        let signature = state.currentLayoutSignature
        state.profiles = [
            DisplaySetupProfile(id: "a", layoutSignature: signature, layoutName: "Test", name: "Alpha"),
            DisplaySetupProfile(id: "b", layoutSignature: signature, layoutName: "Test", name: "Beta")
        ]
        state.selectedProfileIDsByLayout = [signature: "a"]
        func rule(_ name: String, _ profile: String) -> DisplayRule {
            DisplayRule(layoutSignature: signature, layoutName: "Test", profileID: profile,
                        profileName: profile, bundleIdentifier: "test.\(name)", appName: name,
                        targetDisplayPersistentID: display.persistentID, targetDisplayName: "Test", windowMode: .windowed)
        }
        state.rules = [rule("Zulu", "a"), rule("Alpha", "a"), rule("Beta", "b")]
        precondition(state.currentLayoutRules.map(\.appName) == ["Alpha", "Zulu"])
        precondition(state.currentProfiles.map(\.name) == ["Alpha", "Beta"])
        precondition(state.savedLayouts.first?.rules.count == 3)

        // Dictionary and array mutations must invalidate previously read results.
        state.selectedProfileIDsByLayout[signature] = "b"
        precondition(state.currentLayoutRules.map(\.appName) == ["Beta"])
        state.rules.removeAll { $0.profileID == "b" }
        precondition(state.currentLayoutRules.isEmpty)
        precondition(state.savedLayouts.first?.rules.count == 2)
        state.profiles[1] = DisplaySetupProfile(id: "b", layoutSignature: signature, layoutName: "Test", name: "Renamed")
        precondition(state.selectedProfile.name == "Renamed")
        precondition(state.savedLayouts.first?.profiles.contains { $0.name == "Renamed" } == true)
        state.selectedProfileIDsByLayout.removeAll()
        precondition(state.selectedProfileID == "a")
        precondition(state.currentLayoutRules.count == 2)

        state.displays = []
        precondition(state.currentLayoutRules.isEmpty)
        precondition(state.currentProfiles.first?.layoutSignature == "")
        state.displays = [display]
        precondition(state.currentLayoutRules.count == 2)

        // Repeated reads should not repeat sorting/grouping for every tab render.
        state.rules = (0..<1000).map { rule("App\($0)", "a") }
        _ = state.currentLayoutRules
        _ = state.savedLayouts
        let start = ContinuousClock.now
        for _ in 0..<1000 {
            precondition(state.currentLayoutRules.count == 1000)
            precondition(state.savedLayouts.first?.rules.count == 1000)
        }
        print("Passed settings data invalidation checks; 1,000 cached reads: \(start.duration(to: .now))")
    }
}
SWIFT
swiftc -parse-as-library -O \
  "$root/Sources/prism/AppState.swift" \
  "$root/Sources/prism/DisplayInfo.swift" \
  "$root/Sources/prism/WindowMover.swift" \
  "$root/Sources/prism/AXHelpers.swift" \
  "$root/Sources/prism/PermissionManager.swift" \
  "$test_dir/Tests.swift" -o "$test_dir/settings-data-tests"
"$test_dir/settings-data-tests"
