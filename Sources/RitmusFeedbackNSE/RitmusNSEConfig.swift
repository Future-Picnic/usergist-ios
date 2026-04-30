#if os(iOS)
import Foundation

/// Configuration plumbing for the Ritmus Notification Service Extension.
///
/// Resolution order for each field:
///   1. App Group's UserDefaults — `RitmusAppGroup` Info.plist key.
///      The main SDK writes the latest values here at init so secrets
///      can rotate without an App Store update.
///   2. The extension target's own Info.plist.
///
/// Required keys: `RitmusWriteKey`. Optional: `RitmusApiUrl` (defaults
/// to https://api.ritmus.studio), `RitmusAppGroup`.
enum RitmusNSEConfig {

    static var writeKey: String? {
        return readString(key: "RitmusWriteKey")
    }

    static var anonymousId: String? {
        return readString(key: "RitmusAnonymousId")
    }

    static var apiUrl: URL? {
        let raw = readString(key: "RitmusApiUrl") ?? "https://api.ritmus.studio"
        return URL(string: raw)
    }

    private static func readString(key: String) -> String? {
        if let group = Bundle.main.object(forInfoDictionaryKey: "RitmusAppGroup") as? String,
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
