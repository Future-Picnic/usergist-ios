import Foundation

/// Minimal HTTP client over `URLSession` dedicated to the SDK's use.
///
/// Responsible for assembling requests, signing them with the write key,
/// applying the retry policy, and decoding JSON responses. All network
/// work happens on URLSession's internal queues; the callback is delivered
/// on the caller-supplied queue.
final class APIClient {
    enum APIError: Error {
        case invalidURL
        case transport(Error)
        case server(status: Int, body: Data?)
        case decoding(Error)
        case cancelled
        case maxAttemptsExceeded
        case subjectUnavailable
    }

    private let session: URLSession
    private let logger: UserGistLogger
    private let baseURL: URL
    private let writeKey: String
    private let sdkVersion: String
    private let retryPolicy: RetryPolicy
    private let callbackQueue: DispatchQueue
    private let credentialLock = NSLock()
    private var subjectToken: String?
    private var credentialWaiters: [UUID: () -> Void] = [:]

    init(
        baseURL: URL,
        writeKey: String,
        sdkVersion: String,
        logger: UserGistLogger,
        retryPolicy: RetryPolicy = .default,
        callbackQueue: DispatchQueue,
        session: URLSession? = nil,
        tlsPinSets: [TLSPinSet] = []
    ) {
        self.baseURL = baseURL
        self.writeKey = writeKey
        self.sdkVersion = sdkVersion
        self.logger = logger
        self.retryPolicy = retryPolicy
        self.callbackQueue = callbackQueue
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            if tlsPinSets.contains(where: { !$0.sha256Pins.isEmpty }) {
                let delegate = TLSPinnedSessionDelegate(pinSets: tlsPinSets, logger: logger)
                self.session = URLSession(
                    configuration: configuration,
                    delegate: delegate,
                    delegateQueue: nil
                )
            } else {
                self.session = URLSession(configuration: configuration)
            }
        }
    }

    // MARK: - Request building

    private func buildRequest(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil,
        body: Data? = nil,
        requiresSubject: Bool = true,
        subjectTokenOverride: String? = nil
    ) -> URLRequest? {
        guard var comp = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let query, !query.isEmpty {
            comp.queryItems = query
        }
        guard let url = comp.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(writeKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("UserGistFeedback-iOS/\(sdkVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue(sdkVersion, forHTTPHeaderField: "X-UserGist-SDK-Version")
        req.setValue("ios", forHTTPHeaderField: "X-UserGist-Platform")
        credentialLock.lock()
        let sharedToken = subjectToken
        credentialLock.unlock()
        let token = subjectTokenOverride ?? sharedToken
        if requiresSubject && token == nil { return nil }
        if let token {
            req.setValue(token, forHTTPHeaderField: "X-UserGist-Subject-Token")
        }
        if let body {
            req.httpBody = body
        }
        return req
    }

    // MARK: - Public methods

    /// Installs the server-minted credential that binds SDK calls to an
    /// anonymous installation or identified subject.
    func setSubjectToken(_ token: String?) {
        credentialLock.lock()
        subjectToken = token?.hasPrefix("st_") == true ? token : nil
        let waiters = subjectToken == nil ? [] : Array(credentialWaiters.values)
        if subjectToken != nil { credentialWaiters.removeAll() }
        credentialLock.unlock()
        for waiter in waiters { callbackQueue.async(execute: waiter) }
    }

    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    private func whenSubjectReady(
        required: Bool,
        onTimeout: @escaping () -> Void,
        perform: @escaping () -> Void
    ) {
        guard required else {
            perform()
            return
        }
        credentialLock.lock()
        if subjectToken != nil {
            credentialLock.unlock()
            perform()
            return
        }
        let id = UUID()
        credentialWaiters[id] = perform
        credentialLock.unlock()
        callbackQueue.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self else { return }
            self.credentialLock.lock()
            let pending = self.credentialWaiters.removeValue(forKey: id) != nil
            self.credentialLock.unlock()
            if pending { onTimeout() }
        }
    }

    /// Sends a POST request with a JSON body and returns the decoded response.
    func postJSON<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type,
        requiresSubject: Bool = true,
        idempotent: Bool = true,
        subjectTokenOverride: String? = nil,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        let data: Data
        do {
            data = try JSONEncoder.usergist().encode(body)
        } catch {
            callbackQueue.async { completion(.failure(.transport(error))) }
            return
        }
        whenSubjectReady(
            required: requiresSubject && subjectTokenOverride == nil,
            onTimeout: { completion(.failure(.subjectUnavailable)) }
        ) { [weak self] in
            guard let self,
                  let request = self.buildRequest(
                    method: "POST",
                    path: path,
                    body: data,
                    requiresSubject: requiresSubject,
                    subjectTokenOverride: subjectTokenOverride
                  ) else {
                completion(.failure(.invalidURL))
                return
            }
            self.performWithRetry(
                request: request,
                attempt: 0,
                allowRetry: idempotent,
                completion: completion
            )
        }
    }

    /// POST returning only success/failure (no response body expected).
    func postVoid<Request: Encodable>(
        path: String,
        body: Request,
        requiresSubject: Bool = true,
        subjectTokenOverride: String? = nil,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        postJSON(
            path: path,
            body: body,
            responseType: EmptyResponse.self,
            requiresSubject: requiresSubject,
            subjectTokenOverride: subjectTokenOverride
        ) { result in
            switch result {
            case .success: completion(.success(()))
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    /// GET with decoded response.
    func get<Response: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        responseType: Response.Type,
        requiresSubject: Bool = true,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        whenSubjectReady(
            required: requiresSubject,
            onTimeout: { completion(.failure(.subjectUnavailable)) }
        ) { [weak self] in
            guard let self,
                  let request = self.buildRequest(
                    method: "GET",
                    path: path,
                    query: query,
                    body: nil,
                    requiresSubject: requiresSubject
                  ) else {
                completion(.failure(.invalidURL))
                return
            }
            self.performWithRetry(request: request, attempt: 0, completion: completion)
        }
    }

    /// PATCH with JSON body + decoded response.
    func patchJSON<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type,
        requiresSubject: Bool = true,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        let data: Data
        do {
            data = try JSONEncoder.usergist().encode(body)
        } catch {
            callbackQueue.async { completion(.failure(.transport(error))) }
            return
        }
        whenSubjectReady(
            required: requiresSubject,
            onTimeout: { completion(.failure(.subjectUnavailable)) }
        ) { [weak self] in
            guard let self,
                  let request = self.buildRequest(
                    method: "PATCH",
                    path: path,
                    body: data,
                    requiresSubject: requiresSubject
                  ) else {
                completion(.failure(.invalidURL))
                return
            }
            self.performWithRetry(request: request, attempt: 0, completion: completion)
        }
    }

    /// DELETE returning only success/failure. Accepts optional query params
    /// (the SDK uses them to carry anonymousId on author-checked deletes).
    func deleteVoid(
        path: String,
        query: [URLQueryItem] = [],
        requiresSubject: Bool = true,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        whenSubjectReady(
            required: requiresSubject,
            onTimeout: { completion(.failure(.subjectUnavailable)) }
        ) { [weak self] in
            guard let self,
                  let request = self.buildRequest(
                    method: "DELETE",
                    path: path,
                    query: query,
                    body: nil,
                    requiresSubject: requiresSubject
                  ) else {
                completion(.failure(.invalidURL))
                return
            }
            self.performWithRetry(request: request, attempt: 0) {
                (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success: completion(.success(()))
                case .failure(let err): completion(.failure(err))
                }
            }
        }
    }

    // MARK: - Surveys (v1 surface)

    private struct AvailableSurveysEnvelope: Decodable {
        let surveys: [SurveySummary]
    }

    func getAvailableSurveys(
        anonymousId: String,
        externalId: String?,
        completion: @escaping (Result<[SurveySummary], APIError>) -> Void
    ) {
        var query: [URLQueryItem] = [URLQueryItem(name: "anonymousId", value: anonymousId)]
        if let externalId, !externalId.isEmpty {
            query.append(URLQueryItem(name: "externalId", value: externalId))
        }
        get(
            path: "/v1/sdk/surveys/available",
            query: query,
            responseType: AvailableSurveysEnvelope.self
        ) { result in
            switch result {
            case .success(let env): completion(.success(env.surveys))
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    private struct ResolveSurveyLinkRequest: Encodable {
        let token: String
        let anonymousId: String
        let externalId: String?
    }

    struct ResolveSurveyLinkResponse: Decodable {
        let surveyId: String
        let name: String?
        let consentRequired: Bool
        let openAccess: Bool
    }

    struct SurveyAttemptSession: Decodable {
        let attemptId: String
        let startQuestionId: String
        let progressSnapshot: [String: SurveyAnswerValue]
        let currentQuestionId: String?
        let resumed: Bool
    }

    private struct CreateSurveyAttemptBody: Encodable {
        let anonymousId: String
        let externalId: String?
        let source: String
        let language: String?
        let resume: Bool
        let sdkVersion: String
        let appVersion: String?
        let platform: String
    }

    private struct SurveyProgressBody: Encodable {
        let currentQuestionId: String?
        let progressSnapshot: [String: SurveyAnswerValue]
    }

    /// Fetch the full flow definition for `surveyId`. Used by the native
    /// renderer to drive question-by-question presentation.
    func getSurvey(
        surveyId: String,
        anonymousId: String,
        externalId: String?,
        language: String?,
        completion: @escaping (Result<SurveyCampaignWithFlow, APIError>) -> Void
    ) {
        var query: [URLQueryItem] = [URLQueryItem(name: "anonymousId", value: anonymousId)]
        if let externalId, !externalId.isEmpty {
            query.append(URLQueryItem(name: "externalId", value: externalId))
        }
        if let language, !language.isEmpty {
            query.append(URLQueryItem(name: "language", value: language))
        }
        get(
            path: SDKEndpoint.survey(surveyId),
            query: query,
            responseType: SurveyCampaignWithFlow.self,
            completion: completion
        )
    }

    /// Creates or resumes the server-authoritative attempt. Attempt ids must
    /// always originate here so progress and completion pass ownership checks.
    func createSurveyAttempt(
        surveyId: String,
        anonymousId: String,
        externalId: String?,
        source: String,
        language: String?,
        appVersion: String?,
        completion: @escaping (Result<SurveyAttemptSession, APIError>) -> Void
    ) {
        postJSON(
            path: SDKEndpoint.surveyAttempts(surveyId),
            body: CreateSurveyAttemptBody(
                anonymousId: anonymousId,
                externalId: externalId,
                source: source,
                language: language,
                resume: true,
                sdkVersion: sdkVersion,
                appVersion: appVersion,
                platform: "ios"
            ),
            responseType: SurveyAttemptSession.self,
            completion: completion
        )
    }

    func updateSurveyProgress(
        attemptId: String,
        currentQuestionId: String?,
        snapshot: [String: SurveyAnswerValue],
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        patchJSON(
            path: SDKEndpoint.surveyAttempt(attemptId),
            body: SurveyProgressBody(
                currentQuestionId: currentQuestionId,
                progressSnapshot: snapshot
            ),
            responseType: EmptyResponse.self
        ) { result in
            switch result {
            case .success: completion(.success(()))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Resolve a share-link token to a concrete survey id. Server returns 404
    /// for expired or unknown tokens, surfaced as APIError.
    func resolveSurveyLink(
        token: String,
        anonymousId: String,
        externalId: String?,
        completion: @escaping (Result<ResolveSurveyLinkResponse, APIError>) -> Void
    ) {
        let body = ResolveSurveyLinkRequest(
            token: token,
            anonymousId: anonymousId,
            externalId: externalId
        )
        postJSON(
            path: SDKEndpoint.resolveSurveyLink,
            body: body,
            responseType: ResolveSurveyLinkResponse.self
        ) { result in
            switch result {
            case .success(let res): completion(.success(res))
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    // MARK: - Retry loop

    private func performWithRetry<Response: Decodable>(
        request: URLRequest,
        attempt: Int,
        allowRetry: Bool = true,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        logger.debug("HTTP \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") attempt=\(attempt + 1)")
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error = error as NSError?, error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                self.callbackQueue.async { completion(.failure(.cancelled)) }
                return
            }
            if let error {
                guard allowRetry else {
                    self.callbackQueue.async { completion(.failure(.transport(error))) }
                    return
                }
                self.handleRetryable(
                    decision: .retryable(retryAfter: nil),
                    request: request,
                    attempt: attempt,
                    underlying: .transport(error),
                    completion: completion
                )
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let retryAfter = RetryAfterParser.parse(http?.value(forHTTPHeaderField: "Retry-After"))
            let decision = RetryDecision.classify(statusCode: status, retryAfter: retryAfter)
            switch decision {
            case .succeed:
                self.decode(data: data, completion: completion)
            case .retryable(let ra):
                guard allowRetry else {
                    self.callbackQueue.async {
                        completion(.failure(.server(status: status, body: data)))
                    }
                    return
                }
                self.handleRetryable(
                    decision: .retryable(retryAfter: ra),
                    request: request,
                    attempt: attempt,
                    underlying: .server(status: status, body: data),
                    completion: completion
                )
            case .permanent:
                self.callbackQueue.async {
                    completion(.failure(.server(status: status, body: data)))
                }
            }
        }
        task.resume()
    }

    private func handleRetryable<Response: Decodable>(
        decision: RetryDecision,
        request: URLRequest,
        attempt: Int,
        underlying: APIError,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        guard case .retryable(let retryAfter) = decision else {
            callbackQueue.async { completion(.failure(underlying)) }
            return
        }
        guard retryPolicy.canRetry(currentAttempt: attempt) else {
            callbackQueue.async { completion(.failure(underlying)) }
            return
        }
        let delay = retryPolicy.nextDelay(retryIndex: attempt, retryAfter: retryAfter)
        logger.debug("HTTP retry attempt=\(attempt + 2) in \(String(format: "%.2f", delay))s")
        callbackQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performWithRetry(request: request, attempt: attempt + 1, completion: completion)
        }
    }

    private func decode<Response: Decodable>(
        data: Data?,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        let bytes = data ?? Data("{}".utf8)
        let envelope: APIEnvelope<Response>
        do {
            envelope = try JSONDecoder.usergist().decode(APIEnvelope<Response>.self, from: bytes)
        } catch {
            logger.error("decode failed", error: error)
            callbackQueue.async { completion(.failure(.decoding(error))) }
            return
        }

        if envelope.success == false {
            let code = envelope.error?.code ?? "unknown"
            let message = envelope.error?.message ?? "API returned success=false"
            logger.error("API error \(code): \(message)")
            callbackQueue.async {
                completion(.failure(.server(status: 0, body: bytes)))
            }
            return
        }

        // Endpoints with an empty body still satisfy `EmptyResponse`.
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            callbackQueue.async { completion(.success(empty)) }
            return
        }

        guard let payload = envelope.data else {
            // success=true with no `data` is a contract violation. Surface it.
            callbackQueue.async {
                completion(.failure(.server(status: 0, body: bytes)))
            }
            return
        }

        callbackQueue.async { completion(.success(payload)) }
    }
}

/// Standard API envelope returned by every UserGist API route.
/// `data` is absent when `success=false`; `error` is absent when `success=true`.
private struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorEnvelope?
}

private struct APIErrorEnvelope: Decodable {
    let code: String
    let message: String
}

/// Marker type for endpoints that return no body of interest.
struct EmptyResponse: Codable, Equatable {}
