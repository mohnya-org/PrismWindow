import Foundation

struct RuleStore {
    private let key = "displayRules"

    func loadRules() -> [DisplayRule] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rules = try? JSONDecoder().decode([DisplayRule].self, from: data) else {
            return []
        }
        return rules
    }

    func saveRules(_ rules: [DisplayRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
