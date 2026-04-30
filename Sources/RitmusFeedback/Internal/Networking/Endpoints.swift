import Foundation

/// Path constants for SDK-facing endpoints.
enum SDKEndpoint {
    static let basePath = "/v1/sdk"

    static let ingest = "\(basePath)/ingest"
    static let armedTriggers = "\(basePath)/armed-triggers"
    static let consent = "\(basePath)/consent"
    static let identify = "\(basePath)/identify"
    static let responses = "\(basePath)/responses"

    // Push
    static let pushRegisterToken = "\(basePath)/push/register-token"
    static let pushUpdateToken = "\(basePath)/push/update-token"
    static let pushInvalidateToken = "\(basePath)/push/invalidate-token"
    static let pushRebind = "\(basePath)/push/rebind"
    static let pushAppOpen = "\(basePath)/push/app-open"
    static let pushDelivered = "\(basePath)/push/delivered"
    static let pushDisplayed = "\(basePath)/push/displayed"
    static let pushDismissed = "\(basePath)/push/dismissed"
    static let pushSilentAck = "\(basePath)/push/silent-ack"
    static let pushChannels = "\(basePath)/push/channels"
    static let pushChannelSubscription = "\(basePath)/push/channels/subscription"
}
