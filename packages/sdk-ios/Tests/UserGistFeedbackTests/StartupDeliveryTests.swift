import XCTest
@testable import UserGistFeedback

final class StartupDeliveryTests: XCTestCase {
    func testFirstAppOpenReadsInstructionsAfterIngestWithoutAnotherForeground() throws {
        let acknowledged = expectation(description: "first-open instruction acknowledged")
        let lock = NSLock()
        var ingested = false
        var firstPoll = true
        StartupURLProtocol.handler = { request, body in
            switch request.url!.path {
            case "/v1/sdk/session": return ("{\"subjectToken\":\"st_startup_test\",\"subjectId\":\"startup-user\",\"expiresAt\":\"2099-01-01T00:00:00.000Z\"}", 0)
            case "/v1/sdk/ingest":
                let events = body["events"] as? [[String: Any]] ?? []
                let ids = (body["delivery"] as? [String: Any])?["eventIds"] as? [String]
                XCTAssertEqual(ids, events.compactMap { $0["eventId"] as? String })
                XCTAssertTrue(events.contains { $0["name"] as? String == "$app_open" })
                lock.lock(); ingested = true; lock.unlock()
                // The initial inbox poll precedes this response. Upload completion
                // must trigger a second poll without an app restart or a timer.
                return ("{\"accepted\":1,\"rejected\":0}", 0.2)
            case "/v1/sdk/instructions":
                lock.lock()
                let initial = firstPoll
                firstPoll = false
                let ready = ingested
                lock.unlock()
                if initial { return ("{\"instructions\":[]}", 0.35) }
                return (ready ? "{\"instructions\":[{\"id\":1,\"type\":\"test.noop\",\"payload\":{}}]}" : "{\"instructions\":[]}", 0)
            case "/v1/sdk/instructions/ack":
                acknowledged.fulfill()
                return ("{\"acknowledged\":1}", 0)
            default: return ("{\"triggers\":[],\"messages\":[],\"surveys\":[]}", 0)
            }
        }
        let (runtime, session) = try makeRuntime(flushInterval: 60)
        runtime.consentStore.update(Consent(analytics: true, feedback: true))
        runtime.start()
        withExtendedLifetime(runtime) { wait(for: [acknowledged], timeout: 4) }
        session.invalidateAndCancel()
    }

    func testInboxContinuesPollingWhenNoEventsAreQueued() throws {
        let polled = expectation(description: "initial and periodic inbox reads")
        polled.expectedFulfillmentCount = 2
        StartupURLProtocol.handler = { request, _ in
            if request.url!.path == "/v1/sdk/session" { return ("{\"subjectToken\":\"st_poll_test\",\"subjectId\":\"poll-user\",\"expiresAt\":\"2099-01-01T00:00:00.000Z\"}", 0) }
            if request.url!.path == "/v1/sdk/instructions" { polled.fulfill() }
            return ("{\"instructions\":[]}", 0)
        }
        let (runtime, session) = try makeRuntime(flushInterval: 1)
        runtime.start()
        withExtendedLifetime(runtime) { wait(for: [polled], timeout: 4) }
        session.invalidateAndCancel()
    }

    private func makeRuntime(flushInterval: TimeInterval) throws -> (Runtime, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StartupURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = UserGistConfig(writeKey: "startup-\(UUID().uuidString)", environment: .development,
            apiURL: URL(string: "https://startup.test"), debug: false, flushInterval: flushInterval,
            flushBatchSize: 20, maxQueueSize: 100, triggerSyncInterval: 300)
        let secure = MemorySecureStore(writeKeyHash: config.writeKeyHash, logger: UserGistLogger(debug: false))
        return (try Runtime(config: config, session: session, secureStore: secure), session)
    }
}

// Package tests have no signed host entitlements. Keep credentials in test
// memory while exercising the real session, transport and inbox runtime.
private final class MemorySecureStore: SecureStore {
    private var values: [String: Data] = [:]
    override func read(_ key: Key) -> Data? { values[key.rawValue] }
    override func write(_ key: Key, _ data: Data) -> Bool { values[key.rawValue] = data; return true }
    override func delete(_ key: Key) -> Bool { values[key.rawValue] = nil; return true }
}

private final class StartupURLProtocol: URLProtocol {
    static var handler: ((URLRequest, [String: Any]) -> (String, TimeInterval))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let (payload, delay) = Self.handler(request, body)
        let send = {
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data("{\"success\":true,\"data\":\(payload)}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: send) }
        else { send() }
    }
    override func stopLoading() {}
}
