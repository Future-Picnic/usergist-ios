import Foundation

/// Persistent user identity store.
///
/// - `anonymousId` is generated on first run and survives `reset()`.
///   Wait — actually `reset()` MUST regenerate it (dev-prd requirement).
/// - `externalId` is set via `identify(userId:)` and cleared on `reset()`.
final class IdentityStore {
    struct Snapshot: Codable, Equatable {
        var anonymousId: String
        var externalId: String?
    }

    private let storage: Storage
    private let logger: RitmusLogger
    private let queue: DispatchQueue
    private var snapshot: Snapshot

    /// Synchronous init reads (or creates) the identity file.
    init(storage: Storage, logger: RitmusLogger, queue: DispatchQueue) {
        self.storage = storage
        self.logger = logger
        self.queue = queue
        if let existing = (try? storage.readJSON(Snapshot.self, at: storage.identityFile)) ?? nil {
            self.snapshot = existing
        } else {
            self.snapshot = Snapshot(anonymousId: UUID().uuidString, externalId: nil)
            do {
                try storage.writeJSON(self.snapshot, to: storage.identityFile)
            } catch {
                logger.error("failed to persist initial identity", error: error)
            }
        }
    }

    /// Thread-safe read.
    func current() -> Snapshot {
        queue.sync { snapshot }
    }

    var anonymousId: String {
        queue.sync { snapshot.anonymousId }
    }

    func setExternalId(_ externalId: String?) {
        queue.sync {
            guard snapshot.externalId != externalId else { return }
            snapshot.externalId = externalId
            persistLocked()
        }
    }

    /// Regenerates the anonymous ID and clears the external ID.
    /// Used by `reset()` on user logout.
    func resetAll() {
        queue.sync {
            snapshot = Snapshot(anonymousId: UUID().uuidString, externalId: nil)
            persistLocked()
        }
    }

    private func persistLocked() {
        do {
            try storage.writeJSON(snapshot, to: storage.identityFile)
        } catch {
            logger.error("failed to persist identity", error: error)
        }
    }
}
