import Foundation

/// Registers device tokens with the Ritmus control plane. Idempotent —
/// repeated calls with the same token are cheap.
final class PushRegistrar {
    private let apiClient: APIClient
    private let identity: IdentityStore
    private let consent: ConsentStore
    private let logger: RitmusLogger
    private let queue: DispatchQueue

    private var lastRegistered: String?

    init(
        apiClient: APIClient,
        identity: IdentityStore,
        consent: ConsentStore,
        logger: RitmusLogger,
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
                sdkVersion: RitmusConfig.currentSDKVersion,
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
