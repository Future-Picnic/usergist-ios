import XCTest
@testable import UserGistFeedback

final class FeedbackSubmissionTests: XCTestCase {
    func testFeedbackSubmissionIncludesNativeContext() throws {
        let payload = SubmitResponsePayload(
            info: .init(promptId: "prompt", answers: [], dismissed: true, latencyMs: 10),
            identity: .init(anonymousId: "anonymous-user", externalId: nil, properties: nil)
        )
        let encoded = try JSONEncoder.usergist().encode(payload)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["sdkVersion"] as? String, UserGistConfig.currentSDKVersion)
    }

    func testFeedbackRetainsItsSubmissionContextWhenRestored() throws {
        let payload = SubmitResponsePayload(
            info: .init(promptId: "prompt", answers: [], dismissed: false, latencyMs: 10),
            identity: .init(anonymousId: "anonymous-user", externalId: "account-a", properties: nil),
            sdkVersion: "0.2.0",
            appVersion: "9.2"
        )
        let restored = try JSONDecoder.usergist().decode(
            SubmitResponsePayload.self, from: JSONEncoder.usergist().encode(payload)
        )
        XCTAssertEqual(restored.platform, "ios")
        XCTAssertEqual(restored.sdkVersion, "0.2.0")
        XCTAssertEqual(restored.appVersion, "9.2")
        XCTAssertEqual(restored.idempotencyKey, payload.idempotencyKey)
        XCTAssertEqual(restored.externalId, "account-a")
    }

    func testLegacyQueuedFeedbackStillDecodesWithoutDeviceContext() throws {
        let legacy = Data(#"{"idempotencyKey":"retained-response-id","promptId":"prompt","anonymousId":"anonymous-user","answers":[],"dismissed":false,"latencyMs":10}"#.utf8)
        let payload = try JSONDecoder.usergist().decode(SubmitResponsePayload.self, from: legacy)
        let encoded = try JSONEncoder.usergist().encode(payload)
        let restored = try JSONDecoder.usergist().decode(SubmitResponsePayload.self, from: encoded)
        XCTAssertEqual(restored.idempotencyKey, "retained-response-id")
        XCTAssertEqual(restored.anonymousId, "anonymous-user")
        XCTAssertEqual(restored.dismissed, false)
    }

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
