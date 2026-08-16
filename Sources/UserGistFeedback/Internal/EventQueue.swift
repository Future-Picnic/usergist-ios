import Foundation

// PORTED FROM: packages/sdk-react-native/src/internal/queue.ts
//
// Persisted shape mirrors the RN reference: `{ "version": N, "events": [...] }`.
// Bumped every time the on-disk shape changes; older snapshots are discarded
// rather than risk a deserialise mismatch. Events are best-effort, not durable.
private let QUEUE_SCHEMA_VERSION: Int = 1

private struct PersistedQueue: Codable {
    let version: Int
    let events: [IngestEvent]
}

/// Bounded, persistent, FIFO event queue.
///
/// - Persists to `events.log` as a versioned JSON envelope.
/// - On hydrate, falls back to the legacy NDJSON format for installs upgrading
///   from pre-versioning SDK builds; the next persist re-writes as envelope.
/// - Drops oldest on overflow of either `maxCount` or `maxBytes`.
/// - NOT internally locked — callers must serialize access via the SDK's
///   internal serial queue (passed at construction time).
final class EventQueue {
    private let storage: Storage
    private let logger: UserGistLogger
    private let maxCount: Int
    private let maxBytes: Int
    private var events: [IngestEvent]
    private let encoder = JSONEncoder.usergist()
    private let decoder = JSONDecoder.usergist()

    init(storage: Storage, logger: UserGistLogger, maxCount: Int, maxBytes: Int) {
        self.storage = storage
        self.logger = logger
        self.maxCount = maxCount
        self.maxBytes = maxBytes
        self.events = []
        self.hydrate()
    }

    var count: Int { events.count }

    var isEmpty: Bool { events.isEmpty }

    /// Returns a copy of currently queued events.
    func snapshot() -> [IngestEvent] {
        events
    }

    /// Enqueue one event. Drops oldest items to stay under limits.
    func enqueue(_ event: IngestEvent) {
        events.append(event)
        enforceLimits()
        persist()
    }

    /// Peek the head batch (up to `size` items) without removing them.
    func head(size: Int) -> [IngestEvent] {
        guard size > 0, !events.isEmpty else { return [] }
        let end = min(size, events.count)
        return Array(events.prefix(end))
    }

    /// Remove the first `count` items after a successful flush.
    func drop(_ count: Int) {
        guard count > 0 else { return }
        let n = min(count, events.count)
        events.removeFirst(n)
        persist()
    }

    /// Clear all queued events.
    func clear() {
        events.removeAll()
        persist()
    }

    // MARK: - Internals

    private func hydrate() {
        guard let data = (try? storage.readData(at: storage.eventsLog)) ?? nil,
              !data.isEmpty else {
            return
        }
        // Preferred path: versioned JSON envelope written by current SDK builds.
        if let wrapped = try? decoder.decode(PersistedQueue.self, from: data) {
            if wrapped.version == QUEUE_SCHEMA_VERSION {
                events = wrapped.events
            } else {
                logger.error("event queue hydrate: discarding unknown queue version \(wrapped.version)", error: nil)
                try? storage.deleteFile(at: storage.eventsLog)
                return
            }
        } else {
            // Legacy NDJSON written by pre-versioning SDK builds. Parse line by
            // line, then re-persist into the envelope shape on next write.
            events = parseLegacyNDJSON(data)
        }
        if events.count > maxCount {
            events.removeFirst(events.count - maxCount)
            persist()
        }
    }

    private func parseLegacyNDJSON(_ data: Data) -> [IngestEvent] {
        var loaded: [IngestEvent] = []
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard let newline = data.range(of: Data([0x0A]), in: cursor..<data.endIndex) else {
                let slice = data.subdata(in: cursor..<data.endIndex)
                if !slice.isEmpty, let ev = try? decoder.decode(IngestEvent.self, from: slice) {
                    loaded.append(ev)
                }
                break
            }
            let lineEnd = newline.lowerBound
            if lineEnd > cursor {
                let slice = data.subdata(in: cursor..<lineEnd)
                if !slice.isEmpty, let ev = try? decoder.decode(IngestEvent.self, from: slice) {
                    loaded.append(ev)
                }
            }
            cursor = newline.upperBound
        }
        return loaded
    }

    private func enforceLimits() {
        while events.count > maxCount {
            events.removeFirst()
        }
        // Byte cap: approximate by serializing periodically.
        if events.count > 0 {
            var bytes = approximateByteSize()
            while bytes > maxBytes, events.count > 1 {
                events.removeFirst()
                bytes = approximateByteSize()
            }
        }
    }

    private func approximateByteSize() -> Int {
        guard let data = try? encoder.encode(events) else { return 0 }
        return data.count
    }

    private func persist() {
        do {
            if events.isEmpty {
                try storage.deleteFile(at: storage.eventsLog)
                return
            }
            let wrapped = PersistedQueue(version: QUEUE_SCHEMA_VERSION, events: events)
            let data = try encoder.encode(wrapped)
            try storage.writeData(data, to: storage.eventsLog)
        } catch {
            logger.error("event queue persist failed", error: error)
        }
    }
}
