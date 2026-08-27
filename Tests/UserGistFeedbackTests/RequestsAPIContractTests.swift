import XCTest
@testable import UserGistFeedback

final class RequestsAPIContractTests: XCTestCase {
    func test_submitAndCommentIncludeRequiredIdempotencyKeys() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let callbackQueue = DispatchQueue(label: "requests-api-contract")
        let client = APIClient(
            baseURL: URL(string: "https://api.test")!,
            writeKey: "wk_test",
            sdkVersion: "0.1.0",
            logger: UserGistLogger(debug: false),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0),
            callbackQueue: callbackQueue,
            session: session
        )
        client.setSubjectToken("st_test")

        let submit = expectation(description: "submit")
        RequestsURLProtocol.responseBody = Self.envelope(Self.requestJSON)
        client.submitRequest(
            anonymousId: "anon-1",
            externalId: nil,
            title: "Title",
            description: "Description"
        ) { result in
            if case .failure(let error) = result { XCTFail("submit failed: \(error)") }
            submit.fulfill()
        }
        wait(for: [submit], timeout: 2)
        try Self.assertUUIDBody(path: "/v1/sdk/requests")

        let comment = expectation(description: "comment")
        RequestsURLProtocol.responseBody = Self.envelope(Self.commentJSON)
        client.postComment(
            requestId: "request-1",
            anonymousId: "anon-1",
            externalId: nil,
            body: "Comment"
        ) { result in
            if case .failure(let error) = result { XCTFail("comment failed: \(error)") }
            comment.fulfill()
        }
        wait(for: [comment], timeout: 2)
        try Self.assertUUIDBody(path: "/v1/sdk/requests/request-1/comments")
    }

    func test_commentDecodingToleratesRedactedAnonymousAuthor() throws {
        let data = Data(
            """
            {"id":"comment-1","requestId":"request-1","body":"Comment","authorExternalId":null,"viewerIsAuthor":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
            """.utf8
        )

        let comment = try JSONDecoder.usergist().decode(RequestComment.self, from: data)

        XCTAssertEqual(comment.authorAnonymousId, "")
        XCTAssertNil(comment.authorExternalId)
        XCTAssertFalse(comment.viewerIsAuthor)
    }

    override func tearDown() {
        RequestsURLProtocol.lastRequest = nil
        RequestsURLProtocol.responseBody = Data()
        super.tearDown()
    }

    private static func assertUUIDBody(path: String) throws {
        let request = try XCTUnwrap(RequestsURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, path)
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let key = try XCTUnwrap(body["idempotencyKey"] as? String)
        XCTAssertNotNil(UUID(uuidString: key))
    }

    private static func envelope(_ data: String) -> Data {
        Data("{\"success\":true,\"data\":\(data)}".utf8)
    }

    private static let requestJSON = """
    {"id":"request-1","appId":"app-1","title":"Title","description":"Description","status":"under_review","devResponse":null,"upvoteCount":0,"followerCount":0,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z","statusChangedAt":"2026-01-01T00:00:00Z","lastRespondedAt":null,"viewerHasUpvoted":false,"viewerIsFollowing":false,"viewerIsSubmitter":true}
    """

    private static let commentJSON = """
    {"id":"comment-1","requestId":"request-1","body":"Comment","authorAnonymousId":"anon-1","authorExternalId":null,"viewerIsAuthor":true,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """
}

private final class RequestsURLProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1024)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            captured.httpBody = body
        }
        Self.lastRequest = captured
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
