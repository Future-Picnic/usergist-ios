import UIKit
import XCTest
@testable import UserGistFeedback

@MainActor
final class InAppPresenterTests: XCTestCase {
    func testModalCardUsesItsContentHeightAndExposesActions() throws {
        let message = try JSONDecoder().decode(
            ArmedInAppMessage.self,
            from: Data(#"""
            {
              "messageId":"message-1",
              "eventName":"demo_in_app_requested",
              "clientSideEligible":true,
              "format":"modal",
              "title":"The inside scoop",
              "body":"A useful message should be visible above the backdrop.",
              "backdropEnabled":true,
              "ctas":[{"label":"Works","action":"dismiss"}]
            }
            """#.utf8)
        )
        let controller = InAppMessageController(
            message: message,
            theme: .fallback,
            onDismiss: { _ in },
            onCta: { _, _ in }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        let card = descendants(of: controller.view, type: UIView.self)
            .first { $0.accessibilityIdentifier == "usergist_inapp_card" }
        let buttons = descendants(of: controller.view, type: UIButton.self)

        XCTAssertGreaterThan(card?.frame.height ?? 0, 150)
        XCTAssertTrue(buttons.contains { $0.accessibilityLabel == "Close" })
        XCTAssertTrue(buttons.contains { $0.title(for: .normal) == "Works" && $0.isEnabled })
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = child as? T
            return (current.map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }
}
