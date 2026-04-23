import Foundation
import UIKit

/// Concrete orchestrator behind the `Ritmus` singleton.
///
/// Owns every internal subsystem and funnels all mutation through a single
/// serial queue. Nothing outside this type should hold long-lived
/// references to its internals.
final class Runtime {
    let config: RitmusConfig
    let logger: RitmusLogger
    private let storage: Storage
    private let identityStore: IdentityStore
    private let consentStore: ConsentStore
    private let eventQueue: EventQueue
    private let apiClient: APIClient
    private let transport: Transport
    private let rulesCache: RulesCache
    private let frequencyCap: FrequencyCapStore
    private let userStateTracker: UserStateTracker
    private let triggerMatcher: TriggerMatcher
    private let presenter: PromptPresenter
    private let lifecycle: AppLifecycleObserver
    let pushRegistrar: PushRegistrar

    /// Serial queue for all mutating operations.
    private let workQueue: DispatchQueue

    private var themeOverrides: PromptTheme?
    private var triggerSyncTimer: DispatchSourceTimer?
    private var lastTriggerSync: Date?
    private var isRefreshingTriggers = false

    init(config: RitmusConfig) throws {
        self.config = config
        let workQueue = RitmusQueue.serial("runtime", qos: .utility)
        self.workQueue = workQueue
        self.logger = RitmusLogger(debug: config.debug)
        self.storage = try Storage(writeKeyHash: config.writeKeyHash)
        self.identityStore = IdentityStore(storage: storage, logger: logger, queue: RitmusQueue.serial("identity"))
        self.consentStore = ConsentStore(storage: storage, logger: logger, queue: RitmusQueue.serial("consent"))
        self.eventQueue = EventQueue(
            storage: storage,
            logger: logger,
            maxCount: config.maxQueueSize,
            maxBytes: config.maxQueueBytes
        )
        self.apiClient = APIClient(
            baseURL: config.apiURL,
            writeKey: config.writeKey,
            sdkVersion: config.sdkVersion,
            logger: logger,
            callbackQueue: workQueue
        )
        self.transport = Transport(
            config: config,
            apiClient: apiClient,
            logger: logger,
            queue: workQueue,
            eventQueue: eventQueue,
            identity: identityStore,
            consent: consentStore
        )
        self.rulesCache = RulesCache(
            storage: storage,
            logger: logger,
            queue: RitmusQueue.serial("rules")
        )
        self.frequencyCap = FrequencyCapStore(
            storage: storage,
            logger: logger,
            queue: RitmusQueue.serial("frequency")
        )
        self.userStateTracker = UserStateTracker(queue: RitmusQueue.serial("user-state"))
        let rulesCacheRef = rulesCache
        let frequencyCapRef = frequencyCap
        let consentStoreRef = consentStore
        let loggerRef = logger
        let trackerRef = userStateTracker
        self.triggerMatcher = TriggerMatcher(
            rulesCache: rulesCacheRef,
            frequencyCap: frequencyCapRef,
            consent: consentStoreRef,
            logger: loggerRef,
            userState: { trackerRef.snapshot() }
        )
        self.presenter = PromptPresenter()
        self.lifecycle = AppLifecycleObserver(queue: workQueue)
        self.pushRegistrar = PushRegistrar(
            apiClient: apiClient,
            identity: identityStore,
            consent: consentStore,
            logger: logger,
            queue: RitmusQueue.serial("push")
        )

        // Seed user-state tracker from cached rules so first trigger fires
        // with correct windowed counters.
        let initialWindows = UserStateTracker.windows(from: rulesCache.triggers(for: ""))
        userStateTracker.setKnownWindows(initialWindows)
    }

    // MARK: - Lifecycle

    func start() {
        work { [weak self] in
            guard let self else { return }
            self.transport.startPeriodicFlush()
            self.scheduleTriggerSync()
            self.lifecycle.start(
                onActive: { [weak self] in
                    self?.refreshTriggersIfStale()
                    self?.transport.flushIfNeeded()
                },
                onBackground: { [weak self] in
                    self?.transport.flushIfNeeded()
                },
                onTerminate: { [weak self] in
                    self?.transport.flushIfNeeded()
                }
            )
            // Kick off an immediate trigger refresh so the first event can
            // match against fresh rules.
            self.refreshTriggers()
        }
    }

    /// Runs `block` serially on the runtime's queue.
    func work(_ block: @escaping () -> Void) {
        workQueue.async(execute: block)
    }

    // MARK: - Public-facing operations (called via Ritmus singleton)

    var anonymousId: String { identityStore.anonymousId }

    func identify(userId: String, properties: [String: Any]?) {
        identityStore.setExternalId(userId)
        userStateTracker.setProperties(properties)
        if consentStore.allowsTransport {
            transport.sendIdentify(userId: userId, properties: properties)
        }
    }

    func track(eventName: String, properties: [String: Any]?) {
        let timestamp = Date()
        userStateTracker.recordEvent(name: eventName, at: timestamp)

        let identity = identityStore.current()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let event = IngestEvent(
            name: eventName,
            timestamp: timestamp,
            anonymousId: identity.anonymousId,
            externalId: identity.externalId,
            properties: AnyCodable.wrap(properties),
            sessionId: nil,
            sdkVersion: config.sdkVersion,
            appVersion: appVersion,
            platform: "ios"
        )

        // Gate the transport; queue grows until consent granted.
        eventQueue.enqueue(event)
        if consentStore.allowsTransport {
            transport.flushIfNeeded()
        }

        // Evaluate triggers client-side for instant firing.
        if let trigger = triggerMatcher.match(eventName: eventName) {
            firePrompt(for: trigger)
        }
    }

    func setConsent(_ purposes: Consent) {
        let changed = consentStore.update(purposes)
        if changed {
            transport.sendConsent(purposes)
        }
        if purposes.allowsTransport {
            // Drain queued events.
            transport.flushIfNeeded()
            refreshTriggers()
        }
    }

    func reset() {
        identityStore.resetAll()
        userStateTracker.reset()
        frequencyCap.reset()
        eventQueue.clear()
        rulesCache.clear()
    }

    func setThemeOverrides(_ theme: PromptTheme) {
        themeOverrides = theme
    }

    func flushNow() {
        transport.flushIfNeeded()
    }

    func setDebug(_ enabled: Bool) {
        logger.setDebug(enabled)
    }

    // MARK: - Trigger sync

    private func scheduleTriggerSync() {
        triggerSyncTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(
            deadline: .now() + config.triggerSyncInterval,
            repeating: config.triggerSyncInterval
        )
        timer.setEventHandler { [weak self] in
            self?.refreshTriggers()
        }
        timer.resume()
        triggerSyncTimer = timer
    }

    private func refreshTriggersIfStale() {
        let stale: Bool = {
            guard let last = lastTriggerSync else { return true }
            return Date().timeIntervalSince(last) > config.triggerSyncInterval
        }()
        if stale { refreshTriggers() }
    }

    private func refreshTriggers() {
        guard consentStore.allowsTransport else {
            logger.debug("trigger refresh skipped: consent gate")
            return
        }
        guard !isRefreshingTriggers else { return }
        isRefreshingTriggers = true

        let identity = identityStore.current()
        transport.fetchArmedTriggers(
            anonymousId: identity.anonymousId,
            externalId: identity.externalId
        ) { [weak self] result in
            guard let self else { return }
            self.work {
                self.isRefreshingTriggers = false
                switch result {
                case .success(let response):
                    self.rulesCache.replace(response.triggers)
                    let windows = UserStateTracker.windows(from: response.triggers)
                    self.userStateTracker.setKnownWindows(windows)
                    self.lastTriggerSync = Date()
                    self.logger.debug("armed triggers refreshed: \(response.triggers.count)")
                case .failure(let err):
                    self.logger.warn("armed triggers refresh failed: \(err)")
                }
            }
        }
    }

    // MARK: - Prompt firing

    private func firePrompt(for trigger: ArmedTrigger) {
        let resolvedTheme = ThemeResolver.resolve(
            server: trigger.prompt.theme,
            override: themeOverrides
        )
        let shownAt = Date()
        frequencyCap.recordShown(promptId: trigger.promptId)
        let promptId = trigger.promptId

        // Callback on main queue after presenter work completes.
        let onShown: () -> Void = { [weak self] in
            guard let self else { return }
            // Emit shown callback outside the work queue to avoid re-entrancy.
            DispatchQueue.main.async {
                Ritmus.shared.onPromptShown?(promptId)
            }
            // Record `$feedback_prompt_shown` as a first-class event.
            self.work {
                self.track(eventName: "$feedback_prompt_shown", properties: ["promptId": promptId])
            }
        }

        let onFinish: (PromptResponseInfo) -> Void = { [weak self] info in
            guard let self else { return }
            self.work {
                self.handleResponse(info: info)
            }
            DispatchQueue.main.async {
                Ritmus.shared.onResponse?(info)
            }
        }

        presenter.present(
            context: .init(prompt: trigger.prompt, theme: resolvedTheme, shownAt: shownAt),
            onShown: onShown,
            onFinish: onFinish
        )
    }

    private func handleResponse(info: PromptResponseInfo) {
        let identity = identityStore.current()
        let wireAnswers = info.answers.map { answer -> ResponseAnswerWire in
            let value: AnswerValueWire = {
                switch answer.value {
                case .number(let n): return .number(n)
                case .text(let t): return .string(t)
                case .choices(let list): return .list(list)
                case .none: return .null
                }
            }()
            return ResponseAnswerWire(questionId: answer.questionId, value: value)
        }
        let payload = SubmitResponsePayload(
            promptId: info.promptId,
            anonymousId: identity.anonymousId,
            externalId: identity.externalId,
            answers: info.dismissed ? nil : wireAnswers,
            dismissed: info.dismissed,
            latencyMs: info.latencyMs
        )
        transport.submitResponse(payload)

        // Track a `$feedback_response` event so responses flow through the
        // same pipeline as any other event.
        var props: [String: Any] = [
            "promptId": info.promptId,
            "dismissed": info.dismissed,
            "latencyMs": info.latencyMs
        ]
        if !info.answers.isEmpty {
            props["answerCount"] = info.answers.count
        }
        track(eventName: "$feedback_response", properties: props)
    }
}
