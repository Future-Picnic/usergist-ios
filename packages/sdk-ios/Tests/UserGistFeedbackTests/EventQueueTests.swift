import XCTest
@testable import UserGistFeedback

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
            logger: UserGistLogger(debug: false),
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

    func test_persistedEnvelopeIsVersioned() throws {
        // Confirms that the on-disk format is the versioned JSON envelope
        // mirrored from packages/sdk-react-native/src/internal/queue.ts.
        let queue = makeQueue(maxCount: 10)
        queue.enqueue(makeEvent(name: "alpha"))
        let raw = try Data(contentsOf: storage.eventsLog)
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["version"] as? Int, 2)
        let events = json?["events"] as? [[String: Any]]
        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(events?.first?["name"] as? String, "alpha")
    }

    func test_hydratesLegacyNDJSON() throws {
        // Simulates an install upgrading from a pre-versioning build that
        // wrote bare newline-delimited event JSON. Mirrors the legacy fallback
        // in packages/sdk-react-native/src/internal/queue.ts (the
        // `Array.isArray(stored)` branch).
        let encoder = JSONEncoder.usergist()
        let line1 = try encoder.encode(makeEvent(name: "legacy-a"))
        let line2 = try encoder.encode(makeEvent(name: "legacy-b"))
        var buffer = Data()
        buffer.append(line1)
        buffer.append(0x0A)
        buffer.append(line2)
        buffer.append(0x0A)
        try storage.writeData(buffer, to: storage.eventsLog)

        let queue = makeQueue(maxCount: 10)
        XCTAssertEqual(queue.snapshot().map { $0.name }, ["legacy-a", "legacy-b"])

        // Next mutation should rewrite as the versioned envelope.
        queue.enqueue(makeEvent(name: "fresh"))
        let raw = try Data(contentsOf: storage.eventsLog)
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 2)
    }

    func test_discardsUnknownVersion() throws {
        // A future SDK might bump QUEUE_SCHEMA_VERSION. Earlier installs must
        // discard those snapshots rather than crash on a shape mismatch.
        let payload: [String: Any] = ["version": 999, "events": []]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try storage.writeData(data, to: storage.eventsLog)
        let queue = makeQueue(maxCount: 10)
        XCTAssertEqual(queue.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.eventsLog.path))
    }

    // MARK: - Helpers

    private func makeQueue(maxCount: Int) -> EventQueue {
        EventQueue(
            storage: storage,
            logger: UserGistLogger(debug: false),
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
            .appendingPathComponent("usergist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }
}
