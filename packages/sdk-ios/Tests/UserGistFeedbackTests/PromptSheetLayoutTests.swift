import XCTest
@testable import UserGistFeedback

final class PromptSheetLayoutTests: XCTestCase {
    func testSheetAnchorsToContainerBottomWithoutKeyboard() {
        let frame = PromptSheetLayout.frame(
            containerBounds: CGRect(x: 0, y: 0, width: 402, height: 874),
            safeTop: 62,
            requestedHeight: 360,
            keyboardOverlap: 0
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 514, width: 402, height: 360))
    }

    func testSheetAnchorsAboveKeyboardAndKeepsRequestedHeight() {
        let frame = PromptSheetLayout.frame(
            containerBounds: CGRect(x: 0, y: 0, width: 402, height: 874),
            safeTop: 62,
            requestedHeight: 360,
            keyboardOverlap: 242
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 272, width: 402, height: 360))
    }

    func testSheetShrinksWhenKeyboardLeavesLessThanRequestedSpace() {
        let frame = PromptSheetLayout.frame(
            containerBounds: CGRect(x: 0, y: 0, width: 320, height: 568),
            safeTop: 20,
            requestedHeight: 500,
            keyboardOverlap: 260
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 36, width: 320, height: 272))
    }
}
