import Foundation

// PORTED FROM: packages/sdk-react-native/src/UserGist.ts (requests methods,
//              lines 884–1149). Each method: fetch identity → optimistic
//              cache mutation → HTTP call → commit on success / rollback
//              on failure → emit event → fire handler.

extension Runtime {

    func listRequests(
        options: GetRequestsOptions,
        completion: @escaping (Result<GetRequestsResult, Error>) -> Void
    ) {
        guard consentStore.allowsTransport else {
            completion(.success(GetRequestsResult(items: [], nextCursor: nil)))
            return
        }
        let id = identityStore.current()
        apiClient.listRequests(
            anonymousId: id.anonymousId,
            externalId: id.externalId,
            options: options
        ) { [weak self] result in
            switch result {
            case .success(let page):
                // Hydrate the optimistic cache so any subsequent vote/follow
                // taps render instantly while the network round-trip pends.
                self?.requestsCache.upsertList(page.items.map { s in
                    FeatureRequest(
                        id: s.id,
                        appId: "",
                        title: s.title,
                        description: s.description,
                        status: s.status,
                        devResponse: nil,
                        upvoteCount: s.upvoteCount,
                        followerCount: s.followerCount,
                        createdAt: s.createdAt,
                        updatedAt: s.createdAt,
                        statusChangedAt: s.statusChangedAt,
                        lastRespondedAt: nil,
                        viewerHasUpvoted: s.viewerHasUpvoted,
                        viewerIsFollowing: s.viewerIsFollowing,
                        viewerIsSubmitter: false
                    )
                })
                completion(.success(page))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func getRequest(
        requestId: String,
        completion: @escaping (Result<FeatureRequest, Error>) -> Void
    ) {
        let id = identityStore.current()
        apiClient.getRequest(
            requestId: requestId,
            anonymousId: id.anonymousId,
            externalId: id.externalId
        ) { [weak self] result in
            if case .success(let req) = result { self?.requestsCache.upsert(req) }
            completion(result.mapError { $0 as Error })
        }
    }

    func submitRequest(
        title: String,
        description: String,
        completion: @escaping (Result<FeatureRequest, Error>) -> Void
    ) {
        let id = identityStore.current()
        apiClient.submitRequest(
            anonymousId: id.anonymousId,
            externalId: id.externalId,
            title: title,
            description: description
        ) { [weak self] result in
            switch result {
            case .success(let req):
                self?.requestsCache.upsert(req)
                DispatchQueue.main.async {
                    UserGist.shared.requestsHandlers.onSubmit?(req)
                }
                completion(.success(req))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func voteOnRequest(
        requestId: String,
        vote: Bool,
        completion: @escaping (Result<RequestVote, Error>) -> Void
    ) {
        let rollback = requestsCache.applyOptimisticVote(id: requestId, vote: vote)
        let id = identityStore.current()
        apiClient.voteOnRequest(
            requestId: requestId,
            anonymousId: id.anonymousId,
            externalId: id.externalId,
            vote: vote
        ) { [weak self] result in
            switch result {
            case .success(let outcome):
                self?.requestsCache.commitVote(id: requestId, result: outcome)
                DispatchQueue.main.async {
                    UserGist.shared.requestsHandlers.onVote?(outcome)
                }
                completion(.success(outcome))
            case .failure(let err):
                rollback()
                completion(.failure(err))
            }
        }
    }

    func followRequest(
        requestId: String,
        follow: Bool,
        completion: @escaping (Result<RequestFollow, Error>) -> Void
    ) {
        let rollback = requestsCache.applyOptimisticFollow(id: requestId, follow: follow)
        let id = identityStore.current()
        apiClient.followRequest(
            requestId: requestId,
            anonymousId: id.anonymousId,
            externalId: id.externalId,
            follow: follow
        ) { [weak self] result in
            switch result {
            case .success(let outcome):
                self?.requestsCache.commitFollow(id: requestId, result: outcome)
                DispatchQueue.main.async {
                    UserGist.shared.requestsHandlers.onFollow?(outcome)
                }
                completion(.success(outcome))
            case .failure(let err):
                rollback()
                completion(.failure(err))
            }
        }
    }

    func getComments(
        requestId: String,
        completion: @escaping (Result<[RequestComment], Error>) -> Void
    ) {
        let id = identityStore.current()
        apiClient.getComments(
            requestId: requestId,
            anonymousId: id.anonymousId,
            externalId: id.externalId
        ) { result in
            completion(result.mapError { $0 as Error })
        }
    }

    func postComment(
        requestId: String,
        body: String,
        completion: @escaping (Result<RequestComment, Error>) -> Void
    ) {
        let id = identityStore.current()
        apiClient.postComment(
            requestId: requestId,
            anonymousId: id.anonymousId,
            externalId: id.externalId,
            body: body
        ) { result in
            completion(result.mapError { $0 as Error })
        }
    }

    func editComment(
        requestId: String,
        commentId: String,
        body: String,
        completion: @escaping (Result<RequestComment, Error>) -> Void
    ) {
        let id = identityStore.current()
        apiClient.editComment(
            requestId: requestId,
            commentId: commentId,
            anonymousId: id.anonymousId,
            body: body
        ) { result in
            completion(result.mapError { $0 as Error })
        }
    }

    func deleteComment(
        requestId: String,
        commentId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let id = identityStore.current()
        apiClient.deleteComment(
            requestId: requestId,
            commentId: commentId,
            anonymousId: id.anonymousId
        ) { result in
            completion(result.mapError { $0 as Error })
        }
    }

    func getRequestBranding(
        completion: @escaping (Result<RequestBranding, Error>) -> Void
    ) {
        apiClient.getRequestBranding { result in
            completion(result.mapError { $0 as Error })
        }
    }
}
