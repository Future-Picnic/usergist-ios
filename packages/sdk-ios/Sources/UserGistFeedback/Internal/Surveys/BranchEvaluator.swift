import Foundation

// PORTED FROM: packages/sdk-core/src/evaluate/branch.ts
//
// Pure Swift port of the shared branch DSL evaluator. The function set
// is intentionally identical so a SurveyFlow / answer set evaluated
// here yields the same path as on the server / RN / dashboard preview.

enum BranchEvaluator {

    static func evaluateBranchCondition(
        _ cond: SurveyBranchCondition,
        answer: SurveyAnswerValue?
    ) -> Bool {
        switch cond.op {
        case .answered:
            return answer != nil && answer!.isAnswered
        case .unanswered:
            return answer == nil || !answer!.isAnswered
        default:
            break
        }
        guard let answer = answer else { return false }
        switch cond.op {
        case .eq:
            return answer == cond.value
        case .neq:
            return answer != cond.value
        case .lt, .lte, .gt, .gte:
            guard let aN = numberValue(answer), let cN = numberValue(cond.value) else { return false }
            switch cond.op {
            case .lt: return aN < cN
            case .lte: return aN <= cN
            case .gt: return aN > cN
            case .gte: return aN >= cN
            default: return false
            }
        case .includes:
            return arrayContains(answer, value: cond.value)
        case .notIncludes:
            return !arrayContains(answer, value: cond.value)
        case .answered, .unanswered:
            return false // handled above
        }
    }

    static func nextQuestionId(
        flow: SurveyFlow,
        currentQuestionId: String,
        answers: [String: SurveyAnswerValue]
    ) -> String? {
        let branches = flow.branches.filter { $0.fromQuestionId == currentQuestionId }
        let answer = answers[currentQuestionId]
        for branch in branches {
            if evaluateBranchCondition(branch.condition, answer: answer) {
                if branch.toQuestionId == SURVEY_END_SENTINEL { return nil }
                return branch.toQuestionId
            }
        }
        return defaultNext(flow: flow, currentQuestionId: currentQuestionId)
    }

    static func defaultNext(flow: SurveyFlow, currentQuestionId: String) -> String? {
        let idx = flow.questions.firstIndex(where: { $0.id == currentQuestionId }) ?? -1
        if idx < 0 || idx >= flow.questions.count - 1 { return nil }
        return flow.questions[idx + 1].id
    }

    static func findQuestion(flow: SurveyFlow, questionId: String) -> SurveyQuestion? {
        flow.questions.first(where: { $0.id == questionId })
    }

    static func findQuestionIndex(flow: SurveyFlow, questionId: String) -> Int {
        flow.questions.firstIndex(where: { $0.id == questionId }) ?? -1
    }

    static func estimateProgress(flow: SurveyFlow, currentQuestionId: String?) -> Double {
        guard let id = currentQuestionId else { return 1 }
        let idx = findQuestionIndex(flow: flow, questionId: id)
        if idx < 0 { return 0 }
        return Double(idx + 1) / Double(max(1, flow.questions.count))
    }

    static func reachableQuestions(flow: SurveyFlow, startId: String? = nil) -> Set<String> {
        let start = startId ?? flow.startQuestionId
        var visited = Set<String>()
        var stack: [String] = [start]
        while let id = stack.popLast() {
            if visited.contains(id) { continue }
            visited.insert(id)
            for b in flow.branches where b.fromQuestionId == id {
                if b.toQuestionId != SURVEY_END_SENTINEL {
                    stack.append(b.toQuestionId)
                }
            }
            if let idx = flow.questions.firstIndex(where: { $0.id == id }),
               idx >= 0, idx < flow.questions.count - 1 {
                stack.append(flow.questions[idx + 1].id)
            }
        }
        return visited
    }

    // MARK: - Helpers

    private static func numberValue(_ v: SurveyAnswerValue?) -> Double? {
        switch v {
        case .int(let n): return Double(n)
        case .double(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    private static func arrayContains(_ answer: SurveyAnswerValue, value: SurveyAnswerValue?) -> Bool {
        guard let value = value else { return false }
        switch (answer, value) {
        case let (.stringArray(arr), .string(s)):
            return arr.contains(s)
        case let (.intArray(arr), .int(n)):
            return arr.contains(n)
        case let (.intArray(arr), .double(n)):
            return arr.contains(Int(n))
        default:
            return false
        }
    }
}
