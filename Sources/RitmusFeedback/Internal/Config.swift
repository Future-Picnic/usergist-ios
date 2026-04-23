import Foundation

/// Immutable configuration snapshot passed to internal components.
///
/// Created from the arguments to `Ritmus.initialize`. Everything the SDK
/// needs at runtime (API URL, timings, limits) comes from here — no
/// hidden singletons reading back into this.
struct RitmusConfig: Equatable {
    let writeKey: String
    let environment: Environment
    let apiURL: URL
    let debug: Bool
    let flushInterval: TimeInterval
    let flushBatchSize: Int
    let maxQueueSize: Int
    let maxQueueBytes: Int
    let triggerSyncInterval: TimeInterval
    let sdkVersion: String

    static let currentSDKVersion = "1.0.0"
    static let defaultMaxQueueBytes = 1_000_000 // 1 MB cap

    init(
        writeKey: String,
        environment: Environment,
        apiURL: URL?,
        debug: Bool,
        flushInterval: TimeInterval,
        flushBatchSize: Int,
        maxQueueSize: Int,
        triggerSyncInterval: TimeInterval,
        sdkVersion: String = RitmusConfig.currentSDKVersion,
        maxQueueBytes: Int = RitmusConfig.defaultMaxQueueBytes
    ) {
        self.writeKey = writeKey
        self.environment = environment
        self.apiURL = apiURL ?? environment.defaultAPIURL
        self.debug = debug
        self.flushInterval = max(1, flushInterval)
        self.flushBatchSize = max(1, flushBatchSize)
        self.maxQueueSize = max(1, maxQueueSize)
        self.maxQueueBytes = max(10_000, maxQueueBytes)
        self.triggerSyncInterval = max(30, triggerSyncInterval)
        self.sdkVersion = sdkVersion
    }

    /// Hex SHA-256 prefix of the write key, used for on-disk namespacing.
    var writeKeyHash: String {
        Hashing.shortSha256(writeKey)
    }
}
