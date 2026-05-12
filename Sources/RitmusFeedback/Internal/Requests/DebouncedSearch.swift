import Foundation

// PORTED FROM: packages/sdk-react-native/src/internal/requests.ts
//                (createDebouncedSearch — 300ms typeahead helper)
//
// Coalesces rapid `query(_:)` calls so only the latest survives the debounce
// window. A monotonically increasing sequence number drops in-flight requests
// whose result returns after a newer query was issued — typeahead never
// flickers a stale result.

final class DebouncedSearch<TResult> {
    typealias Listener = (String, TResult) -> Void

    private let fn: (String, @escaping (Result<TResult, Error>) -> Void) -> Void
    private let delayMs: Int
    private var timer: DispatchSourceTimer?
    private var lastSeq: UInt64 = 0
    private var listeners: [UUID: Listener] = [:]
    private let queue = DispatchQueue(label: "studio.ritmus.debouncedsearch")

    init(
        delayMs: Int = 300,
        fn: @escaping (String, @escaping (Result<TResult, Error>) -> Void) -> Void
    ) {
        self.fn = fn
        self.delayMs = delayMs
    }

    func query(_ q: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer?.cancel()
            self.lastSeq &+= 1
            let seq = self.lastSeq
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + .milliseconds(self.delayMs))
            t.setEventHandler { [weak self] in
                guard let self = self else { return }
                self.fn(q) { result in
                    self.queue.async {
                        // Drop stale results: another query has fired since.
                        if seq != self.lastSeq { return }
                        switch result {
                        case .success(let r):
                            for cb in self.listeners.values { cb(q, r) }
                        case .failure:
                            // Swallow — RN reference renders nothing on error
                            // and lets the user "post anyway".
                            break
                        }
                    }
                }
            }
            t.resume()
            self.timer = t
        }
    }

    @discardableResult
    func subscribe(_ cb: @escaping Listener) -> () -> Void {
        let token = UUID()
        queue.sync { listeners[token] = cb }
        return { [weak self] in
            self?.queue.async { self?.listeners.removeValue(forKey: token) }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.lastSeq &+= 1
        }
    }
}
