import Foundation

/// Summary of a survey currently available to the user.
public struct SurveySummary: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let mode: String
    public let source: String
    public let resumableAttemptId: String?

    public init(id: String, name: String, mode: String, source: String, resumableAttemptId: String? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
        self.source = source
        self.resumableAttemptId = resumableAttemptId
    }
}

/// Lifecycle callbacks for survey rendering handled by the host app.
public struct SurveyHandlers {
    public var onInvite: ((SurveySummary) -> Void)?
    public var onShow: ((String) -> Void)?
    public var onComplete: ((String, String) -> Void)?
    public var onAbandon: ((String, String) -> Void)?

    public init(
        onInvite: ((SurveySummary) -> Void)? = nil,
        onShow: ((String) -> Void)? = nil,
        onComplete: ((String, String) -> Void)? = nil,
        onAbandon: ((String, String) -> Void)? = nil
    ) {
        self.onInvite = onInvite
        self.onShow = onShow
        self.onComplete = onComplete
        self.onAbandon = onAbandon
    }
}
