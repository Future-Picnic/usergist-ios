import XCTest
@testable import UserGistFeedback

final class LocalInstructionDedupeTests: XCTestCase {
    func testMatchingInstructionIsConsumedOnceAfterRestart() {
        var persisted: [String]?
        func makeDedupe() -> LocalInstructionDedupe {
            LocalInstructionDedupe(
                read: { persisted },
                write: { persisted = $0 },
                remove: { persisted = nil }
            )
        }
        let key = "inapp.show:message-1:event:event-1"

        let first = makeDedupe()
        first.remember(key)
        let restored = makeDedupe()
        restored.hydrate()

        XCTAssertTrue(restored.consume(key))
        XCTAssertFalse(restored.consume(key))
        let afterConsume = makeDedupe()
        afterConsume.hydrate()
        XCTAssertFalse(afterConsume.contains(key))
    }

    func testOnlyLatestTwoHundredInstructionsAreRetained() {
        var persisted: [String]?
        let dedupe = LocalInstructionDedupe(
            read: { persisted },
            write: { persisted = $0 },
            remove: { persisted = nil }
        )

        for index in 0..<205 {
            dedupe.remember("inapp.show:message:event:\(index)")
        }

        XCTAssertEqual(dedupe.count, 200)
        XCTAssertFalse(dedupe.contains("inapp.show:message:event:0"))
        XCTAssertTrue(dedupe.contains("inapp.show:message:event:204"))
    }
}
