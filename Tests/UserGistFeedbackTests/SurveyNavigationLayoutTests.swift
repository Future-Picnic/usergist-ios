import SwiftUI
import UIKit
import XCTest
@testable import UserGistFeedback

/// Approved survey navigation (2026-11-15): Back leading + Close trailing
/// when Back is usable, otherwise Close leading with an empty trailing slot.
/// Portrait retains the full-width footer. Landscape groups Close then Back
/// and the compact primary action into the same header row.
@MainActor
final class SurveyNavigationLayoutTests: XCTestCase {
    func testLandscapeGroupsCloseAndBackWithoutReservingFooterHeight() {
        let question = SurveyNavigationLayout(canGoBack: true, isComplete: false, needsNext: true, landscape: true)
        XCTAssertEqual(question.leading, .closeAndBack)
        XCTAssertEqual(question.trailing, .next)
        XCTAssertEqual(question.footer, .none)
        let first = SurveyNavigationLayout(canGoBack: false, isComplete: false, needsNext: false, landscape: true)
        XCTAssertEqual(first.leading, .close)
        XCTAssertEqual(first.trailing, .empty)
        let end = SurveyNavigationLayout(canGoBack: true, isComplete: true, needsNext: false, landscape: true)
        XCTAssertEqual(end.leading, .close)
        XCTAssertEqual(end.trailing, .endAction)
        XCTAssertEqual(end.footer, .none)
    }
    func testWithoutBackCloseIsLeadingAndTrailingIsEmpty() {
        let layout = SurveyNavigationLayout(canGoBack: false, isComplete: false, needsNext: true)
        XCTAssertEqual(layout.leading, .close)
        XCTAssertEqual(layout.trailing, .empty)
        XCTAssertEqual(layout.footer, .next)
    }

    func testWithBackBackIsLeadingAndCloseIsTrailing() {
        let layout = SurveyNavigationLayout(canGoBack: true, isComplete: false, needsNext: true)
        XCTAssertEqual(layout.leading, .back)
        XCTAssertEqual(layout.trailing, .close)
        XCTAssertEqual(layout.footer, .next, "Back never shares the footer")
    }

    func testAutoAdvanceQuestionWithBackHasNoFooter() {
        let layout = SurveyNavigationLayout(canGoBack: true, isComplete: false, needsNext: false)
        XCTAssertEqual(layout.leading, .back)
        XCTAssertEqual(layout.trailing, .close)
        XCTAssertEqual(layout.footer, .none)
    }

    func testEndScreenHasCloseLeadingAndFullWidthEndAction() {
        let layout = SurveyNavigationLayout(canGoBack: true, isComplete: true, needsNext: false)
        XCTAssertEqual(layout.leading, .close)
        XCTAssertEqual(layout.trailing, .empty)
        XCTAssertEqual(layout.footer, .endAction)
    }

    func testBackAppearsOnlyAfterHistoryAndRespectsBackNavigationFlag() throws {
        for backNavigation in [true, false] {
            let model = try makeModel(backNavigation: backNavigation)
            XCTAssertFalse(model.canGoBack, "First question has no Back")
            model.select(.string("work"), autoAdvance: true)
            XCTAssertEqual(model.currentQuestionId, "details")
            XCTAssertEqual(model.canGoBack, backNavigation)
            let layout = SurveyNavigationLayout(canGoBack: model.canGoBack, isComplete: false, needsNext: true)
            XCTAssertEqual(layout.leading, backNavigation ? .back : .close)
            if backNavigation {
                model.goBack()
                XCTAssertEqual(model.currentQuestionId, "role", "Back history preserved")
                XCTAssertFalse(model.canGoBack)
            }
        }
    }

    func testRequiredValidationStillBlocksAdvance() throws {
        let model = try makeModel(backNavigation: true)
        model.advance()
        XCTAssertEqual(model.currentQuestionId, "role")
        XCTAssertNotNil(model.errorMessage)
    }

    /// Short landscape viewport (keyboard up; the hostless window adds 62/34pt
    /// insets, leaving an 80pt scroll between header and footer — tighter than
    /// a real landscape keyboard case): focusing the answer scrolls it
    /// so its first line is visible below the action header. The title may
    /// scroll away; no footer consumes the remaining keyboard-safe space.
    func testShortLandscapeFocusRevealsFirstAnswerLineBelowHeader() throws {
        let model = try makeModel(backNavigation: true)
        model.select(.string("work"), autoAdvance: true)
        let view = NativeSurveyView(viewModel: model, endScreen: nil, theme: .fallback,
                                    onClose: {}, onAbandon: { _ in })
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let editor = try XCTUnwrap(descendants(of: host.view, type: UITextView.self).first)
        XCTAssertTrue(editor.becomeFirstResponder())
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let scroll = try XCTUnwrap(descendants(of: host.view, type: UIScrollView.self)
            .first { editor.isDescendant(of: $0) })
        let visible = scroll.convert(scroll.bounds, to: host.view)
        let font = editor.font ?? .systemFont(ofSize: 16)
        let firstLineTop = editor.convert(CGPoint(x: 0, y: editor.textContainerInset.top), to: host.view).y
        XCTAssertGreaterThanOrEqual(firstLineTop, visible.minY - 0.5, "First answer line not under the header")
        XCTAssertLessThanOrEqual(firstLineTop + font.lineHeight, visible.maxY + 0.5,
                                 "First answer line not under the footer (offset \(scroll.contentOffset.y), "
                                 + "visible \(visible), editor \(editor.convert(editor.bounds, to: host.view)), "
                                 + "insets \(host.view.safeAreaInsets), first responder \(editor.isFirstResponder))")
        // Landscape gives the scroll the space formerly reserved for a footer.
        let safeBottom = host.view.bounds.maxY - host.view.safeAreaInsets.bottom
        XCTAssertLessThanOrEqual(safeBottom - visible.maxY, 8,
                                 "Landscape does not reserve a second action row")
    }

    private func descendants<T: UIView>(of root: UIView, type: T.Type) -> [T] {
        root.subviews.flatMap { child -> [T] in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, type: type)
        }
    }

    private func makeModel(backNavigation: Bool) throws -> NativeSurveyViewModel {
        let json = """
        {"startQuestionId":"role","progressStyle":"bar","backNavigation":\(backNavigation),"branches":[],
         "questions":[
          {"id":"role","type":"single_choice","title":"Role","required":true,
           "options":[{"id":"work","label":"Work"}]},
          {"id":"details","type":"long_text","title":"Details"}
         ]}
        """
        let flow = try JSONDecoder().decode(SurveyFlow.self, from: Data(json.utf8))
        let storage = try Storage(writeKeyHash: "nav-" + UUID().uuidString)
        let store = SurveyStore(storage: storage, logger: UserGistLogger(debug: false),
                                queue: DispatchQueue(label: "nav-survey"))
        return NativeSurveyViewModel(flow: flow, surveyId: "s", attemptId: "a", store: store, resume: nil,
                                     onProgress: { _, _, _ in }, onComplete: { _, _, done in done(true) })
    }
}
