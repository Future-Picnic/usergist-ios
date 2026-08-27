import XCTest
@testable import UserGistFeedback

final class InAppContractTests: XCTestCase {
    func testDecodesAuthenticatedInstructionMessage() throws {
        let data = Data(#"""
        {
          "messageId":"message-1",
          "eventName":"checkout_completed",
          "clientSideEligible":true,
          "format":"slideup",
          "title":"How did checkout go?",
          "body":"Tell us while it is fresh.",
          "backdropEnabled":false,
          "autoDismissSeconds":4,
          "ctas":[{
            "label":"Share feedback",
            "action":"custom_event",
            "target":"checkout_feedback_requested"
          }],
          "screenAllowlist":["Checkout"],
          "screenDenylist":[],
          "forceShow":false
        }
        """#.utf8)

        let message = try JSONDecoder().decode(ArmedInAppMessage.self, from: data)

        XCTAssertEqual(message.messageId, "message-1")
        XCTAssertEqual(message.format, .slideup)
        XCTAssertFalse(message.backdropEnabled)
        XCTAssertEqual(message.autoDismissSeconds, 4)
        XCTAssertEqual(message.ctas.first?.action, .customEvent)
        XCTAssertEqual(message.screenAllowlist, ["Checkout"])
    }

    func testOlderPayloadDefaultsOptionalCollectionsAndBackdrop() throws {
        let data = Data(#"""
        {
          "messageId":"message-legacy",
          "format":"modal",
          "title":"A message"
        }
        """#.utf8)

        let message = try JSONDecoder().decode(ArmedInAppMessage.self, from: data)

        XCTAssertEqual(message.eventName, "server")
        XCTAssertTrue(message.backdropEnabled)
        XCTAssertTrue(message.ctas.isEmpty)
        XCTAssertFalse(message.forceShow)
    }
}
