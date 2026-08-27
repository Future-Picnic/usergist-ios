import SwiftUI
import XCTest
@testable import UserGistFeedback

@MainActor
final class SurveyRatingInputParityTests: XCTestCase {
    func test_surveyRatingRendersSharedStarsAndRestoresSelection() {
        let question = SurveyQuestion(
            id: "survey-rating",
            type: .rating,
            title: "How reliable did it feel?",
            subtitle: nil,
            required: true,
            imageUrl: nil,
            options: nil,
            allowOther: nil,
            minSelections: nil,
            maxSelections: nil,
            scale: 5,
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
        let host = UIHostingController(
            rootView: SurveyRatingInput(
                question: question,
                selected: 4,
                theme: .fallback,
                onSelect: { _ in },
                onAutoAdvance: {}
            )
            .frame(height: SurveyRatingInput.preferredHeight(for: question))
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 342, height: 120))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let starButtons = descendants(of: host.view, type: UIButton.self)
            .filter { $0.title(for: .normal) == "★" }
        guard starButtons.count == 5 else {
            return XCTFail("Expected five shared star buttons, found \(starButtons.count)")
        }
        XCTAssertTrue(starButtons.allSatisfy { $0.accessibilityLabel?.hasPrefix("Rate ") == true })
        XCTAssertTrue(starButtons.allSatisfy { $0.bounds.height == 36 })
        XCTAssertTrue(starButtons.prefix(4).allSatisfy {
            $0.titleColor(for: .normal) == ResolvedTheme.fallback.primary
        })
        XCTAssertEqual(starButtons.last?.titleColor(for: .normal), ResolvedTheme.fallback.border)
    }

    func test_selectionIsRecordedBeforeDelayedAutoAdvance() {
        let advanced = expectation(description: "auto advance")
        var events: [String] = []
        let coordinator = SurveyRatingInput.Coordinator(
            onSelect: { events.append("selected:\($0)") },
            onAutoAdvance: {
                events.append("advanced")
                advanced.fulfill()
            }
        )

        coordinator.didSelect(5)

        XCTAssertEqual(events, ["selected:5"])
        wait(for: [advanced], timeout: 1)
        XCTAssertEqual(events, ["selected:5", "advanced"])
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = child as? T
            return (current.map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }
}
