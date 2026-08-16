import Foundation

/// Maintains a live, in-memory `UserState` used by the client-side segment
/// evaluator. Updated on every `identify` and `track` call.
///
/// Only a subset of the server DSL is evaluated on-device — specifically
/// the serialized form shipped via armed triggers — so we only need:
/// `properties`, `eventCounts[eventName][windowDays]`, and `lastEventAt`.
final class UserStateTracker {
    private let queue: DispatchQueue
    private var state: UserState = .empty
    /// Ring of event timestamps per event name, newest last.
    private var timestampsByEvent: [String: [Date]] = [:]
    /// Window sizes seen in armed triggers — recomputed from rules cache.
    private var knownWindows: Set<Int> = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Thread-safe snapshot used by `TriggerMatcher`.
    func snapshot() -> UserState {
        queue.sync { state }
    }

    func setProperties(_ properties: [String: Any]?) {
        queue.sync {
            guard let properties else { return }
            var next = state.properties
            for (k, v) in properties {
                if let s = Self.scalar(from: v) {
                    next[k] = s
                } else {
                    next.removeValue(forKey: k)
                }
            }
            state = UserState(
                properties: next,
                eventCounts: state.eventCounts,
                lastEventAt: state.lastEventAt
            )
        }
    }

    /// Record that an event happened. Updates `lastEventAt` and recomputes
    /// the windowed counters for all known window sizes.
    func recordEvent(name: String, at date: Date) {
        queue.sync {
            var ring = timestampsByEvent[name] ?? []
            ring.append(date)
            // Keep only last 365 days to bound memory.
            let floor = date.addingTimeInterval(-365 * 86_400)
            ring = ring.filter { $0 >= floor }
            timestampsByEvent[name] = ring

            var lastEventAt = state.lastEventAt
            lastEventAt[name] = date

            var counts = state.eventCounts[name] ?? [:]
            for windowDays in knownWindows where windowDays > 0 {
                let cutoff = date.addingTimeInterval(-Double(windowDays) * 86_400)
                counts[windowDays] = ring.filter { $0 >= cutoff }.count
            }
            var eventCounts = state.eventCounts
            eventCounts[name] = counts

            state = UserState(
                properties: state.properties,
                eventCounts: eventCounts,
                lastEventAt: lastEventAt
            )
        }
    }

    /// Update the set of windowDays the tracker must maintain, derived from
    /// the current armed-triggers rules. Recomputes counters for each event.
    func setKnownWindows(_ windows: Set<Int>) {
        queue.sync {
            knownWindows = windows
            let now = Date()
            var newCounts: [String: [Int: Int]] = [:]
            for (name, ring) in timestampsByEvent {
                var bucket: [Int: Int] = [:]
                for windowDays in windows where windowDays > 0 {
                    let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
                    bucket[windowDays] = ring.filter { $0 >= cutoff }.count
                }
                newCounts[name] = bucket
            }
            state = UserState(
                properties: state.properties,
                eventCounts: newCounts,
                lastEventAt: state.lastEventAt
            )
        }
    }

    func reset() {
        queue.sync {
            state = .empty
            timestampsByEvent = [:]
        }
    }

    // MARK: - Helpers

    static func scalar(from value: Any) -> SegmentScalar? {
        if let v = value as? String { return .string(v) }
        if let v = value as? Bool { return .bool(v) }
        if let v = value as? Int { return .number(Double(v)) }
        if let v = value as? Double { return .number(v) }
        if let v = value as? NSNumber {
            if CFGetTypeID(v) == CFBooleanGetTypeID() { return .bool(v.boolValue) }
            return .number(v.doubleValue)
        }
        return nil
    }

    static func windows(from triggers: [ArmedTrigger]) -> Set<Int> {
        var out = Set<Int>()
        for trigger in triggers {
            guard let rules = trigger.segmentRules else { continue }
            for rule in rules.eventCounts ?? [] {
                out.insert(rule.windowDays)
            }
        }
        return out
    }
}
