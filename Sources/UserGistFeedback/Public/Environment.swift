import Foundation

/// The deployment environment the SDK is talking to.
///
/// Controls which default API base URL is used when none is explicitly
/// provided via `apiURL` in `UserGist.initialize`.
public enum Environment: String, Sendable {
    /// Production environment — real user data.
    case production
    /// Staging environment — pre-release validation.
    case staging
    /// Development environment — local or dev backends.
    case development

    /// Default API base URL for the given environment.
    public var defaultAPIURL: URL {
        switch self {
        case .production:
            return URL(string: "https://api.usergist.studio")!
        case .staging:
            return URL(string: "https://api.staging.usergist.studio")!
        case .development:
            return URL(string: "http://localhost:3000")!
        }
    }
}
