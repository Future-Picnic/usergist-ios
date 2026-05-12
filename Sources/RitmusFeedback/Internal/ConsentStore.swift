import Foundation

/// Persistent consent gate.
///
/// Acts as the single source of truth for whether the transport layer is
/// allowed to ship data. Writes to disk on every change so a crash
/// doesn't forget a revocation.
final class ConsentStore {
    private let storage: Storage
    private let secure: SecureStore?
    private let logger: RitmusLogger
    private let queue: DispatchQueue
    private var snapshot: Consent

    init(storage: Storage, secure: SecureStore?, logger: RitmusLogger, queue: DispatchQueue) {
        self.storage = storage
        self.secure = secure
        self.logger = logger
        self.queue = queue
        if let secure, let raw = secure.read(.consent),
           let existing = try? JSONDecoder.ritmus().decode(Consent.self, from: raw) {
            self.snapshot = existing
        } else if let legacy = (try? storage.readJSON(Consent.self, at: storage.consentFile)) ?? nil {
            // One-time migration: plaintext file → Keychain.
            self.snapshot = legacy
            if let secure, let data = try? JSONEncoder.ritmus().encode(legacy),
               secure.write(.consent, data) {
                try? storage.deleteFile(at: storage.consentFile)
            }
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

    var allowsPush: Bool {
        queue.sync { snapshot.allowsPush }
    }

    var allowsSurvey: Bool {
        queue.sync { snapshot.allowsSurvey }
    }

    /// Returns `true` if the new value differs from what was on disk.
    @discardableResult
    func update(_ consent: Consent) -> Bool {
        queue.sync {
            guard snapshot != consent else { return false }
            snapshot = consent
            if let secure, let data = try? JSONEncoder.ritmus().encode(snapshot),
               secure.write(.consent, data) {
                return true
            }
            // Fallback: plaintext file if Keychain unavailable.
            do {
                try storage.writeJSON(snapshot, to: storage.consentFile)
            } catch {
                logger.error("failed to persist consent", error: error)
            }
            return true
        }
    }
}
