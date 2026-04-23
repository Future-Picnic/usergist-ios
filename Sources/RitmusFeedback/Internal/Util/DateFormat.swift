import Foundation

/// Shared ISO8601 formatter for timestamps on the wire.
///
/// Uses fractional seconds to match the TypeScript core (`Date#toISOString`).
enum DateFormat {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(from date: Date) -> String {
        iso8601.string(from: date)
    }

    static func date(from string: String) -> Date? {
        iso8601.date(from: string)
    }
}

extension JSONEncoder {
    /// Encoder configured for SDK wire format (ISO8601 fractional-sec dates).
    static func ritmus() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(DateFormat.string(from: date))
        }
        return e
    }
}

extension JSONDecoder {
    /// Decoder configured for SDK wire format.
    static func ritmus() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = DateFormat.date(from: s) {
                return d
            }
            // Fallback: ISO8601 without fractional seconds.
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }
}
