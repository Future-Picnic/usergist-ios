import SwiftUI
import XCTest
@testable import UserGistFeedback

@MainActor
final class SurveyTextInputParityTests: XCTestCase {
    func test_surveyLongTextUsesThemeBackgroundAndReactNativeSizing() {
        let theme = ResolvedTheme(
            primary: UIColor(red: 0, green: 0.64, blue: 0.49, alpha: 1),
            background: UIColor(red: 0.91, green: 1, blue: 0.97, alpha: 1),
            text: UIColor(red: 0.09, green: 0.07, blue: 0.18, alpha: 1),
            subtext: UIColor(red: 0.46, green: 0.44, blue: 0.54, alpha: 1),
            border: UIColor(red: 0.88, green: 0.86, blue: 0.93, alpha: 1),
            radius: 16,
            font: UIFont.systemFont(ofSize: 15),
            titleFont: UIFont.boldSystemFont(ofSize: 18),
            boldFont: UIFont.boldSystemFont(ofSize: 15)
        )
        let host = UIHostingController(
            rootView: SurveyTextInput(
                initial: "",
                accessibilityLabel: "What should improve?",
                placeholder: "Tell us more",
                longForm: true,
                maxLength: 1000,
                theme: theme
            ) { _ in }
            .background(Color(theme.background))
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 342, height: 180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let textViews = descendants(of: host.view, type: UITextView.self)
        XCTAssertEqual(textViews.count, 1)
        XCTAssertEqual(textViews.first?.backgroundColor, UIColor.clear)
        XCTAssertEqual(textViews.first?.textColor, theme.text)
        XCTAssertEqual(textViews.first?.tintColor, theme.primary)
        XCTAssertEqual(textViews.first?.accessibilityLabel, "What should improve?")
        XCTAssertGreaterThanOrEqual(textViews.first?.frame.height ?? 0, 100)
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = child as? T
            return (current.map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }
}
