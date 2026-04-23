import Foundation

/// Bounded, persistent, FIFO event queue.
///
/// - Persists to `events.log` as newline-delimited JSON (`NDJSON`).
/// - Drops oldest on overflow of either `maxCount` or `maxBytes`.
/// - NOT internally locked — callers must serialize access via the SDK's
///   internal serial queue (passed at construction time).
final class EventQueue {
    private let storage: Storage
    private let logger: RitmusLogger
    private let maxCount: Int
    private let maxBytes: Int
    private var events: [IngestEvent]
    private let encoder = JSONEncoder.ritmus()
    private let decoder = JSONDecoder.ritmus()

    init(storage: Storage, logger: RitmusLogger, maxCount: Int, maxBytes: Int) {
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
        self.events = loaded
        if events.count > maxCount {
            events.removeFirst(events.count - maxCount)
            persist()
        }
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
            var buffer = Data()
            for event in events {
                let line = try encoder.encode(event)
                buffer.append(line)
                buffer.append(0x0A) // newline
            }
            try storage.writeData(buffer, to: storage.eventsLog)
        } catch {
            logger.error("event queue persist failed", error: error)
        }
    }
}
