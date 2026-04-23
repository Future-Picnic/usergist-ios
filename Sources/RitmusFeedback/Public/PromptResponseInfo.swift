import Foundation

/// A decoded value answering a single question.
///
/// Callbacks receive this strongly-typed variant rather than `Any` so
/// integrators can switch on it exhaustively.
public enum PromptAnswerValue: Equatable, Sendable {
    /// Numeric answer (rating / NPS / single-select choice index).
    case number(Double)
    /// Free text answer.
    case text(String)
    /// Multi-select choice IDs.
    case choices([String])
    /// User dismissed the question without answering.
    case none
}

/// A single question answer included in a prompt response.
public struct PromptAnswerInfo: Equatable, Sendable {
    public let questionId: String
    public let value: PromptAnswerValue

    public init(questionId: String, value: PromptAnswerValue) {
        self.questionId = questionId
        self.value = value
    }
}

/// Structured information about a submitted prompt response.
///
/// Delivered via `Ritmus.shared.onResponse` when the user completes or
/// dismisses a feedback prompt.
public struct PromptResponseInfo: Equatable, Sendable {
    public let promptId: String
    public let answers: [PromptAnswerInfo]
    public let dismissed: Bool
    public let latencyMs: Int

    public init(
        promptId: String,
        answers: [PromptAnswerInfo],
        dismissed: Bool,
        latencyMs: Int
    ) {
        self.promptId = promptId
        self.answers = answers
        self.dismissed = dismissed
        self.latencyMs = latencyMs
    }
}
