import Foundation

/// Persistent consent gate.
///
/// Acts as the single source of truth for whether the transport layer is
/// allowed to ship data. Writes to disk on every change so a crash
/// doesn't forget a revocation.
final class ConsentStore {
    private let storage: Storage
    private let logger: RitmusLogger
    private let queue: DispatchQueue
    private var snapshot: Consent

    init(storage: Storage, logger: RitmusLogger, queue: DispatchQueue) {
        self.storage = storage
        self.logger = logger
        self.queue = queue
        if let existing = (try? storage.readJSON(Consent.self, at: storage.consentFile)) ?? nil {
            self.snapshot = existing
        } else {
            self.snapshot = Consent()
        }
    }

    func current() -> Consent {
        queue.sync { snapshot }
    }

    var allowsTransport: Bool {
        queue.sync { snapshot.allowsTransport }
    }

    /// Returns `true` if the new value differs from what was on disk.
    @discardableResult
    func update(_ consent: Consent) -> Bool {
        queue.sync {
            guard snapshot != consent else { return false }
            snapshot = consent
            do {
                try storage.writeJSON(snapshot, to: storage.consentFile)
            } catch {
                logger.error("failed to persist consent", error: error)
            }
            return true
        }
    }
}
