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

    func testLandscapeSheetSpansTheFullWidthAboveTheKeyboard() {
        let frame = PromptSheetLayout.frame(
            containerBounds: CGRect(x: 0, y: 0, width: 874, height: 402),
            safeTop: 0,
            requestedHeight: 320,
            keyboardOverlap: 210
        )

        XCTAssertEqual(frame.width, 874, "The sheet background is never a narrow card")
        XCTAssertEqual(frame.maxY, 192)
        XCTAssertEqual(frame.minY, 16)
    }

    func testShortContentKeepsAMinimumSheetHeight() {
        let frame = PromptSheetLayout.frame(
            containerBounds: CGRect(x: 0, y: 0, width: 402, height: 874),
            safeTop: 62,
            requestedHeight: 90,
            keyboardOverlap: 0
        )

        XCTAssertEqual(frame.height, PromptSheetLayout.minimumHeight)
    }
}
