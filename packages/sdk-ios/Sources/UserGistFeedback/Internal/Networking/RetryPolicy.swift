import Foundation

/// Encodes the SDK's retry discipline.
///
/// - At most `maxAttempts` attempts (default 5 including the first try).
/// - Exponential backoff with full jitter (AWS "full jitter" strategy).
/// - Honors `Retry-After` on 429 / 503 responses.
struct RetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    static let `default` = RetryPolicy(
        maxAttempts: 5,
        baseDelay: 0.5,
        maxDelay: 30
    )

    /// Computes the next delay for a given zero-based retry index.
    ///
    /// `retryIndex == 0` is the delay *before* the second attempt.
    /// If `retryAfter` is supplied, it takes precedence (clamped to maxDelay).
    func nextDelay(retryIndex: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter {
            return min(max(0, retryAfter), maxDelay)
        }
        let exp = pow(2.0, Double(retryIndex))
        let cap = min(maxDelay, baseDelay * exp)
        return Jitter.full(base: cap / 2.0)
    }

    /// Returns `true` if another attempt is allowed.
    func canRetry(currentAttempt: Int) -> Bool {
        currentAttempt + 1 < maxAttempts
    }
}

/// HTTP classification helpers.
enum RetryDecision {
    case succeed
    case retryable(retryAfter: TimeInterval?)
    case permanent

    static func classify(statusCode: Int, retryAfter: TimeInterval?) -> RetryDecision {
        switch statusCode {
        case 200..<300:
            return .succeed
        case 408, 425, 429:
            return .retryable(retryAfter: retryAfter)
        case 500..<600:
            return .retryable(retryAfter: retryAfter)
        default:
            return .permanent
        }
    }
}

/// Parses a `Retry-After` header (seconds or HTTP-date).
enum RetryAfterParser {
    static func parse(_ value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}
