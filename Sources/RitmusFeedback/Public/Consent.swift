import Foundation

/// User consent flags for SDK data purposes (GDPR-aligned).
///
/// The SDK hard-blocks all network transport until the `feedback` purpose
/// is granted. Dashboards can still call `track` / `identify` before
/// consent — those events are queued and released once consent is set.
public struct Consent: Codable, Equatable, Sendable {
    /// Permission to use data for product analytics.
    public var analytics: Bool?
    /// Permission to render feedback prompts and submit responses.
    public var feedback: Bool?

    public init(analytics: Bool? = nil, feedback: Bool? = nil) {
        self.analytics = analytics
        self.feedback = feedback
    }

    /// Whether the transport layer may ship data to the backend.
    public var allowsTransport: Bool {
        feedback == true
    }
}
