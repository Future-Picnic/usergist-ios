import Foundation

enum EventPurpose: String, Codable {
    case analytics
    case feedback
}

/// A single event enqueued for ingest.
///
/// Matches the `IngestEvent` shape in `@usergist/sdk-core`.
struct IngestEvent: Codable, Equatable {
    let eventId: String
    let purpose: EventPurpose
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
        case eventId
        case purpose
        case timestamp
        case anonymousId
        case externalId
        case properties
        case sessionId
        case sdkVersion
        case appVersion
        case platform
    }

    init(
        name: String,
        timestamp: Date,
        anonymousId: String,
        externalId: String?,
        properties: [String: AnyCodable]?,
        sessionId: String?,
        sdkVersion: String,
        appVersion: String?,
        platform: String,
        eventId: String = UUID().uuidString,
        purpose: EventPurpose = .analytics
    ) {
        self.eventId = eventId
        self.purpose = purpose
        self.name = name
        self.timestamp = timestamp
        self.anonymousId = anonymousId
        self.externalId = externalId
        self.properties = properties
        self.sessionId = sessionId
        self.sdkVersion = sdkVersion
        self.appVersion = appVersion
        self.platform = platform
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try values.decodeIfPresent(String.self, forKey: .eventId) ?? UUID().uuidString
        purpose = try values.decodeIfPresent(EventPurpose.self, forKey: .purpose) ?? .analytics
        name = try values.decode(String.self, forKey: .name)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        anonymousId = try values.decode(String.self, forKey: .anonymousId)
        externalId = try values.decodeIfPresent(String.self, forKey: .externalId)
        properties = try values.decodeIfPresent([String: AnyCodable].self, forKey: .properties)
        sessionId = try values.decodeIfPresent(String.self, forKey: .sessionId)
        sdkVersion = try values.decode(String.self, forKey: .sdkVersion)
        appVersion = try values.decodeIfPresent(String.self, forKey: .appVersion)
        platform = try values.decode(String.self, forKey: .platform)
    }
}
