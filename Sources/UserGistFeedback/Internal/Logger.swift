import Foundation
import os.log

/// Lightweight logging facade used across the SDK.
///
/// Wraps `os.Logger` and gates verbose output on the `debug` flag. The
/// SDK NEVER logs user content — only structural decisions and errors.
final class UserGistLogger: @unchecked Sendable {
    enum Level: Int {
        case debug, info, warn, error
    }

    private let osLogger: OSLog
    private var debugEnabled: Bool
    private let lock = NSLock()
    private var diagnosticHandler: ((SdkDiagnostic) -> Void)?

    func setDiagnosticHandler(_ handler: ((SdkDiagnostic) -> Void)?) {
        lock.lock()
        diagnosticHandler = handler
        lock.unlock()
    }

    private func emitDiagnostic(_ message: String) {
        lock.lock()
        let handler = diagnosticHandler
        lock.unlock()
        guard let handler else { return }
        do {
            handler(SdkDiagnostic(
                code: "sdk_error",
                message: String(message.prefix(200)),
                occurredAt: Date()
            ))
        }
    }

    init(subsystem: String = "studio.usergist.feedback", category: String = "sdk", debug: Bool) {
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
        let resolved = message()
        emitDiagnostic(resolved)
        os_log("%{public}@", log: osLogger, type: .default, "WARN: \(resolved)")
    }

    func error(_ message: @autoclosure () -> String, error: Error? = nil) {
        let resolved = message()
        emitDiagnostic(resolved)
        if let error {
            os_log("%{public}@", log: osLogger, type: .error, "\(resolved) — \(error)")
        } else {
            os_log("%{public}@", log: osLogger, type: .error, resolved)
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
