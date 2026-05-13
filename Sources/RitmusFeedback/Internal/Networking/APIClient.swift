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
    }

    private let session: URLSession
    private let logger: RitmusLogger
    private let baseURL: URL
    private let writeKey: String
    private let sdkVersion: String
    private let retryPolicy: RetryPolicy
    private let callbackQueue: DispatchQueue

    init(
        baseURL: URL,
        writeKey: String,
        sdkVersion: String,
        logger: RitmusLogger,
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
        } else if tlsPinSets.contains(where: { !$0.sha256Pins.isEmpty }) {
            let delegate = TLSPinnedSessionDelegate(pinSets: tlsPinSets, logger: logger)
            self.session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
        } else {
            self.session = .shared
        }
    }

    // MARK: - Request building

    private func buildRequest(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil,
        body: Data? = nil
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
        req.setValue("RitmusFeedback-iOS/\(sdkVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue(sdkVersion, forHTTPHeaderField: "X-Ritmus-SDK-Version")
        req.setValue("ios", forHTTPHeaderField: "X-Ritmus-Platform")
        if let body {
            req.httpBody = body
        }
        return req
    }

    // MARK: - Public methods

    /// Sends a POST request with a JSON body and returns the decoded response.
    func postJSON<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        let data: Data
        do {
            data = try JSONEncoder.ritmus().encode(body)
        } catch {
            callbackQueue.async { completion(.failure(.transport(error))) }
            return
        }
        guard let request = buildRequest(method: "POST", path: path, body: data) else {
            callbackQueue.async { completion(.failure(.invalidURL)) }
            return
        }
        performWithRetry(request: request, attempt: 0, completion: completion)
    }

    /// POST returning only success/failure (no response body expected).
    func postVoid<Request: Encodable>(
        path: String,
        body: Request,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        postJSON(path: path, body: body, responseType: EmptyResponse.self) { result in
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
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        guard let request = buildRequest(method: "GET", path: path, query: query, body: nil) else {
            callbackQueue.async { completion(.failure(.invalidURL)) }
            return
        }
        performWithRetry(request: request, attempt: 0, completion: completion)
    }

    /// PATCH with JSON body + decoded response.
    func patchJSON<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type,
        completion: @escaping (Result<Response, APIError>) -> Void
    ) {
        let data: Data
        do {
            data = try JSONEncoder.ritmus().encode(body)
        } catch {
            callbackQueue.async { completion(.failure(.transport(error))) }
            return
        }
        guard let request = buildRequest(method: "PATCH", path: path, body: data) else {
            callbackQueue.async { completion(.failure(.invalidURL)) }
            return
        }
        performWithRetry(request: request, attempt: 0, completion: completion)
    }

    /// DELETE returning only success/failure. Accepts optional query params
    /// (the SDK uses them to carry anonymousId on author-checked deletes).
    func deleteVoid(
        path: String,
        query: [URLQueryItem] = [],
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        guard let request = buildRequest(method: "DELETE", path: path, query: query, body: nil) else {
            callbackQueue.async { completion(.failure(.invalidURL)) }
            return
        }
        performWithRetry(request: request, attempt: 0) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success: completion(.success(()))
            case .failure(let err): completion(.failure(err))
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

    private struct ResolveSurveyLinkResponse: Decodable {
        let surveyId: String
        let name: String?
    }

    private struct SurveyFlowEnvelope: Decodable {
        let flow: SurveyFlow
    }

    /// Fetch the full flow definition for `surveyId`. Used by the native
    /// renderer to drive question-by-question presentation.
    func getSurveyFlow(
        surveyId: String,
        language: String?,
        completion: @escaping (Result<SurveyFlow, APIError>) -> Void
    ) {
        var query: [URLQueryItem] = []
        if let language, !language.isEmpty {
            query.append(URLQueryItem(name: "language", value: language))
        }
        get(
            path: SDKEndpoint.surveyFlow(surveyId),
            query: query,
            responseType: SurveyFlowEnvelope.self
        ) { result in
            switch result {
            case .success(let env): completion(.success(env.flow))
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    /// Resolve a share-link token to a concrete survey id. Server returns 404
    /// for expired or unknown tokens, surfaced as APIError.
    func resolveSurveyLink(
        token: String,
        anonymousId: String,
        externalId: String?,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let body = ResolveSurveyLinkRequest(
            token: token,
            anonymousId: anonymousId,
            externalId: externalId
        )
        postJSON(
            path: "/v1/sdk/surveys/resolve",
            body: body,
            responseType: ResolveSurveyLinkResponse.self
        ) { result in
            switch result {
            case .success(let res): completion(.success(res.surveyId))
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    // MARK: - Retry loop

    private func performWithRetry<Response: Decodable>(
        request: URLRequest,
        attempt: Int,
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
            envelope = try JSONDecoder.ritmus().decode(APIEnvelope<Response>.self, from: bytes)
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

/// Standard API envelope returned by every Ritmus API route.
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
