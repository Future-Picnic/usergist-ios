import XCTest
@testable import RitmusFeedback

// Mirrors the behaviour spec from
// packages/sdk-react-native/src/internal/requests.ts so iOS / RN stay in
// lockstep: upvote auto-creates follow, un-upvote leaves follow alone,
// rollback restores the captured snapshot.
final class RequestsCacheTests: XCTestCase {

    private func makeRequest(
        id: String = "r1",
        upvoteCount: Int = 10,
        followerCount: Int = 4,
        viewerHasUpvoted: Bool = false,
        viewerIsFollowing: Bool = false
    ) -> FeatureRequest {
        FeatureRequest(
            id: id,
            appId: "app",
            title: "Title",
            description: "Desc",
            status: .underReview,
            devResponse: nil,
            upvoteCount: upvoteCount,
            followerCount: followerCount,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            statusChangedAt: "2026-01-01T00:00:00Z",
            lastRespondedAt: nil,
            viewerHasUpvoted: viewerHasUpvoted,
            viewerIsFollowing: viewerIsFollowing,
            viewerIsSubmitter: false
        )
    }

    func test_optimisticUpvote_bumpsCountsAndAutoFollows() {
        let cache = RequestsCache()
        cache.upsert(makeRequest())
        _ = cache.applyOptimisticVote(id: "r1", vote: true)
        let after = cache.get("r1")
        XCTAssertEqual(after?.upvoteCount, 11)
        XCTAssertEqual(after?.followerCount, 5)
        XCTAssertEqual(after?.viewerHasUpvoted, true)
        XCTAssertEqual(after?.viewerIsFollowing, true)
    }

    func test_unUpvote_doesNotRemoveFollow() {
        let cache = RequestsCache()
        cache.upsert(makeRequest(viewerHasUpvoted: true, viewerIsFollowing: true))
        _ = cache.applyOptimisticVote(id: "r1", vote: false)
        let after = cache.get("r1")
        XCTAssertEqual(after?.upvoteCount, 9)
        XCTAssertEqual(after?.followerCount, 4, "follower count must stay put on un-upvote")
        XCTAssertEqual(after?.viewerHasUpvoted, false)
        XCTAssertEqual(after?.viewerIsFollowing, true, "follow must NOT be removed by un-upvote")
    }

    func test_rollback_restoresCapturedSnapshot() {
        let cache = RequestsCache()
        cache.upsert(makeRequest())
        let rollback = cache.applyOptimisticVote(id: "r1", vote: true)
        rollback()
        let after = cache.get("r1")
        XCTAssertEqual(after?.upvoteCount, 10)
        XCTAssertEqual(after?.followerCount, 4)
        XCTAssertEqual(after?.viewerHasUpvoted, false)
        XCTAssertEqual(after?.viewerIsFollowing, false)
    }

    func test_concurrentTaps_eachRollbackUsesItsOwnSnapshot() {
        // Two optimistic mutations stack; rollbacks in reverse order should
        // each restore to the snapshot captured at their own call time.
        let cache = RequestsCache()
        cache.upsert(makeRequest())

        let rb1 = cache.applyOptimisticVote(id: "r1", vote: true)
        // After first tap: upvoteCount 11, follower 5, hasUpvoted true.
        let rb2 = cache.applyOptimisticFollow(id: "r1", follow: false)
        // After second tap: viewerIsFollowing false, followerCount 4.
        XCTAssertEqual(cache.get("r1")?.viewerIsFollowing, false)
        XCTAssertEqual(cache.get("r1")?.followerCount, 4)

        rb2()
        // Restores to the post-rb1 snapshot.
        XCTAssertEqual(cache.get("r1")?.viewerIsFollowing, true)
        XCTAssertEqual(cache.get("r1")?.followerCount, 5)

        rb1()
        // Restores to the original snapshot.
        let final = cache.get("r1")
        XCTAssertEqual(final?.upvoteCount, 10)
        XCTAssertEqual(final?.followerCount, 4)
        XCTAssertEqual(final?.viewerHasUpvoted, false)
        XCTAssertEqual(final?.viewerIsFollowing, false)
    }

    func test_commitVote_overwritesWithServerTruth() {
        let cache = RequestsCache()
        cache.upsert(makeRequest())
        _ = cache.applyOptimisticVote(id: "r1", vote: true)
        cache.commitVote(
            id: "r1",
            result: RequestVote(
                requestId: "r1",
                upvoted: true,
                followed: true,
                upvoteCount: 42,
                followerCount: 17
            )
        )
        let after = cache.get("r1")
        XCTAssertEqual(after?.upvoteCount, 42)
        XCTAssertEqual(after?.followerCount, 17)
    }

    func test_subscribe_receivesUpsertAndOptimisticEvents() {
        let cache = RequestsCache()
        var seen: [String] = []
        let unsubscribe = cache.subscribe { _, req in
            seen.append("\(req.upvoteCount)/\(req.followerCount)")
        }
        cache.upsert(makeRequest())
        _ = cache.applyOptimisticVote(id: "r1", vote: true)
        unsubscribe()
        _ = cache.applyOptimisticVote(id: "r1", vote: false)
        XCTAssertEqual(seen, ["10/4", "11/5"])
    }
}
