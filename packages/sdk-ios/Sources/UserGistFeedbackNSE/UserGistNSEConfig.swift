#if os(iOS)
import Foundation

/// Configuration plumbing for the UserGist Notification Service Extension.
///
/// Resolution order for each field:
///   1. App Group's UserDefaults — `UserGistAppGroup` Info.plist key.
///      The main SDK writes the latest values here at init so secrets
///      can rotate without an App Store update.
///   2. The extension target's own Info.plist.
///
/// Required keys: `UserGistWriteKey`. Optional: `UserGistApiUrl` (defaults
/// to https://api.usergist.com), `UserGistAppGroup`.
enum UserGistNSEConfig {

    static var writeKey: String? {
        return readString(key: "UserGistWriteKey")
    }

    static var anonymousId: String? {
        return readString(key: "UserGistAnonymousId")
    }

    static var apiUrl: URL? {
        let raw = readString(key: "UserGistApiUrl") ?? "https://api.usergist.com"
        return URL(string: raw)
    }

    private static func readString(key: String) -> String? {
        if let group = Bundle.main.object(forInfoDictionaryKey: "UserGistAppGroup") as? String,
           let defaults = UserDefaults(suiteName: group),
           let value = defaults.string(forKey: key),
           !value.isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.isEmpty {
            return value
        }
        return nil
    }
}
#endif
