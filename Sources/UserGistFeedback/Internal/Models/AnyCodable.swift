import Foundation

/// A type-erased `Codable` value used for heterogeneous property bags.
///
/// The SDK serializes user-supplied property dictionaries (`[String: Any]`)
/// into JSON. `AnyCodable` normalizes arbitrary scalar / array / dict
/// values and preserves them across encode/decode round-trips.
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any?) {
        self.value = value ?? NSNull()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported AnyCodable value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Int32:
            try container.encode(Int(v))
        case let v as Int64:
            try container.encode(v)
        case let v as Double:
            if v.isFinite {
                try container.encode(v)
            } else {
                try container.encodeNil()
            }
        case let v as Float:
            if v.isFinite {
                try container.encode(Double(v))
            } else {
                try container.encodeNil()
            }
        case let v as String:
            try container.encode(v)
        case let v as [Any?]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any?]:
            try container.encode(v.mapValues { AnyCodable($0) })
        case let v as NSNumber:
            // NSNumber carries both Bool and numeric types; distinguish by objCType.
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                try container.encode(v.boolValue)
            } else {
                try container.encode(v.doubleValue)
            }
        default:
            try container.encode(String(describing: value))
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        case let (l as [Any], r as [Any]):
            return NSArray(array: l).isEqual(to: r)
        case let (l as [String: Any], r as [String: Any]):
            return NSDictionary(dictionary: l).isEqual(to: r)
        default:
            return false
        }
    }
}

extension AnyCodable {
    /// Convenience for converting a loosely-typed property dictionary to
    /// the `Codable`-friendly wrapper.
    static func wrap(_ dict: [String: Any]?) -> [String: AnyCodable]? {
        guard let dict else { return nil }
        return dict.mapValues { AnyCodable($0) }
    }

    /// Event/identify property contract shared with the React Native SDK.
    /// The ingest API accepts bounded primitive scalars, not arbitrary JSON.
    static func wrapEventProperties(_ dict: [String: Any]?) -> [String: AnyCodable]? {
        guard let dict else { return nil }
        var result: [String: AnyCodable] = [:]
        for (key, value) in dict.prefix(100) {
            guard !key.isEmpty, key.count <= 120, !isPiiKey(key) else { continue }
            switch value {
            case is NSNull:
                result[key] = AnyCodable(nil)
            case let bool as Bool:
                result[key] = AnyCodable(bool)
            case let string as String:
                result[key] = AnyCodable(String(string.prefix(10_000)))
            case let int as Int:
                result[key] = AnyCodable(int)
            case let int as Int32:
                result[key] = AnyCodable(Int(int))
            case let int as Int64:
                result[key] = AnyCodable(int)
            case let float as Float where float.isFinite:
                result[key] = AnyCodable(Double(float))
            case let double as Double where double.isFinite:
                result[key] = AnyCodable(double)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    result[key] = AnyCodable(number.boolValue)
                } else if number.doubleValue.isFinite {
                    result[key] = AnyCodable(number.doubleValue)
                }
            default:
                continue
            }
        }
        return result
    }

    private static func isPiiKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return ["email", "phone", "ssn", "tax_id"].contains { term in
            lower == term || lower.hasSuffix(".\(term)") || lower.hasSuffix("_\(term)")
        }
    }
}
