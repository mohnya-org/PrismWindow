import Foundation

enum UpdateConfiguration {
    static func isConfigured(info: [String: Any]) -> Bool {
        guard let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }
}
