import Foundation

/// Stored separately from user queues so reset and relaunch cannot forget an
/// offline logout. All access is on Runtime's work queue.
final class SessionRevocations {
    private struct Entry: Codable { let id: String; let token: String; let anonymousId: String }
    private struct Body: Encodable { let anonymousId: String }
    private let secure: SecureStore
    private let api: APIClient
    private var entries: [Entry]
    private var draining = false
    var isPending: Bool { !entries.isEmpty }
    init(secure: SecureStore, api: APIClient) {
        self.secure = secure; self.api = api
        entries = secure.read(.sessionRevocations).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }
    func remember(token: String?, anonymousId: String) -> Bool {
        guard let token else { return true }
        if entries.contains(where: { $0.token == token && $0.anonymousId == anonymousId }) { return true }
        let previous = entries
        entries.append(Entry(id: UUID().uuidString, token: token, anonymousId: anonymousId))
        guard persist() else { entries = previous; return false }
        return true
    }
    func drain() {
        guard !draining, let entry = entries.first else { return }
        draining = true
        api.postVoid(path: SDKEndpoint.sessionRevoke, body: Body(anonymousId: entry.anonymousId),
            requiresSubject: false, subjectTokenOverride: entry.token) { [weak self] result in
            guard let self else { return }
            self.draining = false
            switch result {
            case .success, .failure(.server(status: 401, body: _)):
                let previous = self.entries
                self.entries.removeAll { $0.id == entry.id }
                if self.persist() { self.drain() } else { self.entries = previous }
            default: break
            }
        }
    }
    private func persist() -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        return secure.write(.sessionRevocations, data)
    }
}
