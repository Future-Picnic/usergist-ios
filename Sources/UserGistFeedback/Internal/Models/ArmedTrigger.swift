import Foundation

/// A locally-cached trigger that can fire a prompt without a network
/// round-trip when its event arrives.
struct ArmedTrigger: Codable, Equatable {
    let promptId: String
    let eventName: String
    let segmentRules: SerializedSegmentRules?
    let frequency: FrequencyCaps
    let prompt: ClientPrompt
}

/// Envelope returned by `GET /v1/sdk/armed-triggers`.
struct ArmedTriggersResponse: Codable, Equatable {
    let triggers: [ArmedTrigger]
    let serverTime: String
    let nextSyncMs: Int
}
