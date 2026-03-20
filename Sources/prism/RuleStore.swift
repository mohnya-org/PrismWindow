import Foundation

struct RuleStorePayload: Codable {
    var rules: [DisplayRule]
    var profiles: [DisplaySetupProfile]
    var selectedProfileIDsByLayout: [String: String]
}

struct RuleStore {
    private let key = "displayRules"

    func loadPayload() -> RuleStorePayload {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return RuleStorePayload(rules: [], profiles: [], selectedProfileIDsByLayout: [:])
        }

        if let payload = try? JSONDecoder().decode(RuleStorePayload.self, from: data) {
            return payload
        }

        if let rules = try? JSONDecoder().decode([DisplayRule].self, from: data) {
            let profiles = Dictionary(grouping: rules, by: { "\($0.layoutSignature)|\($0.profileID)" })
                .compactMap { entry -> DisplaySetupProfile? in
                    let groupedRules = entry.value
                    guard let first = groupedRules.first else { return nil }
                    return DisplaySetupProfile(
                        id: first.profileID,
                        layoutSignature: first.layoutSignature,
                        layoutName: first.layoutName,
                        name: first.profileName
                    )
                }

            return RuleStorePayload(rules: rules, profiles: profiles, selectedProfileIDsByLayout: [:])
        }

        if let legacyRules = try? JSONDecoder().decode([LegacyDisplayRule].self, from: data) {
            let rules = legacyRules.map {
                DisplayRule(
                    layoutSignature: "",
                    layoutName: "Any Layout",
                    profileID: "default",
                    profileName: "Default",
                    bundleIdentifier: $0.bundleIdentifier,
                    appName: $0.appName,
                    targetDisplayPersistentID: "",
                    targetDisplayName: "Legacy Display \($0.targetDisplayID)",
                    windowMode: .windowed
                )
            }
            return RuleStorePayload(rules: rules, profiles: [], selectedProfileIDsByLayout: [:])
        }

        return RuleStorePayload(rules: [], profiles: [], selectedProfileIDsByLayout: [:])
    }

    func savePayload(_ payload: RuleStorePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct LegacyDisplayRule: Codable {
    let bundleIdentifier: String
    let appName: String
    let targetDisplayID: UInt32
}
