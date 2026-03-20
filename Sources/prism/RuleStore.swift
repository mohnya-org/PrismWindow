import Foundation

struct RuleStore {
    private let key = "displayRules"

    func loadRules() -> [DisplayRule] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }

        if let rules = try? JSONDecoder().decode([DisplayRule].self, from: data) {
            return rules
        }

        if let legacyRules = try? JSONDecoder().decode([LegacyDisplayRule].self, from: data) {
            return legacyRules.map {
                DisplayRule(
                    layoutSignature: "",
                    layoutName: "Any Layout",
                    bundleIdentifier: $0.bundleIdentifier,
                    appName: $0.appName,
                    targetDisplayPersistentID: "",
                    targetDisplayName: "Legacy Display \($0.targetDisplayID)",
                    windowMode: .windowed
                )
            }
        }

        return []
    }

    func saveRules(_ rules: [DisplayRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct LegacyDisplayRule: Codable {
    let bundleIdentifier: String
    let appName: String
    let targetDisplayID: UInt32
}
