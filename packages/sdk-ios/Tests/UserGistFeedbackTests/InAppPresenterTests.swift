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

    private func message(format: String, ctas: String = #"[{"label":"Works","action":"dismiss"}]"#,
                         image: Bool = false) throws -> ArmedInAppMessage {
        let imageField = image ? #","imageUrl":"https://example.invalid/hero.png""# : ""
        return try JSONDecoder().decode(ArmedInAppMessage.self, from: Data("""
        {"messageId":"m","eventName":"e","format":"\(format)","title":"The inside scoop",
         "body":"A useful message should be visible above the backdrop.","backdropEnabled":true,
         "ctas":\(ctas)\(imageField)}
        """.utf8))
    }

    private func layout(_ message: ArmedInAppMessage, size: CGSize) -> (UIViewController, UIView, UIWindow) {
        let controller = InAppMessageController(message: message, theme: .fallback,
                                                onDismiss: { _ in }, onCta: { _, _ in })
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let card = descendants(of: controller.view, type: UIView.self)
            .first { $0.accessibilityIdentifier == "usergist_inapp_card" } ?? UIView()
        return (controller, card, window)
    }

    func testLandscapeCardStaysACentredCardWithinTheReadableMeasure() throws {
        let (controller, card, window) = layout(try message(format: "modal"), size: CGSize(width: 874, height: 402))
        defer { window.isHidden = true }
        XCTAssertLessThanOrEqual(card.frame.width, SurfaceMetrics.contentMaxWidth + 0.5)
        XCTAssertEqual(card.frame.midX, controller.view.bounds.midX, accuracy: 1)
        XCTAssertEqual(card.layer.cornerRadius, ResolvedTheme.fallback.radius)
        XCTAssertLessThanOrEqual(card.frame.maxY, controller.view.bounds.maxY)
    }

    func testSlideUpFloatsAsAnInsetCardAndKeepsItsImage() throws {
        let (controller, card, window) = layout(try message(format: "slideup", image: true),
                                                size: CGSize(width: 402, height: 874))
        defer { window.isHidden = true }
        let bounds = controller.view.bounds
        XCTAssertEqual(card.frame.minX, 12, accuracy: 0.5)
        XCTAssertEqual(card.frame.maxX, bounds.maxX - 12, accuracy: 0.5)
        XCTAssertLessThanOrEqual(card.frame.maxY, bounds.maxY - 16)
        XCTAssertEqual(card.layer.cornerRadius, ResolvedTheme.fallback.radius)
        XCTAssertEqual(card.layer.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                                  .layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        XCTAssertEqual(descendants(of: card, type: SurfaceRemoteImageView.self).count, 1)
    }

    func testLongCtaLabelsWrapInsteadOfTruncating() throws {
        let long = "Open the full release notes and see every improvement in detail"
        let ctas = #"[{"label":"\#(long)","action":"dismiss"},{"label":"Remind me later about this update","action":"dismiss"}]"#
        let (_, card, window) = layout(try message(format: "modal", ctas: ctas), size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        let primary = try XCTUnwrap(descendants(of: card, type: SurfacePrimaryButton.self).first)
        XCTAssertEqual(primary.titleLabel?.numberOfLines, 0)
        XCTAssertGreaterThan(primary.bounds.height, SurfaceMetrics.primaryMinHeight, "Wrapped label grows the button")
        XCTAssertEqual(descendants(of: card, type: SurfaceSecondaryButton.self).count, 1)
        let close = try XCTUnwrap(descendants(of: card, type: UIButton.self).first { $0.accessibilityLabel == "Close" })
        XCTAssertLessThan(close.convert(close.bounds, to: card).midX, card.bounds.midX, "Close is leading")
    }

    func testFullScreenUsesThemeBackground() throws {
        let (controller, card, window) = layout(try message(format: "modal_full"), size: CGSize(width: 402, height: 874))
        defer { window.isHidden = true }
        XCTAssertEqual(card.frame, controller.view.bounds)
        XCTAssertEqual(controller.view.backgroundColor, ResolvedTheme.fallback.background)
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = child as? T
            return (current.map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }
}
