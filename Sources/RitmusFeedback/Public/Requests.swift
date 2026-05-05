// Feature requests (5th pillar) — public API surface for sdk-ios.
//
// STATUS: API surface declared; HTTP wiring + UI presentation tracked in
// PARITY.md as the iOS-stub for this pillar. Mirrors the React Native
// reference 1:1 (method names adapted to Swift conventions).
//
// Internal client + UI screens land in a follow-up. The types here are
// intentionally `public` so host apps can compile against the surface
// today and the runtime fills in once the implementation lands.

import Foundation

public enum RequestStatus: String, Codable, Sendable, CaseIterable {
    case underReview = "under_review"
    case planned
    case inProgress = "in_progress"
    case shipped
    case declined
}

public enum RequestFollowSource: String, Codable, Sendable {
    case upvoteAuto = "upvote_auto"
    case manual
}

public enum RequestSort: String, Codable, Sendable {
    case top
    case newest
    case recentlyUpdated = "recently_updated"
}

public enum RequestPersonalFilter: String, Codable, Sendable {
    case submitted
    case upvoted
    case following
}

public struct FeatureRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let appId: String
    public let title: String
    public let description: String
    public let status: RequestStatus
    public let devResponse: String?
    public let upvoteCount: Int
    public let followerCount: Int
    public let createdAt: String
    public let updatedAt: String
    public let statusChangedAt: String
    public let lastRespondedAt: String?
    public let viewerHasUpvoted: Bool
    public let viewerIsFollowing: Bool
    public let viewerIsSubmitter: Bool
}

public struct RequestSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let status: RequestStatus
    public let upvoteCount: Int
    public let followerCount: Int
    public let createdAt: String
    public let statusChangedAt: String
    public let viewerHasUpvoted: Bool
    public let viewerIsFollowing: Bool
}

public struct RequestSearchResult: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: RequestStatus
    public let upvoteCount: Int
}

public struct RequestVote: Codable, Sendable, Equatable {
    public let requestId: String
    public let upvoted: Bool
    public let followed: Bool
    public let upvoteCount: Int
    public let followerCount: Int
}

public struct RequestFollow: Codable, Sendable, Equatable {
    public let requestId: String
    public let following: Bool
    public let followerCount: Int
    public let source: RequestFollowSource
}

public struct GetRequestsOptions: Sendable {
    public var sort: RequestSort?
    public var statuses: [RequestStatus]?
    public var mine: RequestPersonalFilter?
    public var q: String?
    public var cursor: String?
    public var limit: Int?

    public init(
        sort: RequestSort? = nil,
        statuses: [RequestStatus]? = nil,
        mine: RequestPersonalFilter? = nil,
        q: String? = nil,
        cursor: String? = nil,
        limit: Int? = nil
    ) {
        self.sort = sort
        self.statuses = statuses
        self.mine = mine
        self.q = q
        self.cursor = cursor
        self.limit = limit
    }
}

public struct GetRequestsResult: Codable, Sendable {
    public let items: [RequestSummary]
    public let nextCursor: String?
}

public struct RequestStatusChangedNotice: Codable, Sendable {
    public let requestId: String
    public let title: String
    public let oldStatus: RequestStatus
    public let newStatus: RequestStatus
    public let devResponseExcerpt: String?
}

public struct RequestsHandlers {
    public var onSubmit: ((FeatureRequest) -> Void)?
    public var onVote: ((RequestVote) -> Void)?
    public var onFollow: ((RequestFollow) -> Void)?
    public var onStatusChanged: ((RequestStatusChangedNotice) -> Void)?

    public init(
        onSubmit: ((FeatureRequest) -> Void)? = nil,
        onVote: ((RequestVote) -> Void)? = nil,
        onFollow: ((RequestFollow) -> Void)? = nil,
        onStatusChanged: ((RequestStatusChangedNotice) -> Void)? = nil
    ) {
        self.onSubmit = onSubmit
        self.onVote = onVote
        self.onFollow = onFollow
        self.onStatusChanged = onStatusChanged
    }
}

public enum RequestsError: Error {
    case validation(String)
    case notImplemented(String)
}

public extension Ritmus {
    /// Open the SDK-provided requests board UI.
    /// TODO[P5.req-ios]: present RequestsBoardViewController.
    func openRequestsBoard() {
        // Intentionally a no-op until the iOS UI lands.
    }

    /// Open the detail view for a specific request.
    /// TODO[P5.req-ios]: present RequestDetailViewController.
    func openRequestDetail(_ requestId: String) {
        _ = requestId
    }

    /// Submit a new request programmatically.
    /// TODO[P5.req-ios]: call POST /v1/sdk/requests via the runtime.
    func submitRequest(
        title: String,
        description: String,
        completion: @escaping (Result<FeatureRequest, Error>) -> Void
    ) {
        guard !title.isEmpty, title.count <= 120 else {
            completion(.failure(RequestsError.validation("title required, max 120 chars")))
            return
        }
        guard !description.isEmpty, description.count <= 1500 else {
            completion(.failure(RequestsError.validation("description required, max 1500 chars")))
            return
        }
        completion(.failure(RequestsError.notImplemented("iOS submitRequest awaiting P5.req-ios")))
    }

    /// Fetch a page of requests.
    func getRequests(
        options: GetRequestsOptions = GetRequestsOptions(),
        completion: @escaping (Result<GetRequestsResult, Error>) -> Void
    ) {
        _ = options
        completion(.success(GetRequestsResult(items: [], nextCursor: nil)))
    }

    /// Toggle upvote.
    func voteOnRequest(
        _ requestId: String,
        vote: Bool,
        completion: ((Result<RequestVote, Error>) -> Void)? = nil
    ) {
        completion?(.failure(RequestsError.notImplemented("iOS voteOnRequest awaiting P5.req-ios")))
        _ = (requestId, vote)
    }

    /// Toggle follow.
    func followRequest(
        _ requestId: String,
        follow: Bool,
        completion: ((Result<RequestFollow, Error>) -> Void)? = nil
    ) {
        completion?(.failure(RequestsError.notImplemented("iOS followRequest awaiting P5.req-ios")))
        _ = (requestId, follow)
    }

    /// Register host-app callbacks.
    func setRequestsHandlers(_ handlers: RequestsHandlers) {
        _ = handlers
        // TODO[P5.req-ios]: wire handlers through the runtime.
    }
}
