import Foundation

/// One process-wide queue for every SDK-owned modal. This mirrors the React
/// Native provider coordinator and prevents prompts, surveys, and in-app
/// messages from overlapping or being discarded during transitions.
final class SDKModalCoordinator {
    static let shared = SDKModalCoordinator()

    private struct Pending {
        weak var owner: AnyObject?
        let start: (@escaping () -> Void) -> Bool
    }

    private var pending: [Pending] = []
    private var active = false

    private init() {}

    func enqueue(
        owner: AnyObject,
        start: @escaping (@escaping () -> Void) -> Bool
    ) {
        DispatchQueue.main.async { [weak self, weak owner] in
            guard let self, let owner else { return }
            self.pending.append(Pending(owner: owner, start: start))
            self.drain()
        }
    }

    func cancelPending(owner: AnyObject) {
        DispatchQueue.main.async { [weak self, weak owner] in
            guard let self, let owner else { return }
            self.pending.removeAll { $0.owner === owner || $0.owner == nil }
        }
    }

    func retryPending() {
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }

    private func drain() {
        guard !active else { return }
        while !pending.isEmpty {
            let item = pending.removeFirst()
            guard item.owner != nil else { continue }
            active = true
            var released = false
            let started = item.start { [weak self] in
                DispatchQueue.main.async {
                    guard let self, !released else { return }
                    released = true
                    self.active = false
                    self.drain()
                }
            }
            if !started {
                active = false
                pending.insert(item, at: 0)
            }
            return
        }
    }
}
