import Foundation
import os.log

/// Lightweight logging facade used across the SDK.
///
/// Wraps `os.Logger` and gates verbose output on the `debug` flag. The
/// SDK NEVER logs user content — only structural decisions and errors.
final class RitmusLogger: @unchecked Sendable {
    enum Level: Int {
        case debug, info, warn, error
    }

    private let osLogger: OSLog
    private var debugEnabled: Bool
    private let lock = NSLock()

    init(subsystem: String = "studio.ritmus.feedback", category: String = "sdk", debug: Bool) {
        self.osLogger = OSLog(subsystem: subsystem, category: category)
        self.debugEnabled = debug
    }

    func setDebug(_ enabled: Bool) {
        lock.lock()
        debugEnabled = enabled
        lock.unlock()
    }

    private var isDebug: Bool {
        lock.lock()
        defer { lock.unlock() }
        return debugEnabled
    }

    func debug(_ message: @autoclosure () -> String) {
        guard isDebug else { return }
        os_log("%{public}@", log: osLogger, type: .debug, message())
    }

    func info(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLogger, type: .info, message())
    }

    func warn(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLogger, type: .default, "WARN: \(message())")
    }

    func error(_ message: @autoclosure () -> String, error: Error? = nil) {
        if let error {
            os_log("%{public}@", log: osLogger, type: .error, "\(message()) — \(error)")
        } else {
            os_log("%{public}@", log: osLogger, type: .error, "\(message())")
        }
    }

    /// Runs `block`; logs and swallows any thrown error. Returns `nil` on
    /// failure. Used as the SDK's safety net at all public-API boundaries.
    @discardableResult
    func trap<T>(_ label: String, _ block: () throws -> T) -> T? {
        do {
            return try block()
        } catch {
            self.error("trap[\(label)] failed", error: error)
            return nil
        }
    }
}
