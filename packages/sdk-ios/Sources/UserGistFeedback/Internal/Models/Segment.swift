import Foundation

/// Scalar value in segment rules.
enum SegmentScalar: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([SegmentScalar])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([SegmentScalar].self) {
            self = .list(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad scalar")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .list(let v): try c.encode(v)
        }
    }
}

/// Subset of the server DSL that the SDK evaluates client-side for instant
/// trigger firing. Server is authoritative — mismatches reconcile via the
/// response receipt.
struct SerializedSegmentRules: Codable, Equatable {
    struct UserPropertyRule: Codable, Equatable {
        let key: String
        let op: String
        let value: SegmentScalar
    }

    struct EventCountRule: Codable, Equatable {
        let eventName: String
        let op: String
        let count: Int
        let windowDays: Int
    }

    let userProperties: [UserPropertyRule]?
    let eventCounts: [EventCountRule]?
}
