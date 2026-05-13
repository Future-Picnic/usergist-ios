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

    // Surveys
    static func surveyFlow(_ id: String) -> String { "\(basePath)/surveys/\(id)/flow" }
    static let availableSurveys = "\(basePath)/surveys/available"
    static let resolveSurveyLink = "\(basePath)/surveys/resolve"

    // Feature requests
    static let requests = "\(basePath)/requests"
    static func request(_ id: String) -> String { "\(basePath)/requests/\(id)" }
    static func requestVote(_ id: String) -> String { "\(basePath)/requests/\(id)/vote" }
    static func requestFollow(_ id: String) -> String { "\(basePath)/requests/\(id)/follow" }
    static func requestComments(_ id: String) -> String { "\(basePath)/requests/\(id)/comments" }
    static func requestComment(_ requestId: String, _ commentId: String) -> String {
        "\(basePath)/requests/\(requestId)/comments/\(commentId)"
    }
    static let requestBranding = "\(basePath)/request-branding"
}
