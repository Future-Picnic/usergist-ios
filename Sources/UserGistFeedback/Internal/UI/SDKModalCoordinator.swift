import Foundation

/// One process-wide queue for SDK-rendered campaigns. This mirrors the React
/// Native provider coordinator and prevents prompts, surveys, and in-app
/// messages from overlapping or being discarded during transitions.
final class SDKModalCoordinator {
    static let shared = SDKModalCoordinator()

    private struct Pending {
        weak var owner: AnyObject?
        let key: String?
        let isValid: () -> Bool
        let start: (@escaping () -> Void) -> Bool
    }

    private var pending: [Pending] = []
    private var active = false
    private weak var activeOwner: AnyObject?
    private var activeKey: String?
    private var retryScheduled = false
    private let pauseLock = NSLock()
    private var paused = false

    init() {}

    /// Set synchronously, including before asynchronous SDK bootstrap begins.
    /// Pausing never dismisses a modal that is already visible.
    func setPaused(_ paused: Bool) {
        pauseLock.lock()
        self.paused = paused
        pauseLock.unlock()
        if !paused { retryPending() }
    }

    var isPaused: Bool {
        pauseLock.lock()
        defer { pauseLock.unlock() }
        return paused
    }

    func enqueue(
        owner: AnyObject,
        key: String? = nil,
        isValid: @escaping () -> Bool = { true },
        start: @escaping (@escaping () -> Void) -> Bool
    ) {
        DispatchQueue.main.async { [weak self, weak owner] in
            guard let self, let owner else { return }
            self.pending.removeAll { $0.owner == nil || !$0.isValid() }
            if let key,
               (self.active && self.activeOwner === owner && self.activeKey == key
                || self.pending.contains(where: { $0.owner === owner && $0.key == key })) {
                return
            }
            self.pending.append(Pending(owner: owner, key: key, isValid: isValid, start: start))
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
        guard !active, !isPaused else { return }
        while !pending.isEmpty {
            let item = pending.removeFirst()
            guard item.owner != nil, item.isValid() else { continue }
            active = true
            activeOwner = item.owner
            activeKey = item.key
            var released = false
            let started = item.start { [weak self] in
                DispatchQueue.main.async {
                    guard let self, !released else { return }
                    released = true
                    self.active = false
                    self.activeOwner = nil
                    self.activeKey = nil
                    self.drain()
                }
            }
            if !started {
                active = false
                activeOwner = nil
                activeKey = nil
                pending.insert(item, at: 0)
                scheduleRetry()
            }
            return
        }
    }

    /// A UIKit transition can finish without another app lifecycle event.
    /// Keep one retry outstanding, and do no polling while the host is paused.
    private func scheduleRetry() {
        guard !retryScheduled, !isPaused else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            self.drain()
        }
    }
}
