import Foundation

/// Per-user state the segment evaluator queries.
struct UserState: Equatable {
    var properties: [String: SegmentScalar]
    /// `eventCounts[name][windowDays] = count`
    var eventCounts: [String: [Int: Int]]
    /// `lastEventAt[name] = Date of most recent`.
    var lastEventAt: [String: Date]

    static let empty = UserState(properties: [:], eventCounts: [:], lastEventAt: [:])
}

/// Pure-Swift port of the TypeScript `evaluateSerializedSegmentRules`.
///
/// The SDK only evaluates the lightweight serialized form — not the full
/// server DSL — since the server is authoritative.
enum SegmentEvaluator {
    static func evaluate(_ rules: SerializedSegmentRules?, user: UserState) -> Bool {
        guard let rules else { return true }
        if let userProperties = rules.userProperties {
            for rule in userProperties {
                if !evaluateUserProperty(rule: rule, user: user) { return false }
            }
        }
        if let eventCounts = rules.eventCounts {
            for rule in eventCounts {
                if !evaluateEventCount(rule: rule, user: user) { return false }
            }
        }
        return true
    }

    // MARK: - User property

    private static func evaluateUserProperty(
        rule: SerializedSegmentRules.UserPropertyRule,
        user: UserState
    ) -> Bool {
        let actual = user.properties[rule.key]
        switch rule.op {
        case "eq":
            return equal(actual, rule.value)
        case "neq":
            return !equal(actual, rule.value)
        case "in":
            guard case .list(let list) = rule.value, let actual else { return false }
            return list.contains(where: { equal(actual, $0) })
        case "gt":
            guard let a = actualNumber(actual), let b = scalarNumber(rule.value) else { return false }
            return a > b
        case "gte":
            guard let a = actualNumber(actual), let b = scalarNumber(rule.value) else { return false }
            return a >= b
        case "lt":
            guard let a = actualNumber(actual), let b = scalarNumber(rule.value) else { return false }
            return a < b
        case "lte":
            guard let a = actualNumber(actual), let b = scalarNumber(rule.value) else { return false }
            return a <= b
        default:
            return false
        }
    }

    private static func equal(_ lhs: SegmentScalar?, _ rhs: SegmentScalar) -> Bool {
        guard let lhs else { return false }
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        default: return false
        }
    }

    private static func actualNumber(_ v: SegmentScalar?) -> Double? {
        guard let v else { return nil }
        if case .number(let n) = v { return n }
        return nil
    }

    private static func scalarNumber(_ v: SegmentScalar) -> Double? {
        if case .number(let n) = v { return n }
        return nil
    }

    // MARK: - Event count

    private static func evaluateEventCount(
        rule: SerializedSegmentRules.EventCountRule,
        user: UserState
    ) -> Bool {
        let bucket = user.eventCounts[rule.eventName] ?? [:]
        let count = bucket[rule.windowDays] ?? 0
        switch rule.op {
        case "eq": return count == rule.count
        case "gte": return count >= rule.count
        case "lte": return count <= rule.count
        case "gt": return count > rule.count
        case "lt": return count < rule.count
        default: return false
        }
    }
}
