import SwiftUI
import XCTest
@testable import UserGistFeedback

@MainActor
final class QuestionInputSafetyTests: XCTestCase {
    func testMalformedRatingScalesCannotAllocateUnboundedButtons() {
        for scale in [Int.min, -1, 0, 1, 5, 7, 10, 11, Int.max] {
            for display: Question.Rating.Display in [.stars, .numeric, .emoji] {
                let view = RatingQuestionView(question: .init(id: "r", title: "Rate",
                    subtitle: nil, imageUrl: nil, scale: scale, display: display,
                    lowLabel: nil, highLabel: nil), theme: .fallback, initialValue: Int.max)
                let buttons = descendants(of: view, type: UIButton.self)
                let expected = scale == 10 ? 10 : 5
                XCTAssertEqual(buttons.count, expected)
                XCTAssertEqual(view.currentAnswer, .none)
                view.setSelectedValue(expected)
                XCTAssertEqual(view.currentAnswer, .number(Double(expected)))
                view.setSelectedValue(expected + 1)
                XCTAssertEqual(view.currentAnswer, .none)
            }
        }
    }

    func testSurveyRatingHeightMatchesItsBoundedControl() throws {
        for scale in [Int.min, -1, 0, 5, 10, Int.max] {
            let json = """
            {"id":"r","type":"rating","title":"Rate","scale":\(scale)}
            """
            let question = try JSONDecoder().decode(SurveyQuestion.self, from: Data(json.utf8))
            XCTAssertEqual(SurveyRatingInput.promptQuestion(for: question).scale, scale == 10 ? 10 : 5)
            XCTAssertEqual(SurveyRatingInput.preferredHeight(for: question), scale == 10 ? 80 : 36)
        }
    }

    func testInvalidTextLimitsDoNotTrapAndUnicodeIsNotSplit() {
        let text = "🎹👨‍👩‍👧‍👦e\u{301}שלום"
        for limit: Int? in [nil, Int.min, -1, 0, Int.max] {
            XCTAssertEqual(SurveyTextInput.limitedText(text, maxLength: limit), text)
            let input = SurveyTextInput(initial: text, accessibilityLabel: "Text", placeholder: "",
                longForm: true, maxLength: limit, theme: .fallback) { _ in }
            XCTAssertEqual(input.maxLength, limit.flatMap { $0 > 0 ? $0 : nil })
        }
        XCTAssertEqual(SurveyTextInput.limitedText(text, maxLength: 2), "🎹👨‍👩‍👧‍👦")
        XCTAssertEqual(SurveyTextInput.limitedText(text, maxLength: 3), "🎹👨‍👩‍👧‍👦e\u{301}")
        XCTAssertEqual(SurveyTextInput.limitedText("", maxLength: 1), "")
    }

    func testRankingDeduplicatesPayloadAndStaleSavedAnswers() {
        let items = [SurveyChoice(id: "a", label: "First A"),
                     SurveyChoice(id: "b", label: "B"),
                     SurveyChoice(id: "a", label: "Duplicate A"),
                     SurveyChoice(id: "", label: "Missing ID"),
                     SurveyChoice(id: "c", label: "C")]
        let restored = SurveyRankingInput.restoredItems(items,
            savedOrder: ["b", "b", "missing", "a", ""])
        XCTAssertEqual(restored.map(\.id), ["b", "a", "c"])
        XCTAssertEqual(restored.map(\.label), ["B", "First A", "C"])
        XCTAssertEqual(SurveyRankingInput.restoredItems(items, savedOrder: []).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(SurveyRankingInput.restoredItems([], savedOrder: ["a"]), [])
    }

    func testRankingPreservesAValidSavedOrder() {
        let items = [SurveyChoice(id: "a", label: "A"), SurveyChoice(id: "b", label: "B")]
        XCTAssertEqual(SurveyRankingInput.restoredItems(items, savedOrder: ["b", "a"]), items.reversed())
    }

    func testDatePickerAcceptsReversedInvalidAndOutOfDefaultRangeBounds() {
        let cases: [(String?, String?)] = [
            (nil, nil), ("invalid", "invalid"), ("2026-12-31", "2026-01-01"),
            ("2026-01-01", "2026-01-01"), ("2200-01-01", nil), (nil, "1800-01-01")
        ]
        for (minimum, maximum) in cases {
            let input = SurveyDateInput(initial: "invalid", minimum: minimum, maximum: maximum,
                theme: .fallback) { _ in }
            XCTAssertLessThanOrEqual(input.minimum, input.maximum)
            // Evaluating body constructs the closed range that previously trapped.
            _ = input.body
        }
        let forward = SurveyDateInput(initial: "", minimum: "2026-01-01", maximum: "2026-12-31",
            theme: .fallback) { _ in }
        let reversed = SurveyDateInput(initial: "", minimum: "2026-12-31", maximum: "2026-01-01",
            theme: .fallback) { _ in }
        XCTAssertEqual(forward.minimum, reversed.minimum)
        XCTAssertEqual(forward.maximum, reversed.maximum)
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            (child as? T).map { [$0] } ?? []
        } + root.subviews.flatMap { descendants(of: $0, type: type) }
    }
}
