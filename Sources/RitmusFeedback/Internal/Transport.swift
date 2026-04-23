import Foundation

/// Coordinates flushing the `EventQueue` to the ingest endpoint, sending
/// consent changes, identify calls, and feedback responses.
///
/// Runs on the SDK's internal serial queue. All APIs are fire-and-forget;
/// internal failures are logged and retried by the policy.
final class Transport {
    private let config: RitmusConfig
    private let apiClient: APIClient
    private let logger: RitmusLogger
    private let queue: DispatchQueue
    private weak var eventQueue: EventQueue?
    private weak var identity: IdentityStore?
    private weak var consent: ConsentStore?

    private var isFlushing = false
    private var flushTimer: DispatchSourceTimer?

    init(
        config: RitmusConfig,
        apiClient: APIClient,
        logger: RitmusLogger,
        queue: DispatchQueue,
        eventQueue: EventQueue,
        identity: IdentityStore,
        consent: ConsentStore
    ) {
        self.config = config
        self.apiClient = apiClient
        self.logger = logger
        self.queue = queue
        self.eventQueue = eventQueue
        self.identity = identity
        self.consent = consent
    }

    // MARK: - Timer management

    func startPeriodicFlush() {
        stopPeriodicFlush()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flushIfNeeded()
        }
        timer.resume()
        flushTimer = timer
    }

    func stopPeriodicFlush() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    // MARK: - Batched flush

    func flushIfNeeded() {
        guard !isFlushing else { return }
        guard let consent, consent.allowsTransport else {
            logger.debug("flush skipped: consent not granted")
            return
        }
        guard let eventQueue, !eventQueue.isEmpty else { return }
        guard let identity else { return }

        let batch = eventQueue.head(size: config.flushBatchSize)
        guard !batch.isEmpty else { return }

        isFlushing = true
        let identitySnap = identity.current()
        let context = IngestContext.current(
            anonymousId: identitySnap.anonymousId,
            externalId: identitySnap.externalId,
            sdkVersion: config.sdkVersion
        )
        let payload = IngestPayload(events: batch, context: context)
        logger.debug("flushing \(batch.count) events")

        apiClient.postJSON(
            path: SDKEndpoint.ingest,
            body: payload,
            responseType: IngestResponse.self
        ) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                self.isFlushing = false
                switch result {
                case .success:
                    self.eventQueue?.drop(batch.count)
                    self.logger.debug("flushed \(batch.count) events")
                    // If there's more left, schedule another pass on the queue.
                    if let q = self.eventQueue, !q.isEmpty {
                        self.queue.async { self.flushIfNeeded() }
                    }
                case .failure(let err):
                    self.logger.warn("flush failed: \(err)")
                }
            }
        }
    }

    // MARK: - Consent

    func sendConsent(_ consent: Consent) {
        guard let identity else { return }
        let snap = identity.current()
        let payload = ConsentPayload(
            anonymousId: snap.anonymousId,
            externalId: snap.externalId,
            purposes: consent
        )
        apiClient.postVoid(path: SDKEndpoint.consent, body: payload) { [weak self] result in
            if case .failure(let err) = result {
                self?.logger.warn("consent post failed: \(err)")
            }
        }
    }

    // MARK: - Identify

    func sendIdentify(userId: String, properties: [String: Any]?) {
        guard let identity else { return }
        let snap = identity.current()
        let payload = IdentifyPayload(
            anonymousId: snap.anonymousId,
            externalId: userId,
            properties: AnyCodable.wrap(properties)
        )
        apiClient.postVoid(path: SDKEndpoint.identify, body: payload) { [weak self] result in
            if case .failure(let err) = result {
                self?.logger.warn("identify post failed: \(err)")
            }
        }
    }

    // MARK: - Responses

    func submitResponse(_ payload: SubmitResponsePayload) {
        apiClient.postVoid(path: SDKEndpoint.responses, body: payload) { [weak self] result in
            if case .failure(let err) = result {
                self?.logger.warn("response post failed: \(err)")
            }
        }
    }

    // MARK: - Armed triggers

    func fetchArmedTriggers(
        anonymousId: String,
        externalId: String?,
        completion: @escaping (Result<ArmedTriggersResponse, APIClient.APIError>) -> Void
    ) {
        var query: [URLQueryItem] = [URLQueryItem(name: "anonymousId", value: anonymousId)]
        if let externalId {
            query.append(URLQueryItem(name: "externalId", value: externalId))
        }
        apiClient.get(
            path: SDKEndpoint.armedTriggers,
            query: query,
            responseType: ArmedTriggersResponse.self,
            completion: completion
        )
    }
}

// MARK: - Wire payloads

struct IngestPayload: Encodable {
    let events: [IngestEvent]
    let context: IngestContext
}

struct IngestResponse: Decodable {
    let accepted: Int?
    let rejected: Int?
}

struct ConsentPayload: Encodable {
    let anonymousId: String
    let externalId: String?
    let purposes: Consent
}

struct IdentifyPayload: Encodable {
    let anonymousId: String
    let externalId: String
    let properties: [String: AnyCodable]?
}

struct SubmitResponsePayload: Encodable {
    let promptId: String
    let anonymousId: String
    let externalId: String?
    let answers: [ResponseAnswerWire]?
    let dismissed: Bool?
    let latencyMs: Int?
}

struct ResponseAnswerWire: Encodable {
    let questionId: String
    let value: AnswerValueWire
}

enum AnswerValueWire: Encodable {
    case number(Double)
    case string(String)
    case list([String])
    case null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .list(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
