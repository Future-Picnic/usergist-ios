import Foundation

/// Coordinates flushing the `EventQueue` to the ingest endpoint, sending
/// consent changes, identify calls, and feedback responses.
///
/// Runs on the SDK's internal serial queue. All APIs are fire-and-forget;
/// internal failures are logged and retried by the policy.
final class Transport {
    private let config: UserGistConfig
    private let apiClient: APIClient
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private weak var eventQueue: EventQueue?
    private weak var identity: IdentityStore?
    private weak var consent: ConsentStore?

    private var isFlushing = false
    private var flushTimer: DispatchSourceTimer?

    init(
        config: UserGistConfig,
        apiClient: APIClient,
        logger: UserGistLogger,
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
        guard let consent else { return }
        let currentConsent = consent.current()
        guard currentConsent.analytics == true || currentConsent.feedback == true else { return }
        guard let eventQueue, !eventQueue.isEmpty else { return }
        let allowed = eventQueue.snapshot().filter { event in
            event.purpose == .analytics
                ? currentConsent.analytics == true
                : currentConsent.feedback == true
        }
        guard let first = allowed.first else { return }
        let batch = Array(allowed.filter {
            $0.anonymousId == first.anonymousId && $0.externalId == first.externalId
        }.prefix(config.flushBatchSize))
        guard !batch.isEmpty else { return }

        isFlushing = true
        let context = IngestContext.current(
            anonymousId: first.anonymousId,
            externalId: first.externalId,
            sdkVersion: config.sdkVersion
        )
        let payload = IngestPayload(events: batch.map(WireIngestEvent.init), context: context)
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
                    self.eventQueue?.remove(eventIds: Set(batch.map(\.eventId)))
                    self.logger.debug("flushed \(batch.count) events")
                    // If there's more left, schedule another pass on the queue.
                    if let q = self.eventQueue, !q.isEmpty {
                        self.queue.async { self.flushIfNeeded() }
                    }
                case .failure(let err):
                    if case .server(let status, _) = err,
                       (400..<500).contains(status), status != 429 {
                        if batch.count == 1 {
                            self.eventQueue?.remove(eventIds: [first.eventId])
                            self.logger.warn("quarantined permanently rejected event \(first.eventId)")
                            self.queue.async { self.flushIfNeeded() }
                        } else {
                            self.flushSingleForIsolation(first, context: context)
                        }
                    } else {
                        self.logger.warn("flush failed: \(err)")
                    }
                }
            }
        }
    }

    private func flushSingleForIsolation(_ event: IngestEvent, context: IngestContext) {
        let payload = IngestPayload(events: [WireIngestEvent(event)], context: context)
        apiClient.postJSON(
            path: SDKEndpoint.ingest,
            body: payload,
            responseType: IngestResponse.self
        ) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success:
                    self.eventQueue?.remove(eventIds: [event.eventId])
                    self.flushIfNeeded()
                case .failure(.server(let status, _))
                    where (400..<500).contains(status) && status != 429:
                    self.eventQueue?.remove(eventIds: [event.eventId])
                    self.logger.warn("quarantined permanently rejected event \(event.eventId)")
                    self.flushIfNeeded()
                case .failure(let error):
                    self.logger.warn("single-event isolation failed: \(error)")
                }
            }
        }
    }

    // MARK: - Consent

    func sendConsent(_ consent: Consent) {
        guard let identity, let consentStore = self.consent else { return }
        let snap = identity.current()
        let current = consentStore.current()
        let payload = ConsentPayload(
            anonymousId: snap.anonymousId,
            externalId: snap.externalId,
            purposes: Consent(
                analytics: current.analytics ?? false,
                feedback: current.feedback ?? false,
                push: current.push ?? false,
                survey: current.survey ?? false
            ),
            version: consentStore.version,
            effectiveAt: consentStore.updatedAt
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
            properties: AnyCodable.wrapEventProperties(properties)
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
    let events: [WireIngestEvent]
    let context: IngestContext
}

struct WireIngestEvent: Encodable {
    let eventId: String
    let name: String
    let timestamp: Date
    let anonymousId: String
    let externalId: String?
    let properties: [String: AnyCodable]?
    let sessionId: String?
    let sdkVersion: String
    let appVersion: String?
    let platform: String

    init(_ event: IngestEvent) {
        eventId = event.eventId
        name = event.name
        timestamp = event.timestamp
        anonymousId = event.anonymousId
        externalId = event.externalId
        properties = event.properties
        sessionId = event.sessionId
        sdkVersion = event.sdkVersion
        appVersion = event.appVersion
        platform = event.platform
    }
}

struct IngestResponse: Decodable {
    let accepted: Int?
    let rejected: Int?
}

struct ConsentPayload: Encodable {
    let anonymousId: String
    let externalId: String?
    let purposes: Consent
    let version: Int
    let effectiveAt: Date
}

struct IdentifyPayload: Encodable {
    let anonymousId: String
    let externalId: String
    let properties: [String: AnyCodable]?
}

struct SubmitResponsePayload: Codable {
    let idempotencyKey: String
    let promptId: String
    let anonymousId: String
    let externalId: String?
    let answers: [ResponseAnswerWire]?
    let dismissed: Bool?
    let latencyMs: Int?
}

struct ResponseAnswerWire: Codable {
    let questionId: String
    let value: AnswerValueWire
}

enum AnswerValueWire: Codable {
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

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String].self) { self = .list(value) }
        else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported feedback answer value"
            )
        }
    }
}
