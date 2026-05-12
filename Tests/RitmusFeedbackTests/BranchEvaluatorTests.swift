import XCTest
@testable import RitmusFeedback

// Mirrors the assertions used in
// packages/sdk-core/src/evaluate/branch.test.ts so an identical
// SurveyFlow / answer set yields the same next-question id on every
// platform.
final class BranchEvaluatorTests: XCTestCase {

    private func makeFlow() -> SurveyFlow {
        SurveyFlow(
            startQuestionId: "q1",
            questions: [
                SurveyQuestion(
                    id: "q1", kind: .rating, text: "rate", required: true,
                    helperText: nil, choices: nil,
                    minRating: 1, maxRating: 5,
                    minLabel: nil, maxLabel: nil, placeholder: nil
                ),
                SurveyQuestion(
                    id: "q2", kind: .shortText, text: "why?", required: false,
                    helperText: nil, choices: nil,
                    minRating: nil, maxRating: nil,
                    minLabel: nil, maxLabel: nil, placeholder: nil
                ),
                SurveyQuestion(
                    id: "q3", kind: .shortText, text: "what would help?", required: false,
                    helperText: nil, choices: nil,
                    minRating: nil, maxRating: nil,
                    minLabel: nil, maxLabel: nil, placeholder: nil
                ),
            ],
            branches: [
                SurveyBranch(
                    fromQuestionId: "q1",
                    condition: SurveyBranchCondition(op: .lte, value: .int(2)),
                    toQuestionId: "q3"
                ),
            ]
        )
    }

    func test_branchTakesPathOnMatch() {
        let flow = makeFlow()
        let next = BranchEvaluator.nextQuestionId(
            flow: flow,
            currentQuestionId: "q1",
            answers: ["q1": .int(2)]
        )
        XCTAssertEqual(next, "q3")
    }

    func test_branchFallsThroughOnNoMatch() {
        let flow = makeFlow()
        let next = BranchEvaluator.nextQuestionId(
            flow: flow,
            currentQuestionId: "q1",
            answers: ["q1": .int(5)]
        )
        XCTAssertEqual(next, "q2")
    }

    func test_endSentinelReturnsNil() {
        let flow = SurveyFlow(
            startQuestionId: "q1",
            questions: [
                SurveyQuestion(
                    id: "q1", kind: .rating, text: "x", required: nil,
                    helperText: nil, choices: nil,
                    minRating: nil, maxRating: nil,
                    minLabel: nil, maxLabel: nil, placeholder: nil
                ),
            ],
            branches: [
                SurveyBranch(
                    fromQuestionId: "q1",
                    condition: SurveyBranchCondition(op: .answered, value: nil),
                    toQuestionId: SURVEY_END_SENTINEL
                ),
            ]
        )
        let next = BranchEvaluator.nextQuestionId(
            flow: flow,
            currentQuestionId: "q1",
            answers: ["q1": .int(3)]
        )
        XCTAssertNil(next)
    }

    func test_answeredAndUnansweredOperators() {
        XCTAssertTrue(
            BranchEvaluator.evaluateBranchCondition(
                SurveyBranchCondition(op: .answered, value: nil),
                answer: .string("hi")
            )
        )
        XCTAssertFalse(
            BranchEvaluator.evaluateBranchCondition(
                SurveyBranchCondition(op: .answered, value: nil),
                answer: .string("")
            )
        )
        XCTAssertTrue(
            BranchEvaluator.evaluateBranchCondition(
                SurveyBranchCondition(op: .unanswered, value: nil),
                answer: nil
            )
        )
    }

    func test_estimateProgress() {
        let flow = makeFlow()
        XCTAssertEqual(BranchEvaluator.estimateProgress(flow: flow, currentQuestionId: "q2"), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(BranchEvaluator.estimateProgress(flow: flow, currentQuestionId: nil), 1.0)
    }
}
