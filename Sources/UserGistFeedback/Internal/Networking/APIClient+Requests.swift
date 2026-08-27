import Foundation

// PORTED FROM: packages/sdk-react-native/src/UserGist.ts requests methods +
//              packages/sdk-core/src/contract/endpoints.ts (/v1/sdk/requests/*)
//
// API client methods for the Feature Requests pillar. Each maps directly
// to an endpoint described in the shared contract.

extension APIClient {

    private struct SubmitBody: Encodable {
        let idempotencyKey: String
        let anonymousId: String
        let externalId: String?
        let title: String
        let description: String
    }

    private struct VoteBody: Encodable {
        let anonymousId: String
        let externalId: String?
        let vote: Bool
    }

    private struct FollowBody: Encodable {
        let anonymousId: String
        let externalId: String?
        let follow: Bool
    }

    private struct PostCommentBody: Encodable {
        let idempotencyKey: String
        let anonymousId: String
        let externalId: String?
        let body: String
    }

    private struct CommentsEnvelope: Decodable {
        let items: [RequestComment]
    }

    func listRequests(
        anonymousId: String,
        externalId: String?,
        options: GetRequestsOptions,
        completion: @escaping (Result<GetRequestsResult, APIError>) -> Void
    ) {
        var q: [URLQueryItem] = [URLQueryItem(name: "anonymousId", value: anonymousId)]
        if let externalId, !externalId.isEmpty {
            q.append(URLQueryItem(name: "externalId", value: externalId))
        }
        if let sort = options.sort { q.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        if let statuses = options.statuses, !statuses.isEmpty {
            q.append(URLQueryItem(name: "statuses", value: statuses.map { $0.rawValue }.joined(separator: ",")))
        }
        if let mine = options.mine { q.append(URLQueryItem(name: "mine", value: mine.rawValue)) }
        if let qstr = options.q, !qstr.isEmpty { q.append(URLQueryItem(name: "q", value: qstr)) }
        if let cursor = options.cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit = options.limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }
        get(path: SDKEndpoint.requests, query: q, responseType: GetRequestsResult.self, completion: completion)
    }

    func getRequest(
        requestId: String,
        anonymousId: String,
        externalId: String?,
        completion: @escaping (Result<FeatureRequest, APIError>) -> Void
    ) {
        var q: [URLQueryItem] = [URLQueryItem(name: "anonymousId", value: anonymousId)]
        if let externalId, !externalId.isEmpty {
            q.append(URLQueryItem(name: "externalId", value: externalId))
        }
        get(path: SDKEndpoint.request(requestId), query: q, responseType: FeatureRequest.self, completion: completion)
    }

    func submitRequest(
        anonymousId: String,
        externalId: String?,
        title: String,
        description: String,
        completion: @escaping (Result<FeatureRequest, APIError>) -> Void
    ) {
        postJSON(
            path: SDKEndpoint.requests,
            body: SubmitBody(
                idempotencyKey: UUID().uuidString,
                anonymousId: anonymousId,
                externalId: externalId,
                title: title,
                description: description
            ),
            responseType: FeatureRequest.self,
            completion: completion
        )
    }

    func voteOnRequest(
        requestId: String,
        anonymousId: String,
        externalId: String?,
        vote: Bool,
        completion: @escaping (Result<RequestVote, APIError>) -> Void
    ) {
        postJSON(
            path: SDKEndpoint.requestVote(requestId),
            body: VoteBody(anonymousId: anonymousId, externalId: externalId, vote: vote),
            responseType: RequestVote.self,
            completion: completion
        )
    }

    func followRequest(
        requestId: String,
        anonymousId: String,
        externalId: String?,
        follow: Bool,
        completion: @escaping (Result<RequestFollow, APIError>) -> Void
    ) {
        postJSON(
            path: SDKEndpoint.requestFollow(requestId),
            body: FollowBody(anonymousId: anonymousId, externalId: externalId, follow: follow),
            responseType: RequestFollow.self,
            completion: completion
        )
    }

    func getComments(
        requestId: String,
        anonymousId: String,
        externalId: String?,
        completion: @escaping (Result<[RequestComment], APIError>) -> Void
    ) {
        var q: [URLQueryItem] = [URLQueryItem(name: "anonymousId", value: anonymousId)]
        if let externalId, !externalId.isEmpty {
            q.append(URLQueryItem(name: "externalId", value: externalId))
        }
        get(
            path: SDKEndpoint.requestComments(requestId),
            query: q,
            responseType: CommentsEnvelope.self
        ) { result in
            switch result {
            case .success(let env): completion(.success(env.items))
            case .failure(let err): completion(.failure(err))
            }
        }
    }

    func postComment(
        requestId: String,
        anonymousId: String,
        externalId: String?,
        body: String,
        completion: @escaping (Result<RequestComment, APIError>) -> Void
    ) {
        postJSON(
            path: SDKEndpoint.requestComments(requestId),
            body: PostCommentBody(
                idempotencyKey: UUID().uuidString,
                anonymousId: anonymousId,
                externalId: externalId,
                body: body
            ),
            responseType: RequestComment.self,
            completion: completion
        )
    }

    private struct EditCommentBody: Encodable {
        let anonymousId: String
        let body: String
    }

    func editComment(
        requestId: String,
        commentId: String,
        anonymousId: String,
        body: String,
        completion: @escaping (Result<RequestComment, APIError>) -> Void
    ) {
        patchJSON(
            path: SDKEndpoint.requestComment(requestId, commentId),
            body: EditCommentBody(anonymousId: anonymousId, body: body),
            responseType: RequestComment.self,
            completion: completion
        )
    }

    func deleteComment(
        requestId: String,
        commentId: String,
        anonymousId: String,
        completion: @escaping (Result<Void, APIError>) -> Void
    ) {
        deleteVoid(
            path: SDKEndpoint.requestComment(requestId, commentId),
            query: [URLQueryItem(name: "anonymousId", value: anonymousId)],
            completion: completion
        )
    }

    func getRequestBranding(
        completion: @escaping (Result<RequestBranding, APIError>) -> Void
    ) {
        get(
            path: SDKEndpoint.requestBranding,
            responseType: RequestBranding.self,
            completion: completion
        )
    }
}
