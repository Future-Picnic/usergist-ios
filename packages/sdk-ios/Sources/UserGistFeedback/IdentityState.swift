import Foundation

/// `queued` means securely saved for retry, not server-confirmed.
public enum IdentifyResult: String, Sendable { case synced, queued, rejected }
public struct IdentityState: Sendable, Equatable {
    public enum Status: String, Sendable { case anonymous, identifying, identified, authenticationRequired, resetting, resetFailed, rejected }
    public let status: Status
    public let anonymousId: String
    public let externalId: String?
}
/// Fetch a new opaque subject token from your authenticated backend. Never put
/// a UserGist server API key in the application. Call completion exactly once.
public typealias SubjectTokenProvider = (String, @escaping (Result<String, Error>) -> Void) -> Void

/// OS permission is exposed separately by the push permission API. Registered
/// becomes true only after the control plane acknowledges this installation.
public struct PushSubscriptionState: Sendable, Equatable {
    public let tokenAvailable: Bool
    public let registered: Bool
    public let optedIn: Bool
    public let anonymousId: String
    public let externalId: String?
}
