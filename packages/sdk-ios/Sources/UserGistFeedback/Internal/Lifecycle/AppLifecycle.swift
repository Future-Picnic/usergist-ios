import Foundation
import UIKit

/// Observes application lifecycle events and forwards them to SDK
/// subsystems (flush on background, refresh triggers on foreground).
final class AppLifecycleObserver {
    private let queue: DispatchQueue
    private var onActive: (() -> Void)?
    private var onBackground: (() -> Void)?
    private var onTerminate: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(
        onActive: @escaping () -> Void,
        onBackground: @escaping () -> Void,
        onTerminate: @escaping () -> Void
    ) {
        self.onActive = onActive
        self.onBackground = onBackground
        self.onTerminate = onTerminate
        let nc = NotificationCenter.default

        let active = nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.queue.async { self?.onActive?() }
        }
        let resign = nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.queue.async { self?.onBackground?() }
        }
        let terminate = nc.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.queue.async { self?.onTerminate?() }
        }
        observers = [active, resign, terminate]
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    deinit { stop() }
}
