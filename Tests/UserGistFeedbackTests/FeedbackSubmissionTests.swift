import XCTest
@testable import UserGistFeedback

final class FeedbackSubmissionTests: XCTestCase {
    func testDismissalPreservesAnswersInEncodedSubmissionForBothIdentities() throws {
        for externalId in [nil, "identified-user"] as [String?] {
            let info = PromptResponseInfo(
                promptId: "two-question-prompt",
                answers: [.init(questionId: "rating", value: .number(5))],
                dismissed: true,
                latencyMs: 15237
            )
            let payload = SubmitResponsePayload(info: info, identity: .init(
                anonymousId: "anonymous-user", externalId: externalId, properties: nil
            ))
            let data = try JSONEncoder.usergist().encode(payload)
            let decoded = try JSONDecoder.usergist().decode(SubmitResponsePayload.self, from: data)
            XCTAssertEqual(decoded.dismissed, true)
            XCTAssertEqual(decoded.anonymousId, "anonymous-user")
            XCTAssertEqual(decoded.externalId, externalId)
            XCTAssertEqual(decoded.answers?.map(\.questionId), ["rating"])
            guard case .number(let score) = decoded.answers?.first?.value else {
                return XCTFail("The answered rating must survive dismissal and encoding")
            }
            XCTAssertEqual(score, 5)
            XCTAssertEqual(decoded.latencyMs, 15237)
        }
    }

    func testEmptyDismissalAndCompletedResponseKeepTheirOutcomes() throws {
        for dismissed in [true, false] {
            let answers: [PromptAnswerInfo] = dismissed ? [] : [
                .init(questionId: "rating", value: .number(4)),
                .init(questionId: "text", value: .text("More lessons")),
                .init(questionId: "choice", value: .choices(["a", "b"]))
            ]
            let payload = SubmitResponsePayload(
                info: .init(promptId: "prompt", answers: answers, dismissed: dismissed, latencyMs: 100),
                identity: .init(anonymousId: "anonymous-user", externalId: nil, properties: nil)
            )
            let encoded = try JSONEncoder.usergist().encode(payload)
            let decoded = try JSONDecoder.usergist().decode(SubmitResponsePayload.self, from: encoded)
            XCTAssertEqual(decoded.dismissed, dismissed)
            XCTAssertEqual(decoded.answers?.map(\.questionId), answers.map(\.questionId))
            XCTAssertNotNil(UUID(uuidString: decoded.idempotencyKey))
        }
    }
}
