import XCTest
@testable import UserGistFeedback

final class TransportRetryTests: XCTestCase {
    func test_defaultMaxAttempts() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 5)
    }

    func test_canRetryStopsAfterMax() {
        let policy = RetryPolicy.default
        XCTAssertTrue(policy.canRetry(currentAttempt: 0))
        XCTAssertTrue(policy.canRetry(currentAttempt: 3))
        XCTAssertFalse(policy.canRetry(currentAttempt: 4))
    }

    func test_backoffIncreasesMonotonically() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 60)
        var previousUpper: TimeInterval = 0
        for i in 0..<4 {
            // `Jitter.full` returns base + [0, base). Upper bound == 2 * base.
            let cap = min(60, 0.5 * pow(2.0, Double(i))) / 2.0
            let upper = 2 * cap
            XCTAssertGreaterThanOrEqual(upper, previousUpper)
            previousUpper = upper
            let d = policy.nextDelay(retryIndex: i)
            XCTAssertGreaterThanOrEqual(d, 0)
            XCTAssertLessThanOrEqual(d, upper + 0.001)
        }
    }

    func test_retryAfterOverridesBackoff() {
        let policy = RetryPolicy.default
        let d = policy.nextDelay(retryIndex: 0, retryAfter: 5)
        XCTAssertEqual(d, 5, accuracy: 0.001)
    }

    func test_retryAfterClampedToMax() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 10)
        let d = policy.nextDelay(retryIndex: 0, retryAfter: 999)
        XCTAssertEqual(d, 10, accuracy: 0.001)
    }

    func test_retryAfterParsingSeconds() {
        XCTAssertEqual(RetryAfterParser.parse("12"), 12)
        XCTAssertEqual(RetryAfterParser.parse(" 3 "), 3)
    }

    func test_retryAfterParsingInvalid() {
        XCTAssertNil(RetryAfterParser.parse(nil))
        XCTAssertNil(RetryAfterParser.parse(""))
        XCTAssertNil(RetryAfterParser.parse("not-a-date"))
    }

    func test_classificationBuckets() {
        if case .succeed = RetryDecision.classify(statusCode: 204, retryAfter: nil) {} else { XCTFail() }
        if case .retryable = RetryDecision.classify(statusCode: 429, retryAfter: 1) {} else { XCTFail() }
        if case .retryable = RetryDecision.classify(statusCode: 503, retryAfter: nil) {} else { XCTFail() }
        if case .permanent = RetryDecision.classify(statusCode: 400, retryAfter: nil) {} else { XCTFail() }
        if case .permanent = RetryDecision.classify(statusCode: 401, retryAfter: nil) {} else { XCTFail() }
    }
}
