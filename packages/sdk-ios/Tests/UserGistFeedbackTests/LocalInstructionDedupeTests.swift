import XCTest
@testable import UserGistFeedback

final class LocalInstructionDedupeTests: XCTestCase {
    func testServerLowercaseUUIDMatchesPersistedSwiftUppercaseUUID() {
        let swiftKey = "inapp.show:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE:event:FFFFFFFF-1111-2222-3333-444444444444"
        var persisted: [String]? = [swiftKey]
        let dedupe = LocalInstructionDedupe(read: { persisted }, write: { persisted = $0 }, remove: { persisted = nil })
        dedupe.hydrate()
        XCTAssertTrue(dedupe.consume(swiftKey.lowercased()))
        dedupe.remember(swiftKey)
        XCTAssertTrue(dedupe.consume(swiftKey.lowercased()))
        XCTAssertFalse(dedupe.consume(swiftKey))
    }

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
