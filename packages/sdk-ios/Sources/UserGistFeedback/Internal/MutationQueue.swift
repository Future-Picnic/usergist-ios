import Foundation

enum MutationKind: String, Codable, Equatable {
    case identify
    case userProperties = "user-properties"
    case feedbackResponse = "feedback-response"
    case surveyComplete = "survey-complete"
    case surveyAbandon = "survey-abandon"
}

enum MutationPurpose: String, Codable, Equatable {
    case essential
    case analytics
    case feedback
    case survey
}

struct PendingMutation: Codable, Equatable {
    let id: String
    let kind: MutationKind
    let purpose: MutationPurpose
    let payload: Data
    let createdAt: Date
    let dedupeKey: String?
}

private struct PersistedMutations: Codable {
    let version: Int
    let items: [PendingMutation]
}

/// Keychain-backed FIFO for non-event mutations that must survive relaunch.
/// Runtime owns serialization, so this type intentionally has no lock.
final class MutationQueue {
    private let secure: SecureStore
    private let logger: UserGistLogger
    private var items: [PendingMutation]

    init(secure: SecureStore, logger: UserGistLogger) {
        self.secure = secure
        self.logger = logger
        if let data = secure.read(.mutationQueue),
           let stored = try? JSONDecoder.usergist().decode(PersistedMutations.self, from: data),
           stored.version == 1 {
            items = stored.items
        } else {
            items = []
        }
    }

    var count: Int { items.count }
    var first: PendingMutation? { items.first }
    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    @discardableResult
    func enqueue(
        kind: MutationKind,
        purpose: MutationPurpose,
        payload: Data,
        dedupeKey: String? = nil
    ) -> String? {
        let existing = dedupeKey.flatMap { key in items.first { $0.dedupeKey == key } }
        if let existing, kind != .identify { return existing.id }
        var nextPayload = payload
        if let existing,
           let old = try? JSONSerialization.jsonObject(with: existing.payload) as? [String: Any],
           var next = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            next["properties"] = (old["properties"] as? [String: Any] ?? [:])
                .merging(next["properties"] as? [String: Any] ?? [:]) { _, new in new }
            guard let encoded = try? JSONSerialization.data(withJSONObject: next) else { return nil }
            nextPayload = encoded
        }
        let item = PendingMutation(
            id: UUID().uuidString,
            kind: kind,
            purpose: purpose,
            payload: nextPayload,
            createdAt: Date(),
            dedupeKey: dedupeKey
        )
        let previous = items
        if let existing { items = items.map { $0.id == existing.id ? item : $0 } }
        else if purpose == .essential { items.insert(item, at: 0) }
        else { items.append(item) }
        guard persist() else {
            items = previous
            return nil
        }
        return item.id
    }

    @discardableResult
    func remove(_ id: String) -> Bool {
        let previous = items
        items.removeAll { $0.id == id }
        guard persist() else {
            items = previous
            return false
        }
        return true
    }

    func removePurpose(_ purpose: MutationPurpose) {
        let previous = items
        items.removeAll { $0.purpose == purpose }
        if !persist() { items = previous }
    }

    @discardableResult
    func clear() -> Bool {
        let previous = items
        items.removeAll()
        if !persist() { items = previous; return false }
        return true
    }

    private func persist() -> Bool {
        do {
            let data = try JSONEncoder.usergist().encode(
                PersistedMutations(version: 1, items: items)
            )
            if secure.write(.mutationQueue, data) { return true }
        } catch {
            logger.error("mutation queue encode failed", error: error)
            return false
        }
        logger.warn("mutation queue persistence failed")
        return false
    }
}
