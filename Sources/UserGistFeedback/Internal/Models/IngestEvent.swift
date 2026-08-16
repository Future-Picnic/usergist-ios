import Foundation

/// A single event enqueued for ingest.
///
/// Matches the `IngestEvent` shape in `@usergist/sdk-core`.
struct IngestEvent: Codable, Equatable {
    let name: String
    let timestamp: Date
    let anonymousId: String
    let externalId: String?
    let properties: [String: AnyCodable]?
    let sessionId: String?
    let sdkVersion: String
    let appVersion: String?
    let platform: String

    enum CodingKeys: String, CodingKey {
        case name
        case timestamp
        case anonymousId
        case externalId
        case properties
        case sessionId
        case sdkVersion
        case appVersion
        case platform
    }
}
