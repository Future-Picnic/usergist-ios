import XCTest
@testable import UserGistFeedback

final class FrequencyCapTests: XCTestCase {
    private var storage: Storage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storage = try Storage(writeKeyHash: "freq-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storage.root)
        try super.tearDownWithError()
    }

    func test_perPromptDaysBlocks() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = FrequencyCapStore(
            storage: storage,
            logger: UserGistLogger(debug: false),
            queue: UserGistQueue.serial("freq-test-a"),
            clock: { now }
        )
        let caps = FrequencyCaps(perPromptDays: 7, perUserDays: nil)

        XCTAssertTrue(store.canShow(promptId: "p1", caps: caps))
        store.recordShown(promptId: "p1")
        XCTAssertFalse(store.canShow(promptId: "p1", caps: caps))

        // Advance 8 days — cap window has rolled over.
        now = now.addingTimeInterval(8 * 86_400)
        XCTAssertTrue(store.canShow(promptId: "p1", caps: caps))
    }

    func test_perUserDaysBlocksAcrossPrompts() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = FrequencyCapStore(
            storage: storage,
            logger: UserGistLogger(debug: false),
            queue: UserGistQueue.serial("freq-test-b"),
            clock: { now }
        )
        let caps = FrequencyCaps(perPromptDays: nil, perUserDays: 1)

        XCTAssertTrue(store.canShow(promptId: "p1", caps: caps))
        store.recordShown(promptId: "p1")
        XCTAssertFalse(store.canShow(promptId: "p2", caps: caps))

        now = now.addingTimeInterval(2 * 86_400)
        XCTAssertTrue(store.canShow(promptId: "p2", caps: caps))
    }

    func test_differentPromptsDontInterfere() {
        let now = Date()
        let store = FrequencyCapStore(
            storage: storage,
            logger: UserGistLogger(debug: false),
            queue: UserGistQueue.serial("freq-test-c"),
            clock: { now }
        )
        let caps = FrequencyCaps(perPromptDays: 7, perUserDays: nil)

        store.recordShown(promptId: "p1")
        XCTAssertTrue(store.canShow(promptId: "p2", caps: caps))
    }

    func test_resetClearsHistory() {
        let now = Date()
        let store = FrequencyCapStore(
            storage: storage,
            logger: UserGistLogger(debug: false),
            queue: UserGistQueue.serial("freq-test-d"),
            clock: { now }
        )
        let caps = FrequencyCaps(perPromptDays: 7, perUserDays: 7)
        store.recordShown(promptId: "p1")
        store.reset()
        XCTAssertTrue(store.canShow(promptId: "p1", caps: caps))
    }
}
