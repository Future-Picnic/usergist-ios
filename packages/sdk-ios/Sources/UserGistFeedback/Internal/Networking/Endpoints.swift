import Foundation

/// Path constants for SDK-facing endpoints.
enum SDKEndpoint {
    static let session = "/v1/sdk/session"
    static let sessionRevoke = "/v1/sdk/session/revoke"
    static let instructions = "/v1/sdk/instructions"
    static let instructionsAck = "/v1/sdk/instructions/ack"
    static let basePath = "/v1/sdk"

    static let ingest = "\(basePath)/ingest"
    static let armedTriggers = "\(basePath)/armed-triggers"
    static let armedSurveys = "\(basePath)/armed-surveys"
    static let armedInAppMessages = "\(basePath)/armed-inapp-messages"
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
    static func survey(_ id: String) -> String { "\(basePath)/surveys/\(id)" }
    static func surveyAttempts(_ id: String) -> String { "\(survey(id))/attempts" }
    static func surveyAttempt(_ attemptId: String) -> String {
        "\(basePath)/surveys/attempts/\(attemptId)"
    }
    static func surveyResponses(_ attemptId: String) -> String {
        "\(surveyAttempt(attemptId))/responses"
    }
    static let availableSurveys = "\(basePath)/surveys/available"
    static let resolveSurveyLink = "\(basePath)/surveys/resolve-link"
    static func surveyComplete(_ attemptId: String) -> String {
        "\(surveyAttempt(attemptId))/complete"
    }
    static func surveyAbandon(_ attemptId: String) -> String {
        "\(surveyAttempt(attemptId))/abandon"
    }

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
