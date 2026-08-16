import Foundation

/// Registers device tokens with the UserGist control plane. Idempotent —
/// repeated calls with the same token are cheap.
final class PushRegistrar {
    private let apiClient: APIClient
    private let identity: IdentityStore
    private let consent: ConsentStore
    private let logger: UserGistLogger
    private let queue: DispatchQueue

    private var lastRegistered: String?

    init(
        apiClient: APIClient,
        identity: IdentityStore,
        consent: ConsentStore,
        logger: UserGistLogger,
        queue: DispatchQueue
    ) {
        self.apiClient = apiClient
        self.identity = identity
        self.consent = consent
        self.logger = logger
        self.queue = queue
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
                environment: PushRegistrar.environmentFlag(),
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
            self.apiClient.postVoid(path: SDKEndpoint.pushInvalidateToken, body: payload) { _ in }
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

    private static func environmentFlag() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
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

enum PushBeaconKind {
    case delivered
    case displayed
    case dismissed
}
