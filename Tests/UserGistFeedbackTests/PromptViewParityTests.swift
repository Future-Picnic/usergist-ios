import XCTest
import UIKit
@testable import UserGistFeedback

@MainActor
final class PromptViewParityTests: XCTestCase {
    func testLandscapeResizeKeepsFocusedAnswerAboveNext() throws {
        let view = makeView(question: .shortText(.init(
            id: "text", title: "Tell us more", subtitle: nil, imageUrl: nil,
            placeholder: "Type here", maxLength: 140
        )))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.addSubview(view)
        view.frame = controller.view.bounds
        view.layoutIfNeeded()
        let editor = try XCTUnwrap(descendants(of: view, type: UITextView.self).first)
        XCTAssertTrue(editor.becomeFirstResponder())
        editor.text = "An answer with the keyboard open"
        view.frame.size.height = 170
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let scroll = try XCTUnwrap(descendants(of: view, type: UIScrollView.self).first)
        let selection = try XCTUnwrap(editor.selectedTextRange)
        let caret = editor.convert(editor.caretRect(for: selection.end), to: view)
        let visible = scroll.convert(scroll.bounds, to: view)
        XCTAssertGreaterThanOrEqual(caret.minY, visible.minY)
        XCTAssertLessThanOrEqual(caret.maxY, visible.maxY)
        // Landscape with the keyboard up (170pt sheet): Submit is the one
        // full-width footer action below the scrolling answer, still inside
        // the sheet (which rides above the keyboard), never in the header.
        let submit = try XCTUnwrap(buttons(in: view).first { $0.title(for: .normal) == "Submit" })
        let submitFrame = submit.convert(submit.bounds, to: view)
        XCTAssertFalse(submit.isHidden)
        XCTAssertEqual((submit as? SurfacePrimaryButton)?.compact, false, "Landscape uses the full-size footer action")
        XCTAssertGreaterThanOrEqual(submitFrame.minY, visible.maxY - 0.5, "Footer sits below the scroll")
        XCTAssertLessThanOrEqual(submitFrame.maxY, view.bounds.maxY, "Footer stays inside the keyboard-safe sheet")
        let column = min(view.bounds.width - 24, SurfaceMetrics.contentMaxWidth)
        XCTAssertEqual(submitFrame.width, column - 24, accuracy: 1, "Full width of the readable column")
        XCTAssertEqual(submitFrame.midX, view.bounds.midX, accuracy: 1, "Centred in landscape")
        let close = try XCTUnwrap(buttons(in: view).first { $0.accessibilityLabel == "Close" })
        let closeFrame = close.convert(close.bounds, to: view)
        XCTAssertLessThan(closeFrame.midX, view.bounds.midX, "Feedback has no Back: Close stays leading")
        XCTAssertLessThanOrEqual(closeFrame.maxY, visible.minY)
        XCTAssertFalse(buttons(in: view).contains { $0.accessibilityLabel == "Back" })
    }

    func testPortraitKeepsMainActionInFooterBelowTheAnswer() throws {
        let view = makeView(question: .shortText(.init(
            id: "text", title: "Tell us more", subtitle: nil, imageUrl: nil,
            placeholder: "Type here", maxLength: 140
        )))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.addSubview(view)
        view.frame = CGRect(x: 0, y: 400, width: 402, height: 474)
        view.layoutIfNeeded()
        let scroll = try XCTUnwrap(descendants(of: view, type: UIScrollView.self).first)
        let submit = try XCTUnwrap(buttons(in: view).first { $0.title(for: .normal) == "Submit" })
        let visible = scroll.convert(scroll.bounds, to: view)
        XCTAssertGreaterThanOrEqual(submit.convert(submit.bounds, to: view).minY, visible.maxY)
        XCTAssertGreaterThanOrEqual(submit.bounds.height, SurfaceMetrics.primaryMinHeight)
        XCTAssertEqual(submit.bounds.width, view.bounds.width - 48, accuracy: 1, "Full-width footer action")
        XCTAssertFalse(submit.isEnabled, "Empty text keeps Submit disabled")
        XCTAssertEqual(submit.backgroundColor, ResolvedTheme.fallback.fill, "Disabled uses a neutral fill")
    }

    func testWideNpsCentresEveryNumeralIncludingTen() throws {
        let view = makeView(question: .nps(.init(
            id: "nps", title: "Recommend it?", subtitle: nil, imageUrl: nil,
            followUp: nil, lowLabel: nil, highLabel: nil
        )))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.addSubview(view)
        view.frame = controller.view.bounds
        view.layoutIfNeeded()
        let cells = buttons(in: view).filter { $0.accessibilityLabel?.hasPrefix("Score ") == true }
        XCTAssertEqual(cells.count, 11)
        let rows = Set(cells.map { Int($0.convert($0.bounds, to: view).midY.rounded()) })
        XCTAssertEqual(rows.count, 1, "Wide NPS is a single 0–10 row")
        for cell in cells {
            let numeral = try XCTUnwrap(descendants(of: cell, type: UILabel.self)
                .first { $0.text.map { Int($0) != nil } == true })
            XCTAssertEqual(numeral.frame.midX, cell.bounds.midX, accuracy: 0.5, cell.accessibilityLabel ?? "")
            XCTAssertEqual(numeral.frame.midY, cell.bounds.midY, accuracy: 0.5, cell.accessibilityLabel ?? "")
        }
        XCTAssertTrue(labels(in: view).contains { $0.text == "Recommend it?" && $0.textAlignment == .center })
    }

    func testAnsweringFirstQuestionShowsSecondAndDismissalKeepsFirstAnswer() async throws {
        let prompt = ClientPrompt(id: "prompt", questions: [
            .rating(.init(
                id: "rating", title: "Rate it", subtitle: nil, imageUrl: nil,
                scale: 5, display: .stars, lowLabel: nil, highLabel: nil
            )),
            .shortText(.init(
                id: "text", title: "Tell us more", subtitle: nil, imageUrl: nil,
                placeholder: "Type here", maxLength: 140
            ))
        ], theme: nil)
        var result: PromptView.Outcome?
        let view = PromptView(prompt: prompt, theme: .fallback, onFinish: { result = $0 })
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        view.layoutIfNeeded()
        let rating = try XCTUnwrap(descendants(of: view, type: RatingQuestionView.self).first)
        let button = try XCTUnwrap(buttons(in: rating).first { $0.tag == 5 })
        let action = try XCTUnwrap(button.actions(forTarget: rating, forControlEvent: .touchUpInside)?.first)
        rating.perform(NSSelectorFromString(action), with: button)
        // Allow the actual auto-advance timer and transition to run.
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(labels(in: view).contains { $0.text == "Tell us more" })
        XCTAssertNil(result)
        view.dismiss()
        guard case .dismissed(let answers) = result else {
            return XCTFail("Expected a partial dismissal")
        }
        XCTAssertEqual(answers, [.init(questionId: "rating", value: .number(5))])
    }

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

        // Narrow portrait NPS: vertical list (10 first), left-aligned title as in RN.
        let npsView = makeView(question: prompt.questions[1])
        let scores = buttons(in: npsView).filter { $0.accessibilityLabel?.hasPrefix("Score ") == true }
        XCTAssertEqual(scores.count, 11)
        XCTAssertEqual(scores.first?.accessibilityLabel, "Score 10, Extremely likely")
        XCTAssertTrue(labels(in: npsView).contains { $0.text == "Recommend it?" && $0.textAlignment == .natural })
        XCTAssertFalse(hasVisibleNext(in: npsView))

        // A single-question prompt's main action reads "Submit".
        let npsFollowUpView = makeView(question: npsWithFollowUp)
        let npsNext = buttons(in: npsFollowUpView).first { $0.title(for: .normal) == "Submit" }
        XCTAssertEqual(npsNext?.isHidden, false)
        XCTAssertEqual(npsNext?.isEnabled, false)

        let singleView = makeView(question: prompt.questions[2])
        let rows = descendants(of: singleView, type: SurfaceChoiceRow.self)
        XCTAssertEqual(rows.map(\.accessibilityLabel), ["Single A", "Single B"])
        XCTAssertFalse(hasVisibleNext(in: singleView))

        let multiView = makeView(question: prompt.questions[3])
        XCTAssertTrue(hasVisibleNext(in: multiView))
        XCTAssertTrue(labels(in: multiView).contains { $0.text == "Choose all that apply" })

        let textView = makeView(question: prompt.questions[4])
        XCTAssertEqual(descendants(of: textView, type: UITextView.self).count, 1)
        let textNext = buttons(in: textView).first { $0.title(for: .normal) == "Submit" }
        XCTAssertEqual(textNext?.isHidden, false)
        XCTAssertEqual(textNext?.isEnabled, false)
    }

    func testNpsLayoutFollowsItsOwnContentWidthNotTheWindow() {
        let question = Question.Nps(id: "n", title: "Recommend?", subtitle: nil, imageUrl: nil,
                                    followUp: nil, lowLabel: nil, highLabel: nil)
        func distinctRows(width: CGFloat) -> Int {
            let view = NpsQuestionView(question: question, theme: .fallback)
            view.frame = CGRect(x: 0, y: 0, width: width, height: 900)
            view.layoutIfNeeded()
            view.layoutIfNeeded()
            let cells = descendants(of: view, type: UIButton.self)
            return Set(cells.map { Int($0.convert($0.bounds, to: view).midY.rounded()) }).count
        }
        XCTAssertEqual(distinctRows(width: 536), 1, "The 560pt landscape column (536 content) is wide")
        XCTAssertEqual(distinctRows(width: 523), 11, "Below 524 the readable vertical list is kept")
        XCTAssertEqual(PromptView.contentWidth(forSheetWidth: 874), 536)
        XCTAssertEqual(PromptView.contentWidth(forSheetWidth: 402), 354)

        // A narrow sheet inside a wide window keeps the list.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let sheet = PromptView(prompt: ClientPrompt(id: "p", questions: [.nps(question)], theme: nil),
                               theme: .fallback, onFinish: { _ in })
        controller.view.addSubview(sheet)
        sheet.frame = CGRect(x: 0, y: 0, width: 420, height: 402)
        sheet.layoutIfNeeded()
        sheet.layoutIfNeeded()
        let nps = descendants(of: sheet, type: NpsQuestionView.self).first
        XCTAssertEqual(nps?.wide, false)
        XCTAssertTrue(labels(in: sheet).contains { $0.text == "Recommend?" && $0.textAlignment == .natural })
    }

    func testMultiStepPromptShowsStepAndNextUntilTheLastQuestion() {
        let choice = Question.multipleChoice(.init(
            id: "multi", title: "Pick several", subtitle: nil, imageUrl: nil,
            options: [.init(id: "a", label: "A")], multiSelect: true
        ))
        let text = Question.shortText(.init(
            id: "text", title: "Tell us more", subtitle: nil, imageUrl: nil, placeholder: nil, maxLength: nil
        ))
        let view = PromptView(prompt: ClientPrompt(id: "p", questions: [choice, text], theme: nil),
                              theme: .fallback, onFinish: { _ in })
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        view.layoutIfNeeded()
        XCTAssertTrue(labels(in: view).contains { $0.text == "1 of 2" })
        XCTAssertTrue(hasVisibleNext(in: view))
    }

    func testCloseIsOneLeadingControlWithA44PointTarget() throws {
        let view = makeView(question: .shortText(.init(
            id: "text", title: "Tell us more", subtitle: nil, imageUrl: nil, placeholder: nil, maxLength: nil
        )))
        let closes = buttons(in: view).filter { $0.accessibilityLabel == "Close" }
        XCTAssertEqual(closes.count, 1)
        let close = try XCTUnwrap(closes.first)
        XCTAssertEqual(close.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertLessThan(close.convert(close.bounds, to: view).midX, view.bounds.midX)
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
        buttons(in: root).contains {
            ["Next", "Submit"].contains($0.title(for: .normal) ?? "") && !$0.isHidden && $0.superview?.isHidden == false
        }
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
