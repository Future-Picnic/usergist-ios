import Foundation

/// Sliding-window frequency cap tracker.
///
/// Persists per-prompt and global show timestamps. `canShow` returns
/// `false` if any relevant cap would be violated by showing now.
final class FrequencyCapStore {
    struct Snapshot: Codable, Equatable {
        /// `promptShows[promptId]` = sorted list of shown-at dates.
        var promptShows: [String: [Date]]
        /// Global (cross-prompt) show dates for per-user caps.
        var globalShows: [Date]

        static let empty = Snapshot(promptShows: [:], globalShows: [])
    }

    private let storage: Storage
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private var snapshot: Snapshot
    private let clock: () -> Date

    init(
        storage: Storage,
        logger: UserGistLogger,
        queue: DispatchQueue,
        clock: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.logger = logger
        self.queue = queue
        self.clock = clock
        if let existing = (try? storage.readJSON(Snapshot.self, at: storage.frequencyCapsFile)) ?? nil {
            self.snapshot = existing
        } else {
            self.snapshot = .empty
        }
    }

    /// Checks both per-prompt and global per-user caps.
    func canShow(promptId: String, caps: FrequencyCaps) -> Bool {
        queue.sync {
            let now = clock()
            if let perPromptDays = caps.perPromptDays, perPromptDays > 0 {
                let cutoff = now.addingTimeInterval(-Double(perPromptDays) * 86_400)
                let shows = (snapshot.promptShows[promptId] ?? []).filter { $0 >= cutoff }
                if !shows.isEmpty { return false }
            }
            if let perUserDays = caps.perUserDays, perUserDays > 0 {
                let cutoff = now.addingTimeInterval(-Double(perUserDays) * 86_400)
                let shows = snapshot.globalShows.filter { $0 >= cutoff }
                if !shows.isEmpty { return false }
            }
            return true
        }
    }

    /// Record that a prompt was shown. Persists to disk.
    func recordShown(promptId: String) {
        queue.sync {
            let now = clock()
            var newPromptShows = snapshot.promptShows
            var bucket = newPromptShows[promptId] ?? []
            bucket.append(now)
            newPromptShows[promptId] = bucket

            var newGlobal = snapshot.globalShows
            newGlobal.append(now)

            // Trim history older than 90 days to keep files small.
            let floor = now.addingTimeInterval(-90 * 86_400)
            newPromptShows = newPromptShows.mapValues { $0.filter { $0 >= floor } }
            newGlobal = newGlobal.filter { $0 >= floor }

            snapshot = Snapshot(promptShows: newPromptShows, globalShows: newGlobal)
            persistLocked()
        }
    }

    func reset() {
        queue.sync {
            snapshot = .empty
            persistLocked()
        }
    }

    private func persistLocked() {
        do {
            try storage.writeJSON(snapshot, to: storage.frequencyCapsFile)
        } catch {
            logger.error("frequency cap persist failed", error: error)
        }
    }
}
