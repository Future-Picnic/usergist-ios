import Foundation

/// Persistent consent gate.
///
/// Acts as the single source of truth for whether the transport layer is
/// allowed to ship data. Writes to disk on every change so a crash
/// doesn't forget a revocation.
final class ConsentStore {
    private struct Record: Codable {
        let purposes: Consent
        let version: Int
        let updatedAt: Date
    }
    private let storage: Storage
    private let secure: SecureStore?
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private var snapshot: Consent
    private var revision: Int
    private var effectiveAt: Date

    init(storage: Storage, secure: SecureStore?, logger: UserGistLogger, queue: DispatchQueue) {
        self.storage = storage
        self.secure = secure
        self.logger = logger
        self.queue = queue
        if let secure, let raw = secure.read(.consent),
           let record = try? JSONDecoder.usergist().decode(Record.self, from: raw) {
            self.snapshot = record.purposes
            self.revision = record.version
            self.effectiveAt = record.updatedAt
        } else if let secure, let raw = secure.read(.consent),
                  let existing = try? JSONDecoder.usergist().decode(Consent.self, from: raw) {
            self.snapshot = existing
            self.revision = 0
            self.effectiveAt = .distantPast
        } else if let legacy = (try? storage.readJSON(Consent.self, at: storage.consentFile)) ?? nil {
            // One-time migration: plaintext file → Keychain.
            self.snapshot = legacy
            self.revision = 0
            self.effectiveAt = .distantPast
            let record = Record(purposes: legacy, version: 0, updatedAt: .distantPast)
            if let secure, let data = try? JSONEncoder.usergist().encode(record),
               secure.write(.consent, data) {
                try? storage.deleteFile(at: storage.consentFile)
            }
        } else {
            self.snapshot = Consent()
            self.revision = 0
            self.effectiveAt = .distantPast
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

    var version: Int { queue.sync { revision } }

    var updatedAt: Date { queue.sync { effectiveAt } }

    /// Persists every host consent decision as a new monotonic revision.
    @discardableResult
    func update(_ consent: Consent) -> Bool {
        queue.sync {
            let merged = Consent(
                analytics: consent.analytics ?? snapshot.analytics,
                feedback: consent.feedback ?? snapshot.feedback,
                push: consent.push ?? snapshot.push,
                survey: consent.survey ?? snapshot.survey
            )
            snapshot = merged
            revision += 1
            effectiveAt = Date()
            let record = Record(purposes: snapshot, version: revision, updatedAt: effectiveAt)
            if let secure, let data = try? JSONEncoder.usergist().encode(record),
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

    func clear() {
        queue.sync {
            snapshot = Consent()
            revision += 1
            effectiveAt = Date()
            _ = secure?.delete(.consent)
            try? storage.deleteFile(at: storage.consentFile)
        }
    }
}
