import Foundation

/// Deterministic / pseudo-random jitter source used by retry policy and
/// queue backoff. Accepts an injected `RandomNumberGenerator` for tests.
enum Jitter {
    /// Returns the base delay plus `[0, base)` uniformly-distributed jitter.
    static func full(base: TimeInterval, using rng: inout any RandomNumberGenerator) -> TimeInterval {
        guard base > 0 else { return 0 }
        let r = Double.random(in: 0..<base, using: &rng)
        return base + r
    }

    static func full(base: TimeInterval) -> TimeInterval {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        return full(base: base, using: &rng)
    }
}
