import XCTest
@testable import UserGistFeedback

final class IdentityLifecycleTests: XCTestCase {
    func testFreshIdentifyReplacesQueuedTokenAndKeepsGuestProperties() throws {
        let secure = IdentityMemoryStore(writeKeyHash: UUID().uuidString, logger: UserGistLogger(debug: false))
        let queue = MutationQueue(secure: secure, logger: UserGistLogger(debug: false))
        func body(_ token: String, _ properties: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["anonymousId": "install", "externalId": "backend-id", "subjectToken": token, "properties": properties])
        }
        let old = queue.enqueue(kind: .identify, purpose: .essential, payload: try body("st_expired", ["plan": "free", "isAnonymous": true]), dedupeKey: "identify:backend-id")!
        let fresh = queue.enqueue(kind: .identify, purpose: .essential, payload: try body("st_fresh", ["isAnonymous": false]), dedupeKey: "identify:backend-id")!
        XCTAssertNotEqual(old, fresh)
        queue.remove(old)
        let restored = MutationQueue(secure: secure, logger: UserGistLogger(debug: false))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: restored.first!.payload) as? [String: Any])
        XCTAssertEqual(payload["subjectToken"] as? String, "st_fresh")
        XCTAssertEqual((payload["properties"] as? [String: Any])?["plan"] as? String, "free")
        XCTAssertEqual((payload["properties"] as? [String: Any])?["isAnonymous"] as? Bool, false)
    }

    func testPropertiesUseConfirmedInstallationTokenAndRemoveEmailWithoutChangingIdentity() throws {
        let synced = expectation(description: "identified"), updated = expectation(description: "properties acknowledged")
        IdentityURLProtocol.handler = { request, body in
            if request.url!.path == "/v1/sdk/identify" {
                XCTAssertEqual(body["previousSubjectToken"] as? String, "st_anonymous")
                XCTAssertEqual((body["properties"] as? [String: Any])?["email"] as? String, "guest@example.test")
                return (200, "{\"subjectToken\":\"st_bound\",\"filteredKeys\":[]}", 0)
            }
            if request.url!.path == "/v1/sdk/user-properties" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-UserGist-Subject-Token"), "st_bound")
                XCTAssertEqual(body["unset"] as? [String], ["email"])
                XCTAssertNotNil(UUID(uuidString: body["mutationId"] as? String ?? ""))
                return (200, "{\"applied\":true,\"filteredKeys\":[]}", 0)
            }
            return Self.defaultReply(request)
        }
        let (runtime, session, _) = try makeRuntime()
        runtime.consentStore.update(Consent(analytics: true))
        runtime.start()
        runtime.work { runtime.identify(userId: "backend-id", properties: ["isAnonymous": true, "email": "guest@example.test"], subjectToken: "st_backend") { result in
            // Startup may queue identification; the observer below confirms delivery.
            XCTAssertNotEqual(result, .rejected)
        } }
        runtime.onIdentityState = { state in if state.status == .identified { synced.fulfill() } }
        wait(for: [synced], timeout: 3)
        let alias = runtime.anonymousId
        runtime.work { runtime.setUserProperties(["isAnonymous": false], unset: ["email"]) { result in
            XCTAssertEqual(result, .synced); updated.fulfill()
        } }
        wait(for: [updated], timeout: 3)
        XCTAssertEqual(runtime.externalId, "backend-id")
        XCTAssertEqual(runtime.anonymousId, alias)
        let stopped = expectation(description: "runtime stopped")
        runtime.work { runtime.stop(); session.invalidateAndCancel(); stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
    }

    func testResetCompletesLocallyWhileLogoutDeliveryIsWaiting() throws {
        let synced = expectation(description: "identified"), reset = expectation(description: "local reset")
        IdentityURLProtocol.handler = { request, _ in
            if request.url!.path == "/v1/sdk/identify" { return (200, "{\"subjectToken\":\"st_bound\"}", 0) }
            if request.url!.path == "/v1/sdk/session/revoke" { return (200, "{}", 2) }
            return Self.defaultReply(request)
        }
        let (runtime, session, secure) = try makeRuntime()
        runtime.onIdentityState = { if $0.status == .identified { synced.fulfill() } }
        runtime.start()
        runtime.work { runtime.identify(userId: "account-a", properties: nil, subjectToken: "st_backend") }
        wait(for: [synced], timeout: 3)
        let oldAlias = runtime.anonymousId
        runtime.work { runtime.reset { success in XCTAssertTrue(success); reset.fulfill() } }
        wait(for: [reset], timeout: 1)
        XCTAssertNil(runtime.externalId)
        XCTAssertNotEqual(runtime.anonymousId, oldAlias)
        let entries = try XCTUnwrap(try JSONSerialization.jsonObject(with: secure.read(.sessionRevocations)!) as? [[String: String]])
        XCTAssertEqual(entries.first?["token"], "st_bound")
        XCTAssertEqual(entries.first?["anonymousId"], oldAlias)
        let stopped = expectation(description: "runtime stopped")
        runtime.work { runtime.stop(); session.invalidateAndCancel(); stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
    }

    func testExpiredIdentifiedSessionRefreshesWithoutRotatingGuestBackendId() throws {
        let recovered = expectation(description: "server confirmed recovered identity")
        IdentityURLProtocol.handler = { request, _ in
            if request.url!.path == "/v1/sdk/session" { return (401, "{}", 0) }
            if request.url!.path == "/v1/sdk/identify" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-UserGist-Subject-Token"), "st_refreshed")
                return (200, "{\"subjectToken\":\"st_recovered_installation\"}", 0)
            }
            return Self.defaultReply(request)
        }
        let (runtime, session, secure) = try makeRuntime()
        runtime.identityStore.setExternalId("guest-backend-id")
        secure.write(.subjectToken, Data("st_expired".utf8))
        let alias = runtime.anonymousId
        runtime.subjectTokenProvider = { id, complete in
            XCTAssertEqual(id, "guest-backend-id"); complete(.success("st_refreshed"))
        }
        runtime.onIdentityState = { state in
            if state.status == .identified {
                XCTAssertEqual(String(data: secure.read(.subjectToken) ?? Data(), encoding: .utf8), "st_recovered_installation")
                recovered.fulfill()
            }
        }
        runtime.start()
        wait(for: [recovered], timeout: 5)
        XCTAssertEqual(runtime.externalId, "guest-backend-id")
        XCTAssertEqual(runtime.anonymousId, alias)
        let stopped = expectation(description: "runtime stopped")
        runtime.work { runtime.stop(); session.invalidateAndCancel(); stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
    }

    func testFailedIdentityPersistenceKeepsLogoutPausedAndCanBeRetried() throws {
        IdentityURLProtocol.handler = { request, _ in Self.defaultReply(request) }
        let (runtime, session, secure) = try makeRuntime()
        runtime.identityStore.setExternalId("account-a")
        secure.write(.subjectToken, Data("st_original".utf8))
        let alias = runtime.anonymousId
        secure.failIdentityWrites = true
        let failed = expectation(description: "reset failed safely")
        runtime.work { runtime.reset { success in XCTAssertFalse(success); failed.fulfill() } }
        wait(for: [failed], timeout: 1)
        XCTAssertEqual(runtime.externalId, "account-a")
        let rejected = expectation(description: "cannot switch while reset failed")
        runtime.work { runtime.identify(userId: "account-b", properties: nil, subjectToken: "st_b") { result in
            XCTAssertEqual(result, .rejected); rejected.fulfill()
        } }
        wait(for: [rejected], timeout: 1)
        secure.failIdentityWrites = false
        let reset = expectation(description: "retry completed")
        runtime.work { runtime.reset { success in XCTAssertTrue(success); reset.fulfill() } }
        wait(for: [reset], timeout: 1)
        XCTAssertNotEqual(runtime.anonymousId, alias)
        XCTAssertNil(runtime.externalId)
        let stopped = expectation(description: "runtime stopped")
        runtime.work { runtime.stop(); session.invalidateAndCancel(); stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
    }

    func testRestoredIdentityWaitsForSessionConfirmation() throws {
        let identifying = expectation(description: "restored identity is pending")
        let identified = expectation(description: "session accepted")
        IdentityURLProtocol.handler = { request, _ in
            if request.url!.path == "/v1/sdk/session" { return (200, "{\"subjectToken\":\"st_confirmed\",\"subjectId\":\"account-subject\",\"expiresAt\":\"2099-01-01T00:00:00.000Z\"}", 0.1) }
            return Self.defaultReply(request)
        }
        let (runtime, session, secure) = try makeRuntime()
        runtime.identityStore.setExternalId("account-a")
        secure.write(.subjectToken, Data("st_unchecked".utf8))
        runtime.onIdentityState = { state in
            if state.status == .identifying { identifying.fulfill() }
            if state.status == .identified {
                XCTAssertEqual(String(data: secure.read(.subjectToken) ?? Data(), encoding: .utf8), "st_confirmed")
                identified.fulfill()
            }
        }
        runtime.start()
        wait(for: [identifying, identified], timeout: 3, enforceOrder: true)
        let stopped = expectation(description: "runtime stopped")
        runtime.work { runtime.stop(); session.invalidateAndCancel(); stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
    }

    func testPushInvalidationSurvivesRetryAndRegistrarRestart() throws {
        let registered = expectation(description: "first registration")
        let invalidated = expectation(description: "invalidation reached server")
        let registeredAgain = expectation(description: "explicit registration allowed")
        var registrationCount = 0
        IdentityURLProtocol.handler = { request, _ in
            if request.url!.path.hasSuffix("/register-token") {
                registrationCount += 1
                return (200, "{\"registered\":true}", 0)
            }
            if request.url!.path.hasSuffix("/invalidate-token") { invalidated.fulfill() }
            return Self.defaultReply(request)
        }
        let (runtime, session, secure) = try makeRuntime()
        runtime.apiClient.setSubjectToken("st_anonymous")
        runtime.consentStore.update(Consent(push: true))
        let queue = DispatchQueue(label: "push-invalidation-test")
        func registrar() -> PushRegistrar {
            PushRegistrar(apiClient: runtime.apiClient, identity: runtime.identityStore,
                consent: runtime.consentStore, logger: runtime.logger, queue: queue,
                environment: "sandbox", secure: secure)
        }
        let first = registrar()
        first.onSubscriptionState = { if $0.registered { registered.fulfill() } }
        first.register(token: "device")
        wait(for: [registered], timeout: 2)
        first.invalidate(token: "device")
        wait(for: [invalidated], timeout: 2)
        XCTAssertNil(secure.read(.pushToken))
        let restarted = registrar()
        let retrySkipped = expectation(description: "restart has no candidate")
        restarted.onSubscriptionState = { state in
            XCTAssertFalse(state.registered)
            XCTAssertFalse(state.tokenAvailable)
            retrySkipped.fulfill()
        }
        queue.async { restarted.retryRegistration() }
        wait(for: [retrySkipped], timeout: 2)
        XCTAssertEqual(registrationCount, 1)
        restarted.onSubscriptionState = { if $0.registered { registeredAgain.fulfill() } }
        restarted.register(token: "device")
        wait(for: [registeredAgain], timeout: 2)
        XCTAssertEqual(registrationCount, 2)
        session.invalidateAndCancel()
    }

    func testPushInvalidationWaitsForAnInflightRegistration() throws {
        let entered = expectation(description: "registration in flight")
        let invalidated = expectation(description: "invalidation follows registration")
        let (runtime, session, secure) = try makeRuntime()
        runtime.apiClient.setSubjectToken("st_anonymous")
        runtime.consentStore.update(Consent(push: true))
        var registrations = 0
        IdentityURLProtocol.handler = { request, _ in
            if request.url!.path.hasSuffix("/register-token") {
                registrations += 1
                entered.fulfill()
                return (200, "{\"registered\":true}", 0.1)
            }
            if request.url!.path.hasSuffix("/invalidate-token") {
                XCTAssertNil(secure.read(.pushToken))
                invalidated.fulfill()
            }
            return Self.defaultReply(request)
        }
        let queue = DispatchQueue(label: "push-order-test")
        let registrar = PushRegistrar(apiClient: runtime.apiClient, identity: runtime.identityStore,
            consent: runtime.consentStore, logger: runtime.logger, queue: queue,
            environment: "sandbox", secure: secure)
        registrar.register(token: "device")
        wait(for: [entered], timeout: 2)
        registrar.invalidate(token: "device")
        queue.async { registrar.retryRegistration() }
        wait(for: [invalidated], timeout: 2)
        let unregistered = expectation(description: "automatic retry cannot revive token")
        registrar.onSubscriptionState = { state in
            XCTAssertFalse(state.registered)
            XCTAssertFalse(state.tokenAvailable)
            unregistered.fulfill()
        }
        queue.async { registrar.retryRegistration() }
        wait(for: [unregistered], timeout: 2)
        XCTAssertEqual(registrations, 1)
        session.invalidateAndCancel()
    }

    private static func defaultReply(_ request: URLRequest) -> (Int, String, TimeInterval) {
        if request.url!.path == "/v1/sdk/session" { return (200, "{\"subjectToken\":\"st_anonymous\",\"subjectId\":\"subject\",\"expiresAt\":\"2099-01-01T00:00:00.000Z\"}", 0) }
        return (200, "{\"triggers\":[],\"messages\":[],\"surveys\":[],\"instructions\":[],\"accepted\":0,\"rejected\":0}", 0)
    }
    private func makeRuntime() throws -> (Runtime, URLSession, IdentityMemoryStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdentityURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = UserGistConfig(writeKey: "identity-\(UUID().uuidString)", environment: .development,
            apiURL: URL(string: "https://identity.test"), debug: false, flushInterval: 60,
            flushBatchSize: 20, maxQueueSize: 100, triggerSyncInterval: 300)
        let secure = IdentityMemoryStore(writeKeyHash: config.writeKeyHash, logger: UserGistLogger(debug: false))
        return (try Runtime(config: config, session: session, secureStore: secure), session, secure)
    }
}

private final class IdentityMemoryStore: SecureStore {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    var failIdentityWrites = false
    override func read(_ key: Key) -> Data? { lock.lock(); defer { lock.unlock() }; return values[key.rawValue] }
    override func write(_ key: Key, _ data: Data) -> Bool { lock.lock(); defer { lock.unlock() }; if key == .identity && failIdentityWrites { return false }; values[key.rawValue] = data; return true }
    override func delete(_ key: Key) -> Bool { lock.lock(); defer { lock.unlock() }; values[key.rawValue] = nil; return true }
}
private final class IdentityURLProtocol: URLProtocol {
    static var handler: ((URLRequest, [String: Any]) -> (Int, String, TimeInterval))!
    private var cancelled = false
    private let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
        let (status, payload, delay) = Self.handler(request, body)
        let send = {
            self.lock.lock(); let cancelled = self.cancelled; self.lock.unlock()
            guard !cancelled else { return }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data("{\"success\":\(status == 200),\"data\":\(payload)}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: send) } else { send() }
    }
    override func stopLoading() { lock.lock(); cancelled = true; lock.unlock() }
}
