import XCTest
@testable import UserGistFeedback

final class SurveyContractTests: XCTestCase {
    func test_decodesReactNativeSurveyWireContract() throws {
        let data = Data(
            """
            {
              "startQuestionId": "q1",
              "questions": [
                {
                  "id": "q1",
                  "type": "single_choice",
                  "title": "Choose a plan",
                  "subtitle": "One answer",
                  "required": true,
                  "options": [
                    {"id": "free", "label": "Free"},
                    {"id": "pro", "label": "Pro"}
                  ]
                },
                {
                  "id": "q2",
                  "type": "rating",
                  "title": "Rate it",
                  "scale": 10,
                  "lowLabel": "Poor",
                  "highLabel": "Great"
                },
                {
                  "id": "q3",
                  "type": "info_screen",
                  "title": "Done",
                  "body": "Thank you"
                }
              ],
              "branches": [
                {
                  "fromQuestionId": "q1",
                  "condition": {"op": "eq", "value": "free"},
                  "toQuestionId": "__end__"
                }
              ],
              "progressStyle": "bar",
              "backNavigation": true
            }
            """.utf8
        )

        let flow = try JSONDecoder.usergist().decode(SurveyFlow.self, from: data)

        XCTAssertEqual(flow.questions.map(\.type), [.singleChoice, .rating, .infoScreen])
        XCTAssertEqual(flow.questions[0].title, "Choose a plan")
        XCTAssertEqual(flow.questions[0].options?.map(\.id), ["free", "pro"])
        XCTAssertEqual(flow.questions[1].scale, 10)
        let rating = SurveyRatingInput.promptQuestion(for: flow.questions[1])
        XCTAssertEqual(rating.display, .stars)
        XCTAssertEqual(rating.scale, 10)
        XCTAssertEqual(rating.lowLabel, "Poor")
        XCTAssertEqual(rating.highLabel, "Great")
        XCTAssertEqual(flow.questions[2].body, "Thank you")
        XCTAssertNil(
            BranchEvaluator.nextQuestionId(
                flow: flow,
                currentQuestionId: "q1",
                answers: ["q1": .string("free")]
            )
        )
        XCTAssertEqual(
            BranchEvaluator.nextQuestionId(
                flow: flow,
                currentQuestionId: "q1",
                answers: ["q1": .string("pro")]
            ),
            "q2"
        )
    }

    func test_answerValuesRoundTripNullAndMixedScalarShapes() throws {
        let values: [SurveyAnswerValue] = [
            .null,
            .bool(true),
            .int(5),
            .double(2.5),
            .string("answer"),
            .stringArray(["a", "b"]),
            .intArray([1, 2])
        ]
        let encoded = try JSONEncoder.usergist().encode(values)
        let decoded = try JSONDecoder.usergist().decode([SurveyAnswerValue].self, from: encoded)
        XCTAssertEqual(decoded, values)
    }

    func test_decodesArmedSurveyTargetingAndEmbeddedContent() throws {
        let data = Data(#"""
        {"surveys":[{"campaignId":"survey-1","eventName":"checkout_completed",
          "clientSideEligible":false,"cooldownSeconds":90,
          "segmentRules":{"userProperties":[{"key":"plan","op":"eq","value":"pro"}]},
          "frequencyCap":{"perCampaignDays":7,"perPillarDays":1},
          "survey":{"id":"survey-1","name":"Checkout","flow":{"startQuestionId":"q1",
            "questions":[{"id":"q1","type":"info_screen","title":"Done"}],
            "branches":[],"progressStyle":"bar","backNavigation":true}}}]}
        """#.utf8)

        let response = try JSONDecoder.usergist().decode(ArmedSurveysResponse.self, from: data)
        let armed = try XCTUnwrap(response.surveys.first)
        XCTAssertEqual(armed.clientSideEligible, false)
        XCTAssertEqual(armed.cooldownSeconds, 90)
        XCTAssertEqual(armed.frequencyCap.perCampaignDays, 7)
        XCTAssertEqual(armed.survey.name, "Checkout")
    }

    func test_completionAcceptanceRejectsResetRaceAndPermanentFailure() {
        XCTAssertTrue(Runtime.shouldAcceptSurveyCompletion(
            delivered: false,
            mutationQueued: true,
            deliveryGeneration: 4,
            currentGeneration: 4,
            resetInProgress: false
        ))
        XCTAssertFalse(Runtime.shouldAcceptSurveyCompletion(
            delivered: true,
            mutationQueued: false,
            deliveryGeneration: 4,
            currentGeneration: 5,
            resetInProgress: false
        ))
        XCTAssertFalse(Runtime.shouldAcceptSurveyCompletion(
            delivered: true,
            mutationQueued: false,
            deliveryGeneration: 4,
            currentGeneration: 4,
            resetInProgress: true
        ))
        XCTAssertFalse(Runtime.shouldAcceptSurveyCompletion(
            delivered: false,
            mutationQueued: false,
            deliveryGeneration: 4,
            currentGeneration: 4,
            resetInProgress: false
        ))
    }
}
