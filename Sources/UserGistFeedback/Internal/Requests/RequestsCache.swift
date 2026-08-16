import Foundation

// PORTED FROM: packages/sdk-react-native/src/internal/requests.ts
//
// In-memory snapshot of recently-touched feature requests. Lets the SDK
// render upvote / follow counts immediately on tap, then reconcile against
// the server response. Spec §9 invariants enforced here, matching RN:
//   - Upvoting auto-creates a follow (followerCount += 1 only if the
//     user wasn't already following).
//   - Un-upvoting does NOT remove the follow.
//
// Each optimistic mutation captures the pre-mutation snapshot and returns
// a rollback closure. Concurrent taps each get their own captured snapshot,
// so rollback always restores the value seen at call time — never "the
// current value" at the moment of rollback.

final class RequestsCache {
    typealias Listener = (String, FeatureRequest) -> Void
    typealias Rollback = () -> Void

    private var store: [String: FeatureRequest] = [:]
    private var listeners: [UUID: Listener] = [:]
    private let lock = NSRecursiveLock()

    func upsert(_ req: FeatureRequest) {
        lock.lock(); defer { lock.unlock() }
        store[req.id] = req
        emit(id: req.id, req: req)
    }

    func upsertList(_ list: [FeatureRequest]) {
        lock.lock(); defer { lock.unlock() }
        for r in list { store[r.id] = r }
    }

    func get(_ id: String) -> FeatureRequest? {
        lock.lock(); defer { lock.unlock() }
        return store[id]
    }

    /// Optimistically apply an upvote toggle. Returns a closure that
    /// restores the captured pre-call snapshot. No-op if `id` is unknown.
    func applyOptimisticVote(id: String, vote: Bool) -> Rollback {
        lock.lock(); defer { lock.unlock() }
        guard let before = store[id] else { return {} }
        let upvoteDelta: Int = {
            if vote && !before.viewerHasUpvoted { return 1 }
            if !vote && before.viewerHasUpvoted { return -1 }
            return 0
        }()
        // Auto-follow: upvoting bumps follower count if user wasn't following.
        let followDelta: Int = (vote && !before.viewerIsFollowing) ? 1 : 0
        let next = before.copy(
            upvoteCount: max(0, before.upvoteCount + upvoteDelta),
            followerCount: max(0, before.followerCount + followDelta),
            viewerHasUpvoted: vote,
            viewerIsFollowing: vote ? true : before.viewerIsFollowing
        )
        store[id] = next
        emit(id: id, req: next)
        return { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.store[id] = before
            self.emit(id: id, req: before)
        }
    }

    /// Optimistically apply a follow toggle. Returns a closure that
    /// restores the captured pre-call snapshot. No-op if `id` is unknown.
    func applyOptimisticFollow(id: String, follow: Bool) -> Rollback {
        lock.lock(); defer { lock.unlock() }
        guard let before = store[id] else { return {} }
        let delta: Int = {
            if follow && !before.viewerIsFollowing { return 1 }
            if !follow && before.viewerIsFollowing { return -1 }
            return 0
        }()
        let next = before.copy(
            followerCount: max(0, before.followerCount + delta),
            viewerIsFollowing: follow
        )
        store[id] = next
        emit(id: id, req: next)
        return { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.store[id] = before
            self.emit(id: id, req: before)
        }
    }

    func commitVote(id: String, result: RequestVote) {
        lock.lock(); defer { lock.unlock() }
        guard let before = store[id] else { return }
        let next = before.copy(
            upvoteCount: result.upvoteCount,
            followerCount: result.followerCount,
            viewerHasUpvoted: result.upvoted,
            viewerIsFollowing: result.followed
        )
        store[id] = next
        emit(id: id, req: next)
    }

    func commitFollow(id: String, result: RequestFollow) {
        lock.lock(); defer { lock.unlock() }
        guard let before = store[id] else { return }
        let next = before.copy(
            followerCount: result.followerCount,
            viewerIsFollowing: result.following
        )
        store[id] = next
        emit(id: id, req: next)
    }

    /// Returns an unsubscribe closure.
    @discardableResult
    func subscribe(_ cb: @escaping Listener) -> () -> Void {
        lock.lock(); defer { lock.unlock() }
        let token = UUID()
        listeners[token] = cb
        return { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.listeners.removeValue(forKey: token)
        }
    }

    private func emit(id: String, req: FeatureRequest) {
        // Snapshot listeners so a listener that unsubscribes during its own
        // callback does not mutate the iterator.
        let snapshot = Array(listeners.values)
        for cb in snapshot { cb(id, req) }
    }
}

private extension FeatureRequest {
    /// Returns a copy with the given fields overridden. Mirrors the
    /// `{ ...before, ... }` spread used in the RN reference.
    func copy(
        upvoteCount: Int? = nil,
        followerCount: Int? = nil,
        viewerHasUpvoted: Bool? = nil,
        viewerIsFollowing: Bool? = nil
    ) -> FeatureRequest {
        FeatureRequest(
            id: id,
            appId: appId,
            title: title,
            description: description,
            status: status,
            devResponse: devResponse,
            upvoteCount: upvoteCount ?? self.upvoteCount,
            followerCount: followerCount ?? self.followerCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            statusChangedAt: statusChangedAt,
            lastRespondedAt: lastRespondedAt,
            viewerHasUpvoted: viewerHasUpvoted ?? self.viewerHasUpvoted,
            viewerIsFollowing: viewerIsFollowing ?? self.viewerIsFollowing,
            viewerIsSubmitter: viewerIsSubmitter
        )
    }
}
