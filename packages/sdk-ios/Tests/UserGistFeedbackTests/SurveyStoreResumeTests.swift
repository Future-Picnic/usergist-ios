import XCTest
@testable import UserGistFeedback

final class SurveyStoreResumeTests: XCTestCase {
    private func makeStore(_ storage: Storage) -> SurveyStore {
        SurveyStore(storage: storage, logger: UserGistLogger(debug: false), queue: DispatchQueue(label: "survey-resume-test"))
    }

    func testRestartRetainsLocallyEditedAnswerAgainstLaggingServerSnapshot() throws {
        let storage = try Storage(writeKeyHash: "qa-survey-" + UUID().uuidString)
        let store = makeStore(storage)
        _ = store.upsert(surveyId: "survey", attemptId: "server-attempt", answers: ["recommend": .string("no")], currentQuestionId: "details")
        store.recordAnswer(surveyId: "survey", questionId: "details", value: .string("saved draft"), nextQuestionId: "details")
        let restored = makeStore(storage).upsert(surveyId: "survey", attemptId: "server-attempt", answers: ["recommend": .string("no"), "details": .string("saved draf")], currentQuestionId: "details")
        XCTAssertEqual(restored.attemptId, "server-attempt")
        XCTAssertEqual(restored.answers["details"], .string("saved draft"))
    }

    func testServerChangesToUneditedQuestionsAreRetained() throws {
        let storage = try Storage(writeKeyHash: "qa-survey-" + UUID().uuidString)
        let store = makeStore(storage)
        _ = store.upsert(surveyId: "survey", attemptId: "attempt", answers: [:], currentQuestionId: "details")
        store.recordAnswer(surveyId: "survey", questionId: "details", value: .string("local"), nextQuestionId: "details")
        let restored = store.upsert(surveyId: "survey", attemptId: "attempt", answers: ["recommend": .string("yes")], currentQuestionId: "recommend")
        XCTAssertEqual(restored.answers["recommend"], .string("yes"))
        XCTAssertEqual(restored.answers["details"], .string("local"))
        XCTAssertEqual(restored.currentQuestionId, "details")
    }

    func testNewServerAttemptDoesNotInheritPreviousDraft() throws {
        let storage = try Storage(writeKeyHash: "qa-survey-" + UUID().uuidString)
        let store = makeStore(storage)
        _ = store.begin(surveyId: "survey", attemptId: "old", startQuestionId: "details")
        store.recordAnswer(surveyId: "survey", questionId: "details", value: .string("old account draft"), nextQuestionId: "details")
        let next = store.upsert(surveyId: "survey", attemptId: "new", answers: [:], currentQuestionId: "recommend")
        XCTAssertEqual(next.attemptId, "new")
        XCTAssertTrue(next.answers.isEmpty)
        XCTAssertEqual(next.currentQuestionId, "recommend")
    }
}
