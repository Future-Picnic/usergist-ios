import XCTest
@testable import RitmusFeedback

final class EventQueueTests: XCTestCase {
    private var tmpRoot: URL!
    private var storage: Storage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpRoot = try makeTempStorage()
        storage = try Storage(writeKeyHash: "test-\(UUID().uuidString.prefix(8))", fileManager: .default)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storage.root)
        try super.tearDownWithError()
    }

    func test_appendAndHead() {
        let queue = makeQueue(maxCount: 10)
        queue.enqueue(makeEvent(name: "a"))
        queue.enqueue(makeEvent(name: "b"))
        queue.enqueue(makeEvent(name: "c"))

        XCTAssertEqual(queue.count, 3)
        let batch = queue.head(size: 2)
        XCTAssertEqual(batch.map { $0.name }, ["a", "b"])
    }

    func test_dropFirst() {
        let queue = makeQueue(maxCount: 10)
        for letter in ["a", "b", "c"] {
            queue.enqueue(makeEvent(name: letter))
        }
        queue.drop(2)
        XCTAssertEqual(queue.snapshot().map { $0.name }, ["c"])
    }

    func test_overflowDropsOldest() {
        let queue = makeQueue(maxCount: 3)
        for letter in ["a", "b", "c", "d", "e"] {
            queue.enqueue(makeEvent(name: letter))
        }
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.snapshot().map { $0.name }, ["c", "d", "e"])
    }

    func test_persistenceRoundTrip() {
        let queue = makeQueue(maxCount: 10)
        for name in ["alpha", "beta", "gamma"] {
            queue.enqueue(makeEvent(name: name))
        }
        // Recreate queue against same storage.
        let reloaded = EventQueue(
            storage: storage,
            logger: RitmusLogger(debug: false),
            maxCount: 10,
            maxBytes: 1_000_000
        )
        XCTAssertEqual(reloaded.snapshot().map { $0.name }, ["alpha", "beta", "gamma"])
    }

    func test_clearRemovesFile() {
        let queue = makeQueue(maxCount: 10)
        queue.enqueue(makeEvent(name: "a"))
        queue.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.eventsLog.path))
    }

    // MARK: - Helpers

    private func makeQueue(maxCount: Int) -> EventQueue {
        EventQueue(
            storage: storage,
            logger: RitmusLogger(debug: false),
            maxCount: maxCount,
            maxBytes: 1_000_000
        )
    }

    private func makeEvent(name: String) -> IngestEvent {
        IngestEvent(
            name: name,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            anonymousId: "anon-1",
            externalId: nil,
            properties: nil,
            sessionId: nil,
            sdkVersion: "1.0.0",
            appVersion: "1.2.3",
            platform: "ios"
        )
    }

    private func makeTempStorage() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ritmus-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }
}
