import Foundation

/// Pure prompt-navigation and response policy shared by the renderer and tests.
enum PromptFlow {
    static func shouldAutoAdvance(_ question: Question) -> Bool {
        switch question {
        case .rating: return true
        case .nps(let value): return value.followUp?.isEmpty != false
        case .multipleChoice(let value): return value.multiSelect != true
        case .shortText: return false
        }
    }

    static func needsExplicitNext(_ question: Question) -> Bool {
        switch question {
        case .nps(let value): return value.followUp?.isEmpty == false
        case .multipleChoice(let value): return value.multiSelect == true
        case .shortText: return true
        default: return false
        }
    }

    static func orderedAnswers(
        prompt: ClientPrompt,
        answers: [String: PromptAnswerValue]
    ) -> [PromptAnswerInfo] {
        var result: [PromptAnswerInfo] = []
        for question in prompt.questions {
            if let answer = answers[question.id], hasValue(answer) {
                result.append(PromptAnswerInfo(questionId: question.id, value: answer))
            }
            let followUpId = "\(question.id)__followUp"
            if let answer = answers[followUpId], hasValue(answer) {
                result.append(PromptAnswerInfo(questionId: followUpId, value: answer))
            }
        }
        return result
    }

    static func hasValue(_ answer: PromptAnswerValue) -> Bool {
        switch answer {
        case .none: return false
        case .text(let value): return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choices(let ids): return !ids.isEmpty
        case .number: return true
        }
    }
}
