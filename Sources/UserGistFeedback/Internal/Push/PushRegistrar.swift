import Foundation

/// Registers device tokens with the UserGist control plane. Idempotent —
/// repeated calls with the same token are cheap.
final class PushRegistrar {
    private let apiClient: APIClient
    private let identity: IdentityStore
    private let consent: ConsentStore
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private let environment: String
    private let secure: SecureStore
    var canRegister: (() -> Bool)?
    var onSubscriptionState: ((PushSubscriptionState) -> Void)?
    private var registrationAttempt: UUID?
    private var registeredIdentity: String?
    private var lastRegistrationAt: Date = .distantPast

    private var lastRegistered: String?
    private var operations: [(@escaping () -> Void) -> Void] = []
    private var operationRunning = false

    // All token mutations finish in request order, including an invalidation
    // requested while registration is still waiting for its server response.
    private func enqueue(_ operation: @escaping (@escaping () -> Void) -> Void) {
        operations.append(operation)
        drainOperations()
    }

    private func drainOperations() {
        guard !operationRunning, !operations.isEmpty else { return }
        operationRunning = true
        let operation = operations.removeFirst()
        operation { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.operationRunning = false
                self.drainOperations()
            }
        }
    }

    init(
        apiClient: APIClient,
        identity: IdentityStore,
        consent: ConsentStore,
        logger: UserGistLogger,
        queue: DispatchQueue,
        environment: String,
        secure: SecureStore
    ) {
        self.apiClient = apiClient
        self.identity = identity
        self.consent = consent
        self.logger = logger
        self.queue = queue
        self.environment = environment
        self.secure = secure
    }

    func register(token: String, automatic: Bool = false) {
        let requestedAlias = identity.anonymousId
        queue.async { [weak self] in
            guard let self else { return }
            self.enqueue { done in
                var awaitingResponse = false
                defer { if !awaitingResponse { done() } }
                guard requestedAlias == self.identity.anonymousId else { return }
                if automatic && self.secure.read(.pushToken) != Data(token.utf8) { return }
                guard self.secure.read(.pushToken) == Data(token.utf8) || self.secure.write(.pushToken, Data(token.utf8)) else {
                    self.logger.warn("push registration could not be persisted"); return
                }
                guard self.consent.allowsPush else {
                    self.emitState()
                    self.logger.debug("push register skipped: consent not granted")
                    return
                }
                guard self.canRegister?() != false else { self.emitState(); return }
                let snap = self.identity.current()
                let owner = snap.anonymousId + ":" + (snap.externalId ?? "")
                if self.registrationAttempt != nil { return }
                if self.lastRegistered == token && self.registeredIdentity == owner && Date().timeIntervalSince(self.lastRegistrationAt) < 86400 { return }
                let attempt = UUID()
                self.registrationAttempt = attempt
                self.emitState()

                let payload = RegisterTokenPayload(
                    anonymousId: snap.anonymousId,
                    externalId: snap.externalId,
                    token: token,
                    platform: "ios",
                    environment: self.environment,
                    language: Locale.current.identifier,
                    timezone: TimeZone.current.identifier,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    sdkVersion: UserGistConfig.currentSDKVersion,
                    optIn: true
                )

                awaitingResponse = true
                self.apiClient.postJSON(path: SDKEndpoint.pushRegisterToken, body: payload, responseType: RegistrationResponse.self) { [weak self] result in
                    guard let self else { done(); return }
                    self.queue.async {
                        defer { done() }
                        guard self.registrationAttempt == attempt else { return }
                        self.registrationAttempt = nil
                        guard self.identity.current().anonymousId == snap.anonymousId,
                              self.identity.current().externalId == snap.externalId, self.consent.allowsPush,
                              self.secure.read(.pushToken) == Data(token.utf8) else {
                            self.retryRegistration()
                            return
                        }
                        if case .success(let response) = result, response.registered == true {
                            self.lastRegistered = token
                            self.registeredIdentity = owner
                            self.lastRegistrationAt = Date()
                        }
                        self.emitState()
                    }
                }
            }
        }
    }

    func invalidate(token: String) {
        let requestedAlias = identity.anonymousId
        queue.async { [weak self] in
            guard let self else { return }
            self.enqueue { done in
                let snap = self.identity.current()
                guard requestedAlias == snap.anonymousId else { done(); return }
                if self.secure.read(.pushToken) == Data(token.utf8) {
                    guard self.secure.delete(.pushToken) else { done(); return }
                }
                if self.lastRegistered == token {
                    self.lastRegistered = nil
                    self.registeredIdentity = nil
                }
                self.emitState()
                let payload = InvalidateTokenPayload(anonymousId: snap.anonymousId, token: token)
                self.apiClient.postVoid(path: SDKEndpoint.pushInvalidateToken, body: payload) { _ in done() }
            }
        }
    }

    /// Re-bind the most-recently-registered token to a newly identified user.
    func rebind(externalId: String) {
        queue.async { [weak self] in
            guard let self, let token = self.lastRegistered else { return }
            let snap = self.identity.current()
            let payload = RebindPayload(
                anonymousId: snap.anonymousId,
                externalId: externalId,
                token: token
            )
            self.apiClient.postVoid(path: SDKEndpoint.pushRebind, body: payload) { _ in }
        }
    }

    /// Forward an applicationDidBecomeActive signal to the server. Used by
    /// the adaptive reachability policy to skip silent pings for known-
    /// active users.
    func reportAppOpen() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.lastRegistered != nil else {
                self.logger.debug("push app-open skipped: no registered token")
                return
            }
            let snap = self.identity.current()
            let payload = AppOpenPayload(
                anonymousId: snap.anonymousId,
                occurredAt: ISO8601DateFormatter().string(from: Date())
            )
            self.apiClient.postVoid(path: SDKEndpoint.pushAppOpen, body: payload) { _ in }
        }
    }

    /// SDK-side delivered/displayed/dismissed beacon. Distinct from the
    /// NSE-side beacon: this fires when the SDK first sees the payload in
    /// foreground/main code paths (the NSE has already fired earlier in
    /// the OS receive cycle).
    func beacon(kind: PushBeaconKind, deliveryId: String, actionButton: String? = nil) {
        guard !deliveryId.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let payload = BeaconPayload(
                deliveryId: deliveryId,
                occurredAt: ISO8601DateFormatter().string(from: Date()),
                actionButton: actionButton
            )
            let path: String
            switch kind {
            case .delivered: path = SDKEndpoint.pushDelivered
            case .displayed: path = SDKEndpoint.pushDisplayed
            case .dismissed: path = SDKEndpoint.pushDismissed
            }
            self.apiClient.postVoid(path: path, body: payload) { _ in }
        }
    }

    func acknowledgeSilent(pingId: String) {
        guard !pingId.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let payload = SilentAckPayload(
                pingId: pingId,
                anonymousId: self.identity.current().anonymousId,
                receivedAt: ISO8601DateFormatter().string(from: Date())
            )
            self.apiClient.postVoid(path: SDKEndpoint.pushSilentAck, body: payload) { _ in }
        }
    }

    func fetchChannels(completion: @escaping ([UserGistPushChannel]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.apiClient.get(
                path: SDKEndpoint.pushChannels,
                responseType: PushChannelsEnvelope.self
            ) { result in
                switch result {
                case .success(let envelope): completion(envelope.channels)
                case .failure(let error):
                    self.logger.warn("push channel fetch failed: \(error)")
                    completion([])
                }
            }
        }
    }

    func setChannelSubscription(channelId: String, subscribed: Bool) {
        guard !channelId.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let payload = ChannelSubscriptionPayload(
                anonymousId: self.identity.current().anonymousId,
                channelId: channelId,
                subscribed: subscribed
            )
            self.apiClient.postVoid(
                path: SDKEndpoint.pushChannelSubscription,
                body: payload
            ) { _ in }
        }
    }

    func emitState() {
        let snap = identity.current()
        onSubscriptionState?(PushSubscriptionState(tokenAvailable: secure.read(.pushToken) != nil,
            registered: consent.allowsPush && registeredIdentity == snap.anonymousId + ":" + (snap.externalId ?? "") && lastRegistered != nil,
            optedIn: consent.allowsPush, anonymousId: snap.anonymousId, externalId: snap.externalId))
    }

    func retryRegistration() {
        guard let data = secure.read(.pushToken), let token = String(data: data, encoding: .utf8) else { emitState(); return }
        register(token: token, automatic: true)
    }

    func reset() {
        lastRegistered = nil
        registeredIdentity = nil
        registrationAttempt = nil
        emitState()
    }

}

private struct RegisterTokenPayload: Encodable {
    let anonymousId: String
    let externalId: String?
    let token: String
    let platform: String
    let environment: String
    let language: String?
    let timezone: String?
    let appVersion: String?
    let sdkVersion: String?
    let optIn: Bool
}

private struct InvalidateTokenPayload: Encodable {
    let anonymousId: String
    let token: String
}

private struct RebindPayload: Encodable {
    let anonymousId: String
    let externalId: String
    let token: String
}

private struct AppOpenPayload: Encodable {
    let anonymousId: String
    let occurredAt: String
}

private struct BeaconPayload: Encodable {
    let deliveryId: String
    let occurredAt: String
    let actionButton: String?
}

private struct SilentAckPayload: Encodable {
    let pingId: String
    let anonymousId: String
    let receivedAt: String
}

private struct PushChannelsEnvelope: Decodable {
    let channels: [UserGistPushChannel]
}

private struct ChannelSubscriptionPayload: Encodable {
    let anonymousId: String
    let channelId: String
    let subscribed: Bool
}

enum PushBeaconKind {
    case delivered
    case displayed
    case dismissed
}

private struct RegistrationResponse: Decodable { let registered: Bool? }
