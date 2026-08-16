import XCTest
@testable import UserGistFeedback

final class PromptDecodingTests: XCTestCase {
    private let fixtureJSON: String = """
    {
      "triggers": [
        {
          "promptId": "p_rating",
          "eventName": "completed_checkout",
          "segmentRules": {
            "userProperties": [
              { "key": "plan", "op": "eq", "value": "free" }
            ],
            "eventCounts": [
              { "eventName": "completed_checkout", "op": "gte", "count": 3, "windowDays": 7 }
            ]
          },
          "frequency": { "perPromptDays": 14, "perUserDays": 1 },
          "prompt": {
            "id": "p_rating",
            "questions": [
              {
                "type": "rating",
                "id": "q1",
                "title": "How was checkout?",
                "subtitle": "Be honest.",
                "scale": 5,
                "lowLabel": "Bad",
                "highLabel": "Great"
              }
            ],
            "theme": { "colors": { "primary": "#FF6600" }, "radius": 12 }
          }
        },
        {
          "promptId": "p_nps",
          "eventName": "opened_app",
          "frequency": {},
          "prompt": {
            "id": "p_nps",
            "questions": [
              { "type": "nps", "id": "qnps", "title": "Would you recommend us?", "followUp": "Why?" }
            ]
          }
        },
        {
          "promptId": "p_mc",
          "eventName": "dismissed_tutorial",
          "frequency": {},
          "prompt": {
            "id": "p_mc",
            "questions": [
              {
                "type": "multiple_choice",
                "id": "qmc",
                "title": "Why did you skip?",
                "options": [
                  { "id": "o1", "label": "Too long" },
                  { "id": "o2", "label": "Not useful" }
                ],
                "multiSelect": true
              }
            ]
          }
        },
        {
          "promptId": "p_text",
          "eventName": "rated_low",
          "frequency": {},
          "prompt": {
            "id": "p_text",
            "questions": [
              {
                "type": "short_text",
                "id": "qtxt",
                "title": "Tell us more",
                "placeholder": "Optional feedback",
                "maxLength": 280
              }
            ]
          }
        }
      ],
      "serverTime": "2026-04-21T10:00:00.000Z",
      "nextSyncMs": 60000
    }
    """

    func test_decodesAllFourQuestionTypes() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let decoded = try JSONDecoder.usergist().decode(ArmedTriggersResponse.self, from: data)
        XCTAssertEqual(decoded.triggers.count, 4)
        XCTAssertEqual(decoded.nextSyncMs, 60000)

        // Rating
        guard case .rating(let r) = decoded.triggers[0].prompt.questions[0] else {
            XCTFail("expected rating"); return
        }
        XCTAssertEqual(r.scale, 5)
        XCTAssertEqual(r.lowLabel, "Bad")

        // NPS
        guard case .nps(let nps) = decoded.triggers[1].prompt.questions[0] else {
            XCTFail("expected nps"); return
        }
        XCTAssertEqual(nps.followUp, "Why?")

        // Multiple choice
        guard case .multipleChoice(let mc) = decoded.triggers[2].prompt.questions[0] else {
            XCTFail("expected multiple_choice"); return
        }
        XCTAssertEqual(mc.options.count, 2)
        XCTAssertEqual(mc.multiSelect, true)

        // Short text
        guard case .shortText(let t) = decoded.triggers[3].prompt.questions[0] else {
            XCTFail("expected short_text"); return
        }
        XCTAssertEqual(t.maxLength, 280)
    }

    func test_roundTripEncodeDecode() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let decoded = try JSONDecoder.usergist().decode(ArmedTriggersResponse.self, from: data)
        let reencoded = try JSONEncoder.usergist().encode(decoded)
        let redecoded = try JSONDecoder.usergist().decode(ArmedTriggersResponse.self, from: reencoded)
        XCTAssertEqual(decoded.triggers.count, redecoded.triggers.count)
        for (a, b) in zip(decoded.triggers, redecoded.triggers) {
            XCTAssertEqual(a.promptId, b.promptId)
            XCTAssertEqual(a.eventName, b.eventName)
            XCTAssertEqual(a.prompt.questions.count, b.prompt.questions.count)
        }
    }

    func test_segmentRulesDecoding() throws {
        let data = fixtureJSON.data(using: .utf8)!
        let decoded = try JSONDecoder.usergist().decode(ArmedTriggersResponse.self, from: data)
        let first = decoded.triggers[0]
        let rules = first.segmentRules
        XCTAssertEqual(rules?.userProperties?.count, 1)
        XCTAssertEqual(rules?.eventCounts?.first?.windowDays, 7)
    }
}
