import XCTest
import UIKit
@testable import UserGistFeedback

@MainActor
final class PromptViewParityTests: XCTestCase {
    func test_allQuestionFamiliesFollowReferenceFlow() {
        let prompt = ClientPrompt(
            id: "prompt",
            questions: [
                .rating(.init(
                    id: "rating",
                    title: "Rate it",
                    subtitle: nil,
                    imageUrl: nil,
                    scale: 5,
                    display: .stars,
                    lowLabel: nil,
                    highLabel: nil
                )),
                .nps(.init(
                    id: "nps",
                    title: "Recommend it?",
                    subtitle: nil,
                    imageUrl: nil,
                    followUp: nil,
                    lowLabel: nil,
                    highLabel: nil
                )),
                .multipleChoice(.init(
                    id: "single",
                    title: "Pick one",
                    subtitle: nil,
                    imageUrl: nil,
                    options: [
                        .init(id: "single-a", label: "Single A"),
                        .init(id: "single-b", label: "Single B")
                    ],
                    multiSelect: false
                )),
                .multipleChoice(.init(
                    id: "multi",
                    title: "Pick several",
                    subtitle: nil,
                    imageUrl: nil,
                    options: [
                        .init(id: "multi-a", label: "Multi A"),
                        .init(id: "multi-b", label: "Multi B")
                    ],
                    multiSelect: true
                )),
                .shortText(.init(
                    id: "text",
                    title: "Tell us more",
                    subtitle: nil,
                    imageUrl: nil,
                    placeholder: "Type here",
                    maxLength: 140
                ))
            ],
            theme: nil
        )

        XCTAssertTrue(PromptFlow.shouldAutoAdvance(prompt.questions[0]))
        XCTAssertTrue(PromptFlow.shouldAutoAdvance(prompt.questions[1]))
        XCTAssertTrue(PromptFlow.shouldAutoAdvance(prompt.questions[2]))
        XCTAssertFalse(PromptFlow.shouldAutoAdvance(prompt.questions[3]))
        XCTAssertFalse(PromptFlow.shouldAutoAdvance(prompt.questions[4]))
        XCTAssertTrue(PromptFlow.needsExplicitNext(prompt.questions[3]))
        XCTAssertTrue(PromptFlow.needsExplicitNext(prompt.questions[4]))

        let npsWithFollowUp = Question.nps(.init(
            id: "nps-follow-up",
            title: "Recommend it?",
            subtitle: nil,
            imageUrl: nil,
            followUp: "What led to your score?",
            lowLabel: nil,
            highLabel: nil
        ))
        XCTAssertFalse(PromptFlow.shouldAutoAdvance(npsWithFollowUp))
        XCTAssertTrue(PromptFlow.needsExplicitNext(npsWithFollowUp))

        let ordered = PromptFlow.orderedAnswers(
            prompt: prompt,
            answers: [
                "single": .choices(["single-a"]),
                "nps": .number(7),
                "rating": .number(4)
            ]
        )
        XCTAssertEqual(ordered.map(\.questionId), ["rating", "nps", "single"])

        let ratingView = makeView(question: prompt.questions[0])
        XCTAssertEqual(buttons(in: ratingView).filter { $0.title(for: .normal) == "★" }.count, 5)
        XCTAssertTrue(labels(in: ratingView).contains { $0.text == "Rate it" && $0.textAlignment == .center })
        XCTAssertFalse(hasVisibleNext(in: ratingView))

        let npsView = makeView(question: prompt.questions[1])
        XCTAssertEqual(buttons(in: npsView).filter { $0.accessibilityLabel?.hasPrefix("Score ") == true }.count, 11)
        XCTAssertTrue(labels(in: npsView).contains { $0.text == "Recommend it?" && $0.textAlignment == .center })
        XCTAssertFalse(hasVisibleNext(in: npsView))

        let npsFollowUpView = makeView(question: npsWithFollowUp)
        let npsNext = buttons(in: npsFollowUpView).first { $0.title(for: .normal) == "Next" }
        XCTAssertEqual(npsNext?.isHidden, false)
        XCTAssertEqual(npsNext?.isEnabled, false)

        let singleView = makeView(question: prompt.questions[2])
        XCTAssertTrue(buttons(in: singleView).contains { $0.title(for: .normal) == "Single A" })
        XCTAssertFalse(hasVisibleNext(in: singleView))

        let multiView = makeView(question: prompt.questions[3])
        XCTAssertTrue(hasVisibleNext(in: multiView))

        let textView = makeView(question: prompt.questions[4])
        XCTAssertEqual(descendants(of: textView, type: UITextView.self).count, 1)
        let textNext = buttons(in: textView).first { $0.title(for: .normal) == "Next" }
        XCTAssertEqual(textNext?.isHidden, false)
        XCTAssertEqual(textNext?.isEnabled, false)
    }

    private func makeView(question: Question) -> PromptView {
        let view = PromptView(
            prompt: ClientPrompt(id: "prompt", questions: [question], theme: nil),
            theme: .fallback,
            onFinish: { _ in }
        )
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        view.layoutIfNeeded()
        return view
    }

    private func hasVisibleNext(in root: UIView) -> Bool {
        buttons(in: root).contains { $0.title(for: .normal) == "Next" && !$0.isHidden }
    }

    private func buttons(in root: UIView) -> [UIButton] {
        descendants(of: root, type: UIButton.self)
    }

    private func labels(in root: UIView) -> [UILabel] {
        descendants(of: root, type: UILabel.self)
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = child as? T
            return (current.map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }
}
