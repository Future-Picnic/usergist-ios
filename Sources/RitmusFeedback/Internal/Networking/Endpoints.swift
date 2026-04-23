import Foundation

/// Path constants for SDK-facing endpoints.
enum SDKEndpoint {
    static let basePath = "/v1/sdk"

    static let ingest = "\(basePath)/ingest"
    static let armedTriggers = "\(basePath)/armed-triggers"
    static let consent = "\(basePath)/consent"
    static let identify = "\(basePath)/identify"
    static let responses = "\(basePath)/responses"
}
