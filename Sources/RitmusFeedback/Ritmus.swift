import Foundation
import UIKit

/// Public entry point for the Ritmus Feedback iOS SDK.
///
/// A single shared instance is available as `Ritmus.shared`. All public
/// methods are thread-safe and non-blocking — heavy work (I/O, network,
/// trigger evaluation) happens on an internal serial queue.
///
/// Typical usage in an app delegate:
///
/// ```swift
/// Ritmus.shared.initialize(writeKey: "pk_live_...")
/// Ritmus.shared.setConsent(Consent(analytics: true, feedback: true))
/// Ritmus.shared.track("opened_app")
/// ```
public final class Ritmus {
    /// Shared singleton. The SDK is only useful in singleton form since it
    /// owns storage files and lifecycle observers.
    public static let shared = Ritmus()

    // MARK: - Public callbacks

    /// Invoked each time a prompt is shown. The parameter is the prompt ID.
    public var onPromptShown: ((String) -> Void)?

    /// Invoked each time a user responds to (or dismisses) a prompt.
    public var onResponse: ((PromptResponseInfo) -> Void)?

    // MARK: - Internal state

    private let bootstrapQueue = RitmusQueue.serial("bootstrap")
    private let lock = NSLock()
    private var runtime: Runtime?

    /// Push-notifications surface. Available after `initialize`; no-ops before.
    public private(set) lazy var push: RitmusPush = RitmusPush(
        registerToken: { [weak self] token in
            self?.withRuntime { rt in rt.pushRegistrar.register(token: token) }
        },
        track: { [weak self] name, props in
            self?.track(name, properties: props)
        },
        appOpen: { [weak self] in
            self?.withRuntime { rt in rt.pushRegistrar.reportAppOpen() }
        },
        beacon: { [weak self] kind, deliveryId, action in
            self?.withRuntime { rt in
                rt.pushRegistrar.beacon(kind: kind, deliveryId: deliveryId, actionButton: action)
            }
        }
    )

    private init() {}

    // MARK: - Public API

    /// Initializes the SDK. Subsequent calls are no-ops.
    ///
    /// - Parameters:
    ///   - writeKey: Your Ritmus write key (required).
    ///   - environment: `.production`, `.staging`, or `.development`.
    ///   - apiURL: Explicit API base URL. Overrides the environment default.
    ///   - debug: Emit `os_log` debug trace (default `false`).
    ///   - flushInterval: Seconds between automatic flushes (default 15s).
    ///   - flushBatchSize: Max events per ingest request (default 100).
    ///   - maxQueueSize: Max queued events before drop-oldest (default 1000).
    ///   - triggerSyncInterval: Seconds between armed-trigger refreshes (default 300s).
    public func initialize(
        writeKey: String,
        environment: Environment = .production,
        apiURL: URL? = nil,
        debug: Bool = false,
        flushInterval: TimeInterval = 15,
        flushBatchSize: Int = 100,
        maxQueueSize: Int = 1_000,
        triggerSyncInterval: TimeInterval = 300
    ) {
        lock.lock()
        let alreadyInitialized = runtime != nil
        lock.unlock()
        guard !alreadyInitialized else { return }

        let config = RitmusConfig(
            writeKey: writeKey,
            environment: environment,
            apiURL: apiURL,
            debug: debug,
            flushInterval: flushInterval,
            flushBatchSize: flushBatchSize,
            maxQueueSize: maxQueueSize,
            triggerSyncInterval: triggerSyncInterval
        )

        // Non-blocking: assemble runtime on background queue.
        bootstrapQueue.async { [weak self] in
            guard let self else { return }
            do {
                let runtime = try Runtime(config: config)
                self.lock.lock()
                self.runtime = runtime
                self.lock.unlock()
                runtime.start()
            } catch {
                // Never throw across SDK boundary. Just log to the default logger.
                let fallback = RitmusLogger(debug: true)
                fallback.error("initialize failed", error: error)
            }
        }
    }

    /// Identifies the logged-in user. Safe to call multiple times.
    public func identify(userId: String, properties: [String: Any]? = nil) {
        withRuntime { rt in
            rt.identify(userId: userId, properties: properties)
        }
    }

    /// Records a custom event.
    public func track(_ eventName: String, properties: [String: Any]? = nil) {
        withRuntime { rt in
            rt.track(eventName: eventName, properties: properties)
        }
    }

    /// Sets (or updates) consent purposes.
    public func setConsent(_ purposes: Consent) {
        withRuntime { rt in
            rt.setConsent(purposes)
        }
    }

    /// Clears user identity on logout. Regenerates `anonymousId`.
    public func reset() {
        withRuntime { rt in
            rt.reset()
        }
    }

    /// Applies developer-supplied theme overrides on top of server themes.
    public func setThemeOverrides(_ theme: PromptTheme) {
        withRuntime { rt in
            rt.setThemeOverrides(theme)
        }
    }

    /// Force-flush the event queue now.
    public func flush() {
        withRuntime { rt in
            rt.flushNow()
        }
    }

    /// Toggles debug logging at runtime.
    public func setDebug(_ enabled: Bool) {
        lock.lock()
        let rt = runtime
        lock.unlock()
        rt?.setDebug(enabled)
    }

    /// Current device-local anonymous ID. Returns an empty string until
    /// `initialize` completes.
    public var anonymousId: String {
        lock.lock()
        let rt = runtime
        lock.unlock()
        return rt?.anonymousId ?? ""
    }

    // MARK: - Surveys

    /// Handlers invoked during the survey lifecycle (show / complete / abandon).
    /// Set these before calling `openSurvey` if you want to react to lifecycle events.
    public var surveyHandlers: SurveyHandlers = SurveyHandlers()

    /// Returns the list of surveys currently offerable to this user.
    /// Requires `Consent.survey = true`. Returns an empty list otherwise.
    public func getAvailableSurveys(completion: @escaping ([SurveySummary]) -> Void) {
        withRuntime { rt in
            rt.getAvailableSurveys { summaries in
                DispatchQueue.main.async {
                    completion(summaries)
                }
            }
        }
    }

    /// Launches a specific survey by ID. Host app is responsible for rendering
    /// the multi-step flow; the SDK provides the fetched flow via the handler.
    public func openSurvey(_ surveyId: String, language: String? = nil) {
        withRuntime { rt in
            rt.openSurvey(surveyId: surveyId, language: language, source: "on_demand")
        }
    }

    /// Handles a Ritmus survey share link. Returns true if the URL was recognized.
    @discardableResult
    public func handleSurveyDeepLink(_ url: URL) -> Bool {
        let path = url.path
        let tokenFromPath = path.hasPrefix("/s/") ? String(path.dropFirst(3)) : nil
        let tokenFromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "survey" })?.value
        let token = tokenFromPath ?? tokenFromQuery
        guard let token, !token.isEmpty else { return false }
        withRuntime { rt in
            rt.resolveSurveyLink(token: token)
        }
        return true
    }

    // MARK: - Internals

    private func withRuntime(_ body: @escaping (Runtime) -> Void) {
        bootstrapQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let rt = self.runtime
            self.lock.unlock()
            guard let rt else { return }
            rt.work {
                let logger = rt.logger
                logger.trap("public-api") {
                    body(rt)
                }
            }
        }
    }
}
