import XCTest
@testable import UserGistFeedback

// Mirrors the assertions used in
// packages/sdk-core/src/evaluate/branch.test.ts so an identical
// SurveyFlow / answer set yields the same next-question id on every
// platform.
final class BranchEvaluatorTests: XCTestCase {

    private func makeQuestion(
        id: String,
        type: SurveyQuestionKind,
        title: String,
        required: Bool? = nil,
        scale: Int? = nil
    ) -> SurveyQuestion {
        SurveyQuestion(
            id: id,
            type: type,
            title: title,
            subtitle: nil,
            required: required,
            imageUrl: nil,
            options: nil,
            allowOther: nil,
            minSelections: nil,
            maxSelections: nil,
            scale: scale,
            style: nil,
            lowLabel: nil,
            highLabel: nil,
            labels: nil,
            placeholder: nil,
            maxLength: nil,
            items: nil,
            minDate: nil,
            maxDate: nil,
            body: nil
        )
    }

    private func makeFlow() -> SurveyFlow {
        SurveyFlow(
            startQuestionId: "q1",
            questions: [
                makeQuestion(id: "q1", type: .rating, title: "rate", required: true, scale: 5),
                makeQuestion(id: "q2", type: .shortText, title: "why?", required: false),
                makeQuestion(id: "q3", type: .shortText, title: "what would help?", required: false),
            ],
            branches: [
                SurveyBranch(
                    fromQuestionId: "q1",
                    condition: SurveyBranchCondition(op: .lte, value: .int(2)),
                    toQuestionId: "q3"
                ),
            ],
            progressStyle: "bar",
            backNavigation: true,
            endScreen: nil
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
                makeQuestion(id: "q1", type: .rating, title: "x"),
            ],
            branches: [
                SurveyBranch(
                    fromQuestionId: "q1",
                    condition: SurveyBranchCondition(op: .answered, value: nil),
                    toQuestionId: SURVEY_END_SENTINEL
                ),
            ],
            progressStyle: "bar",
            backNavigation: true,
            endScreen: nil
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
