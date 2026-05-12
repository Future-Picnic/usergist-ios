import Foundation

// PORTED FROM: packages/sdk-core/src/types/survey.ts
//
// Native mirrors of the survey flow types. Field names match the TS types
// verbatim so JSON payloads from the API decode without custom coding
// keys. Optional fields use `?` to mirror TS optionality.

public enum SurveyQuestionKind: String, Codable, Sendable {
    case singleChoice = "single_choice"
    case multiChoice = "multi_choice"
    case rating
    case nps
    case shortText = "short_text"
    case longText = "long_text"
    case likert
    case ranking
    case date
    case info
}

public struct SurveyChoice: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
}

/// Per-question answer value. Surveys send heterogenous payloads (numbers,
/// strings, string arrays) so we wrap them in an enum that round-trips
/// through JSONDecoder.
public enum SurveyAnswerValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case stringArray([String])
    case intArray([Int])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String].self) { self = .stringArray(v); return }
        if let v = try? c.decode([Int].self) { self = .intArray(v); return }
        throw DecodingError.typeMismatch(
            SurveyAnswerValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "unrecognised answer value"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .stringArray(let v): try c.encode(v)
        case .intArray(let v): try c.encode(v)
        }
    }

    /// Treats empty string / empty array as "unanswered". Matches the
    /// "empty answer" semantics used by the RN branch evaluator.
    public var isAnswered: Bool {
        switch self {
        case .string(let v): return !v.isEmpty
        case .stringArray(let v): return !v.isEmpty
        case .intArray(let v): return !v.isEmpty
        default: return true
        }
    }
}

public struct SurveyQuestion: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: SurveyQuestionKind
    public let text: String
    public let required: Bool?
    public let helperText: String?
    public let choices: [SurveyChoice]?
    public let minRating: Int?
    public let maxRating: Int?
    public let minLabel: String?
    public let maxLabel: String?
    public let placeholder: String?
}

public enum SurveyBranchOp: String, Codable, Sendable {
    case eq, neq, lt, lte, gt, gte
    case includes
    case notIncludes = "not_includes"
    case answered, unanswered
}

public struct SurveyBranchCondition: Codable, Sendable, Equatable {
    public let op: SurveyBranchOp
    public let value: SurveyAnswerValue?
}

public struct SurveyBranch: Codable, Sendable, Equatable {
    public let fromQuestionId: String
    public let condition: SurveyBranchCondition
    public let toQuestionId: String
}

public let SURVEY_END_SENTINEL = "__end__"

public struct SurveyFlow: Codable, Sendable, Equatable {
    public let startQuestionId: String
    public let questions: [SurveyQuestion]
    public let branches: [SurveyBranch]
}
