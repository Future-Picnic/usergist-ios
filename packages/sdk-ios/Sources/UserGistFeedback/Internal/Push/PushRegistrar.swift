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

    private var lastRegistered: String?

    init(
        apiClient: APIClient,
        identity: IdentityStore,
        consent: ConsentStore,
        logger: UserGistLogger,
        queue: DispatchQueue,
        environment: String
    ) {
        self.apiClient = apiClient
        self.identity = identity
        self.consent = consent
        self.logger = logger
        self.queue = queue
        self.environment = environment
    }

    func register(token: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.consent.allowsPush else {
                self.logger.debug("push register skipped: consent not granted")
                return
            }
            if self.lastRegistered == token { return }
            let snap = self.identity.current()

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

            self.apiClient.postVoid(path: SDKEndpoint.pushRegisterToken, body: payload) { [weak self] result in
                switch result {
                case .success:
                    self?.lastRegistered = token
                    self?.logger.debug("push token registered")
                case .failure(let err):
                    self?.logger.warn("push token registration failed: \(err)")
                }
            }
        }
    }

    func invalidate(token: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let snap = self.identity.current()
            let payload = InvalidateTokenPayload(
                anonymousId: snap.anonymousId,
                token: token
            )
            self.apiClient.postVoid(path: SDKEndpoint.pushInvalidateToken, body: payload) { [weak self] result in
                if case .success = result, self?.lastRegistered == token {
                    self?.lastRegistered = nil
                }
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

    func reset() {
        queue.async { [weak self] in self?.lastRegistered = nil }
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
