import Foundation

/// In-memory cache of armed triggers, persisted on disk for cold-start hits.
final class RulesCache {
    private let storage: Storage
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private var triggersByEvent: [String: [ArmedTrigger]] = [:]
    private var allTriggers: [ArmedTrigger] = []

    init(storage: Storage, logger: UserGistLogger, queue: DispatchQueue) {
        self.storage = storage
        self.logger = logger
        self.queue = queue
        if let triggers = (try? storage.readJSON([ArmedTrigger].self, at: storage.armedTriggersFile)) ?? nil {
            self.allTriggers = triggers
            self.triggersByEvent = Dictionary(grouping: triggers, by: { $0.eventName })
        }
    }

    func triggers(for eventName: String) -> [ArmedTrigger] {
        queue.sync { triggersByEvent[eventName] ?? [] }
    }

    func snapshot() -> [ArmedTrigger] {
        queue.sync { allTriggers }
    }

    /// Replace the cached set with `triggers`. Also persists to disk.
    func replace(_ triggers: [ArmedTrigger]) {
        queue.sync {
            allTriggers = triggers
            triggersByEvent = Dictionary(grouping: triggers, by: { $0.eventName })
            do {
                try storage.writeJSON(triggers, to: storage.armedTriggersFile)
            } catch {
                logger.error("rules cache persist failed", error: error)
            }
        }
    }

    func clear() {
        replace([])
    }
}
