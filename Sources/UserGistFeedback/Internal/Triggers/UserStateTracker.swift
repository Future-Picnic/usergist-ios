import Foundation

/// Maintains a live, in-memory `UserState` used by the client-side segment
/// evaluator. Updated on every `identify` and `track` call.
///
/// Only a subset of the server DSL is evaluated on-device — specifically
/// the serialized form shipped via armed triggers — so we only need:
/// `properties`, `eventCounts[eventName][windowDays]`, and `lastEventAt`.
final class UserStateTracker {
    private struct Persisted: Codable {
        let version: Int
        let history: [String: [Date]]
    }

    private let queue: DispatchQueue
    private let storage: Storage
    private let logger: UserGistLogger
    private var state: UserState = .empty
    /// Ring of event timestamps per event name, newest last.
    private var timestampsByEvent: [String: [Date]] = [:]
    /// Window sizes seen in armed triggers — recomputed from rules cache.
    private var knownWindows: Set<Int> = []

    init(queue: DispatchQueue, storage: Storage, logger: UserGistLogger) {
        self.queue = queue
        self.storage = storage
        self.logger = logger
        if let persisted = (try? storage.readJSON(
            Persisted.self,
            at: storage.userStateFile
        )) ?? nil {
            self.timestampsByEvent = persisted.history.mapValues {
                Array($0.suffix(Self.historyCapPerEvent))
            }
        }
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

    func setPersistedProperties(_ properties: [String: SegmentScalar]?) {
        queue.sync {
            state = UserState(
                properties: properties ?? [:],
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
            if ring.count > Self.historyCapPerEvent {
                ring = Array(ring.suffix(Self.historyCapPerEvent))
            }
            timestampsByEvent[name] = ring
            persistLocked()

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
            var newLastEventAt: [String: Date] = [:]
            for (name, ring) in timestampsByEvent {
                if let last = ring.last { newLastEventAt[name] = last }
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
                lastEventAt: newLastEventAt
            )
        }
    }

    func reset() {
        queue.sync {
            state = .empty
            timestampsByEvent = [:]
            try? storage.deleteFile(at: storage.userStateFile)
        }
    }

    private func persistLocked() {
        do {
            try storage.writeJSON(
                Persisted(version: 1, history: timestampsByEvent),
                to: storage.userStateFile
            )
        } catch {
            logger.error("user-state persist failed", error: error)
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

    static func windows(from surveys: [ArmedSurvey]) -> Set<Int> {
        var out = Set<Int>()
        for survey in surveys {
            guard let rules = survey.segmentRules else { continue }
            for rule in rules.eventCounts ?? [] {
                out.insert(rule.windowDays)
            }
        }
        return out
    }

    private static let historyCapPerEvent = 200
}
