import XCTest
import UIKit
@testable import UserGistFeedback

@MainActor
final class RatingQuestionViewTests: XCTestCase {
    func testBothEndpointLabels() {
        verifyRating(lowLabel: "Poor", highLabel: "Excellent")
    }

    func testLowEndpointLabelOnly() {
        verifyRating(lowLabel: "Poor", highLabel: nil)
    }

    func testHighEndpointLabelOnly() {
        verifyRating(lowLabel: nil, highLabel: "Excellent")
    }

    func testNoEndpointLabels() {
        verifyRating(lowLabel: nil, highLabel: nil)
    }

    private func verifyRating(lowLabel: String?, highLabel: String?) {
        for display: Question.Rating.Display in [.stars, .emoji, .numeric] {
            let view = RatingQuestionView(
                question: .init(
                    id: "rating", title: "Rate it", subtitle: nil, imageUrl: nil,
                    scale: 5, display: display, lowLabel: lowLabel, highLabel: highLabel
                ),
                theme: .fallback,
                initialValue: 4
            )
            // Exercise portrait and landscape bounds, including resizing the same view.
            for size in [CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)] {
                view.frame = CGRect(origin: .zero, size: size)
                view.setNeedsLayout()
                view.layoutIfNeeded()

                let endpointLabels = descendants(of: view, type: UILabel.self)
                    .filter { $0.superview is UIStackView }
                XCTAssertEqual(endpointLabels.compactMap(\.text), [lowLabel, highLabel].compactMap { $0 })
                if let labelRow = endpointLabels.first?.superview {
                    XCTAssertEqual(labelRow.bounds.width, size.width, accuracy: 0.5)
                }
            }

            XCTAssertEqual(view.currentAnswer, .number(4))
            let buttons = descendants(of: view, type: UIButton.self)
            XCTAssertEqual(buttons.count, 5)
            var answer: PromptAnswerValue?
            view.onValueChange = { answer = $0 }
            guard let button = buttons.first(where: { $0.tag == 2 }),
                  let action = button.actions(forTarget: view, forControlEvent: .touchUpInside)?.first else {
                XCTFail("Expected a registered rating selection action")
                continue
            }
            // Package tests have no UIApplication to dispatch UIControl actions.
            view.perform(NSSelectorFromString(action), with: button)
            XCTAssertEqual(answer, .number(2))
            XCTAssertEqual(view.currentAnswer, .number(2))
        }
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? []
        } + root.subviews.flatMap { descendants(of: $0, type: type) }
    }
}
