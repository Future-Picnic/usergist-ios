import Foundation
import UIKit

/// Concrete orchestrator behind the `UserGist` singleton.
///
/// Owns every internal subsystem and funnels all mutation through a single
/// serial queue. Nothing outside this type should hold long-lived
/// references to its internals.
final class Runtime {
    let config: UserGistConfig
    let logger: UserGistLogger
    private let storage: Storage
    let identityStore: IdentityStore
    let consentStore: ConsentStore
    private let eventQueue: EventQueue
    let apiClient: APIClient
    private let transport: Transport
    private let rulesCache: RulesCache
    private let campaignRules: CampaignRulesCache
    private let frequencyCap: FrequencyCapStore
    private let userStateTracker: UserStateTracker
    private let triggerMatcher: TriggerMatcher
    private let presenter: PromptPresenter
    private let inAppPresenter: InAppPresenter
    private let presentationEligibility = CampaignPresentationEligibility()
    private let lifecycle: AppLifecycleObserver
    let pushRegistrar: PushRegistrar
    private let secureStore: SecureStore
    private let surveyStore: SurveyStore
    private let mutations: MutationQueue
    private let localInstructionDedupe: LocalInstructionDedupe
    let requestsCache: RequestsCache

    /// Serial queue for all mutating operations.
    private let workQueue: DispatchQueue

    private var themeOverrides: PromptTheme?
    private var triggerSyncTimer: DispatchSourceTimer?
    private var lastTriggerSync: Date?
    private var isRefreshingTriggers = false
    private var appOpenPending = false
    private var subjectToken: String?
    private var sessionOpening = false
    private var sessionRetryScheduled = false
    private var authenticatedRuntimeStarted = false
    private var isPollingInstructions = false
    private var instructionPollRequested = false
    private var surveyCooldownByCampaign: [String: Date] = [:]
    private var isFlushingMutations = false
    private var mutationFlushTimer: DispatchSourceTimer?
    private var mutationDeliveryCallbacks: [String: (Bool) -> Void] = [:]
    var subjectTokenProvider: SubjectTokenProvider?
    var onIdentityState: ((IdentityState) -> Void)?
    private var identityCallbacks: [String: (IdentifyResult) -> Void] = [:]
    private var resetCallbacks: [(Bool) -> Void] = []
    private var resetRunning = false
    private var pendingReset: (token: String?, anonymousId: String)?
    private lazy var revocations = SessionRevocations(secure: secureStore, api: apiClient)
    private var recoveringIdentity = false
    private var recoveryAttempt: UUID?
    private var lastRecovery: Date = .distantPast
    private var resetGeneration: UInt64 = 0
    private var resetInProgress = false
    private var pendingPromptCapIds: Set<String> = []
    private var pendingSurveyCapIds: Set<String> = []

    init(config: UserGistConfig, session: URLSession? = nil, secureStore: SecureStore? = nil) throws {
        self.config = config
        let workQueue = UserGistQueue.serial("runtime", qos: .utility)
        self.workQueue = workQueue
        self.logger = UserGistLogger(debug: config.debug)
        self.storage = try Storage(writeKeyHash: config.writeKeyHash)
        self.secureStore = secureStore ?? SecureStore(writeKeyHash: config.writeKeyHash, logger: logger)
        self.identityStore = IdentityStore(storage: storage, secure: self.secureStore, logger: logger, queue: UserGistQueue.serial("identity"))
        self.consentStore = ConsentStore(storage: storage, secure: self.secureStore, logger: logger, queue: UserGistQueue.serial("consent"))
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
            callbackQueue: workQueue,
            session: session,
            tlsPinSets: config.tlsPinSets
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
            queue: UserGistQueue.serial("rules")
        )
        self.campaignRules = CampaignRulesCache(
            storage: storage,
            logger: logger,
            queue: UserGistQueue.serial("campaign-rules")
        )
        self.frequencyCap = FrequencyCapStore(
            storage: storage,
            logger: logger,
            queue: UserGistQueue.serial("frequency")
        )
        self.userStateTracker = UserStateTracker(
            queue: UserGistQueue.serial("user-state"),
            storage: storage,
            logger: logger
        )
        self.userStateTracker.setPersistedProperties(identityStore.current().properties)
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
        self.inAppPresenter = InAppPresenter()
        self.lifecycle = AppLifecycleObserver(queue: workQueue)
        self.pushRegistrar = PushRegistrar(
            apiClient: apiClient,
            identity: identityStore,
            consent: consentStore,
            logger: logger,
            queue: workQueue,
            environment: config.environment == .production ? "production" : "sandbox",
            secure: self.secureStore
        )
        self.surveyStore = SurveyStore(
            storage: storage,
            logger: logger,
            queue: UserGistQueue.serial("survey-store")
        )
        self.mutations = MutationQueue(secure: self.secureStore, logger: logger)
        self.localInstructionDedupe = LocalInstructionDedupe(
            storage: storage,
            logger: logger
        )
        self.requestsCache = RequestsCache()
        self.presentationEligibility.updateConsent(consentStore.current())
        self.pushRegistrar.canRegister = { [weak self] in
            guard let self, !self.resetInProgress else { return false }
            self.revocations.drain()
            return !self.revocations.isPending
        }
        self.apiClient.onAuthenticationRequired = { [weak self] in self?.recoverIdentity() }
        self.transport.onPollInstructions = { [weak self] in
            self?.pollInstructions(); self?.revocations.drain(); self?.pushRegistrar.retryRegistration()
        }

        // Seed user-state tracker from cached rules so first trigger fires
        // with correct windowed counters.
        let initialWindows = UserStateTracker.windows(from: rulesCache.snapshot())
            .union(UserStateTracker.windows(from: campaignRules.surveySnapshot()))
        userStateTracker.setKnownWindows(initialWindows)
    }

    /// Stop an owned runtime before disposing its injected network session.
    /// Does not erase identity or perform a remote logout.
    func stop() {
        resetInProgress = true
        resetGeneration &+= 1
        lifecycle.stop()
        triggerSyncTimer?.cancel()
        mutationFlushTimer?.cancel()
        transport.invalidate()
        apiClient.cancelAll()
        apiClient.setSubjectToken(nil)
        onIdentityState = nil
        pushRegistrar.onSubscriptionState = nil
    }

    // MARK: - Lifecycle

    func start() {
        work { [weak self] in
            guard let self else { return }
            self.localInstructionDedupe.hydrate()
            self.revocations.drain()
            self.notifyIdentity(self.externalId == nil ? .anonymous : .identifying)
            let persisted = self.secureStore.read(.subjectToken)
                .flatMap { String(data: $0, encoding: .utf8) }
            self.apiClient.setSubjectToken(persisted)
            self.establishSubjectSession(persistedToken: persisted) { [weak self] ready in
                guard let self, ready else { return }
                self.startAuthenticatedRuntime()
            }
        }
    }

    private func startAuthenticatedRuntime() {
        guard !authenticatedRuntimeStarted else { return }
        authenticatedRuntimeStarted = true
        self.transport.startPeriodicFlush()
        self.scheduleMutationFlush()
        self.scheduleTriggerSync()
        self.lifecycle.start(
            onActive: { [weak self] in
                self?.inAppPresenter.retryPending()
                self?.refreshTriggersIfStale()
                self?.requestAppOpen()
                self?.transport.flushIfNeeded()
                self?.pollInstructions()
                self?.flushMutations()
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
        self.requestAppOpen()
        self.pollInstructions()
        self.flushMutations()
    }

    private func establishSubjectSession(
        persistedToken: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard !resetInProgress else {
            completion(false)
            return
        }
        guard !sessionOpening else {
            completion(subjectToken != nil)
            return
        }
        let generation = resetGeneration
        sessionOpening = true
        openSubjectSessionAttempt(
            persistedToken: persistedToken,
            mayRotateIdentity: true,
            generation: generation
        ) { [weak self] success in
            guard let self else { return }
            guard generation == self.resetGeneration, !self.resetInProgress else { return }
            self.sessionOpening = false
            if !success { self.scheduleSubjectSessionRetry() }
            completion(success)
        }
    }

    private func openSubjectSessionAttempt(
        persistedToken: String?,
        mayRotateIdentity: Bool,
        generation: UInt64,
        completion: @escaping (Bool) -> Void
    ) {
        apiClient.setSubjectToken(persistedToken)
        apiClient.postJSON(
            path: SDKEndpoint.session,
            body: SubjectSessionRequest(anonymousId: identityStore.anonymousId),
            responseType: SubjectSessionResponse.self,
            requiresSubject: false,
            idempotent: false
        ) { [weak self] result in
            guard let self else { return }
            guard generation == self.resetGeneration, !self.resetInProgress else { return }
            switch result {
            case .success(let session) where session.subjectToken.hasPrefix("st_"):
                guard self.secureStore.write(
                    .subjectToken,
                    Data(session.subjectToken.utf8)
                ) else {
                    self.subjectToken = nil
                    self.apiClient.setSubjectToken(nil)
                    self.logger.warn("unable to persist UserGist subject session")
                    completion(false)
                    return
                }
                self.subjectToken = session.subjectToken
                self.apiClient.setSubjectToken(session.subjectToken)
                self.notifyIdentity(self.externalId == nil ? .anonymous : .identified)
                self.flushMutations()
                self.pushRegistrar.retryRegistration()
                completion(true)
            case .failure(let error) where self.externalId != nil && Self.shouldRotateIdentity(error):
                self.recoverIdentity()
                completion(false)
            case .failure(let error) where mayRotateIdentity && Self.shouldRotateIdentity(error):
                // A claimed anonymous alias cannot receive a replacement
                // credential. Rotate before retrying without the stale token.
            guard self.secureStore.delete(.subjectToken) else { completion(false); return }
                self.apiClient.setSubjectToken(nil)
                self.identityStore.resetAll()
                self.openSubjectSessionAttempt(
                    persistedToken: nil,
                    mayRotateIdentity: false,
                    generation: generation,
                    completion: completion
                )
            case .success, .failure:
                self.subjectToken = nil
                self.apiClient.setSubjectToken(nil)
                self.logger.warn("unable to establish UserGist subject session")
                completion(false)
            }
        }
    }

    private static func shouldRotateIdentity(_ error: APIClient.APIError) -> Bool {
        guard case .server(let status, _) = error else { return false }
        return status == 401 || status == 403 || status == 409
    }

    private func scheduleSubjectSessionRetry() {
        guard !resetInProgress, !sessionRetryScheduled, subjectToken == nil else { return }
        let generation = resetGeneration
        sessionRetryScheduled = true
        workQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            guard generation == self.resetGeneration, !self.resetInProgress else { return }
            self.sessionRetryScheduled = false
            guard self.subjectToken == nil else { return }
            let persisted = self.secureStore.read(.subjectToken)
                .flatMap { String(data: $0, encoding: .utf8) }
            self.establishSubjectSession(persistedToken: persisted) { [weak self] ready in
                if ready { self?.startAuthenticatedRuntime() }
            }
        }
    }

    /// Runs `block` serially on the runtime's queue.
    func work(_ block: @escaping () -> Void) {
        workQueue.async(execute: block)
    }

    // MARK: - Public-facing operations (called via UserGist singleton)

    var anonymousId: String { identityStore.anonymousId }
    var externalId: String? { identityStore.current().externalId }

    private func recoverIdentity() {
        guard !resetInProgress else { return }
        notifyIdentity(.authenticationRequired)
        guard let externalId, let provider = subjectTokenProvider, !recoveringIdentity,
              Date().timeIntervalSince(lastRecovery) >= 5 else { return }
        recoveringIdentity = true
        let attempt = UUID()
        recoveryAttempt = attempt
        lastRecovery = Date()
        let generation = resetGeneration
        DispatchQueue.main.async {
            provider(externalId) { [weak self] result in
                self?.work {
                    guard let self, generation == self.resetGeneration, !self.resetInProgress, self.recoveryAttempt == attempt else { return }
                    self.recoveringIdentity = false
                    self.recoveryAttempt = nil
                    if case .success(let token) = result {
                        self.identify(userId: externalId, properties: nil, subjectToken: token) { [weak self] result in
                            if result == .synced {
                                self?.work { self?.startAuthenticatedRuntime(); self?.flushNow() }
                            }
                        }
                    }
                }
            }
        }
        workQueue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, generation == self.resetGeneration, self.recoveryAttempt == attempt else { return }
            self.recoveringIdentity = false
            self.recoveryAttempt = nil
        }
    }

    func notifyIdentity(_ status: IdentityState.Status) {
        let identity = identityStore.current()
        onIdentityState?(IdentityState(status: status, anonymousId: identity.anonymousId, externalId: identity.externalId))
    }

    func identify(userId: String, properties: [String: Any]?, subjectToken: String, completion: ((IdentifyResult) -> Void)? = nil) {
        let pendingId = mutations.first.flatMap { try? JSONDecoder.usergist().decode(IdentifyMutationPayload.self, from: $0.payload) }?.externalId
        let currentId = identityStore.current().externalId
        guard !resetInProgress, currentId == nil || currentId == userId, pendingId == nil || pendingId == userId else {
            logger.warn("identify rejected: await reset before switching accounts")
            DispatchQueue.main.async { completion?(.rejected) }
            return
        }
        guard !userId.isEmpty else {
            DispatchQueue.main.async { completion?(.rejected) }
            logger.warn("identify requires a non-empty userId")
            return
        }
        guard subjectToken.hasPrefix("st_") else {
            DispatchQueue.main.async { completion?(.rejected) }
            logger.warn("identify requires a server-minted subject token")
            return
        }
        let cleanProperties = consentStore.current().analytics == true ? properties : nil
        let identity = identityStore.current()
        let payload = IdentifyMutationPayload(
            subjectToken: subjectToken,
            anonymousId: identity.anonymousId,
            externalId: userId,
            properties: AnyCodable.wrapEventProperties(cleanProperties, allowPii: true)
        )
        guard let data = try? JSONEncoder.usergist().encode(payload),
              let mutationId = mutations.enqueue(
                kind: .identify,
                purpose: .essential,
                payload: data,
                dedupeKey: "identify:\(userId)"
              ) else {
            DispatchQueue.main.async { completion?(.rejected) }
            logger.warn("identify could not be persisted")
            return
        }
        if let completion {
            if isFlushingMutations || mutations.first?.id != mutationId || self.subjectToken == nil {
                DispatchQueue.main.async { completion(.queued) }
            } else { identityCallbacks[mutationId] = completion }
        }
        notifyIdentity(.identifying)
        flushMutations()
    }

    func setUserProperties(_ properties: [String: Any], unset: [String], completion: ((IdentifyResult) -> Void)?) {
        guard !resetInProgress, consentStore.current().analytics == true,
              !properties.isEmpty || !unset.isEmpty, !unset.contains(where: { properties[$0] != nil }) else {
            DispatchQueue.main.async { completion?(.rejected) }; return
        }
        let payload = UserPropertiesPayload(anonymousId: anonymousId, mutationId: UUID().uuidString,
            set: AnyCodable.wrapEventProperties(properties, allowPii: true) ?? [:], unset: unset)
        guard let data = try? JSONEncoder.usergist().encode(payload),
              let id = mutations.enqueue(kind: .userProperties, purpose: .analytics, payload: data) else {
            DispatchQueue.main.async { completion?(.rejected) }; return
        }
        if let completion {
            if isFlushingMutations || mutations.first?.id != id || subjectToken == nil {
                DispatchQueue.main.async { completion(.queued) }
            } else { identityCallbacks[id] = completion }
        }
        flushMutations()
    }

    func track(
        eventName: String,
        properties: [String: Any]?,
        purpose: EventPurpose = .analytics
    ) {
        guard !resetInProgress else { return }
        guard !eventName.isEmpty else {
            logger.warn("track requires a non-empty event name")
            return
        }
        let timestamp = Date()
        userStateTracker.recordEvent(name: eventName, at: timestamp)

        let identity = identityStore.current()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let event = IngestEvent(
            name: eventName,
            timestamp: timestamp,
            anonymousId: identity.anonymousId,
            externalId: identity.externalId,
            properties: AnyCodable.wrapEventProperties(properties),
            sessionId: nil,
            sdkVersion: config.sdkVersion,
            appVersion: appVersion,
            platform: "ios",
            purpose: purpose
        )

        // Gate the transport; queue grows until consent granted.
        eventQueue.enqueue(event)
        if consentStore.allowsTransport {
            transport.flushIfNeeded()
        }

        // Evaluate triggers client-side for instant firing.
        if let trigger = triggerMatcher.match(eventName: eventName) {
            rememberLocalInstruction(
                type: "prompt.show",
                refId: trigger.promptId,
                eventId: event.eventId
            )
            firePrompt(for: trigger)
        }
        evaluateCampaigns(eventName: eventName, eventId: event.eventId)
    }

    func setConsent(_ purposes: Consent) {
        guard !resetInProgress else { return }
        let previous = consentStore.current()
        let changed = consentStore.update(purposes)
        let current = consentStore.current()
        pushRegistrar.retryRegistration()
        presentationEligibility.updateConsent(current)
        if changed {
            transport.sendConsent(current)
        }
        if purposes.analytics == false { eventQueue.removePurpose(.analytics); mutations.removePurpose(.analytics) }
        if purposes.feedback == false { eventQueue.removePurpose(.feedback) }
        if purposes.feedback == false {
            mutations.removePurpose(.feedback)
            pendingPromptCapIds.removeAll()
        }
        if purposes.survey == false {
            mutations.removePurpose(.survey)
            pendingSurveyCapIds.removeAll()
        }
        if (previous.analytics != true && current.analytics == true) ||
            (previous.feedback != true && current.feedback == true) {
            transport.flushIfNeeded()
        }
        if (previous.feedback != true && current.feedback == true) ||
            (previous.survey != true && current.survey == true) {
            refreshTriggers()
            emitPendingAppOpenIfReady()
        }
    }

    func reset(completion: ((Bool) -> Void)? = nil) {
        if let completion { resetCallbacks.append(completion) }
        guard !resetRunning else { return }
        resetRunning = true
        if pendingReset == nil {
            pendingReset = (subjectToken ?? secureStore.read(.subjectToken).flatMap { String(data: $0, encoding: .utf8) }, anonymousId)
        }
        resetInProgress = true
        requestsCache.clear()
        if #available(iOS 14.0, *) { RequestsBoardHost.reset() }
        presentationEligibility.invalidateIdentity()
        presentationEligibility.updateConsent(Consent())
        resetGeneration &+= 1
        sessionOpening = false
        sessionRetryScheduled = false
        notifyIdentity(.resetting)
        apiClient.cancelAll()
        apiClient.setSubjectToken(nil)
        transport.invalidate()
        if !revocations.remember(token: pendingReset?.token, anonymousId: pendingReset!.anonymousId) {
            failReset("logout cleanup could not be persisted"); return
        }
        guard self.identityStore.resetAll() else { failReset("logout identity could not be persisted"); return }
        self.userStateTracker.reset()
        self.frequencyCap.reset()
        self.eventQueue.clear()
        guard self.mutations.clear() else { failReset("logout queue could not be cleared"); return }
        let pendingCallbacks = Array(self.mutationDeliveryCallbacks.values)
        self.mutationDeliveryCallbacks.removeAll()
        DispatchQueue.main.async { pendingCallbacks.forEach { $0(false) } }
        self.rulesCache.clear()
        self.campaignRules.clear()
        self.surveyStore.clearAll()
        self.presenter.reset()
        self.inAppPresenter.reset()
        if #available(iOS 14.0, *) { SurveyHost.reset() }
        self.consentStore.clear()
        self.pushRegistrar.reset()
        guard self.secureStore.delete(.subjectToken) else { failReset("logout credential could not be cleared"); return }
        try? self.storage.deleteFile(at: self.storage.instructionStateFile)
        self.localInstructionDedupe.clear()
        self.subjectToken = nil
        self.surveyCooldownByCampaign.removeAll()
        self.pendingPromptCapIds.removeAll()
        self.pendingSurveyCapIds.removeAll()
        self.appOpenPending = false
        self.apiClient.setSubjectToken(nil)
        isFlushingMutations = false
        recoveringIdentity = false
        recoveryAttempt = nil
        let pendingIdentityCallbacks = Array(identityCallbacks.values)
        identityCallbacks.removeAll()
        let callbacks = resetCallbacks
        resetCallbacks.removeAll()
        resetInProgress = false
        resetRunning = false
        pendingReset = nil
        notifyIdentity(.anonymous)
        DispatchQueue.main.async {
            pendingIdentityCallbacks.forEach { $0(.rejected) }
            callbacks.forEach { $0(true) }
        }
        revocations.drain()
        establishSubjectSession(persistedToken: nil) { [weak self] ready in
            if ready { self?.transport.startPeriodicFlush(); self?.startAuthenticatedRuntime() }
        }
    }

    private func failReset(_ message: String) {
        logger.warn(message)
        resetRunning = false
        notifyIdentity(.resetFailed)
        let callbacks = resetCallbacks
        resetCallbacks.removeAll()
        let identities = Array(identityCallbacks.values)
        identityCallbacks.removeAll()
        let deliveries = Array(mutationDeliveryCallbacks.values)
        mutationDeliveryCallbacks.removeAll()
        DispatchQueue.main.async {
            identities.forEach { $0(.rejected) }
            deliveries.forEach { $0(false) }
            callbacks.forEach { $0(false) }
        }
    }

    func setThemeOverrides(_ theme: PromptTheme) {
        themeOverrides = theme
    }

    func flushNow() {
        transport.flushIfNeeded()
        flushMutations()
    }

    func setDebug(_ enabled: Bool) {
        logger.setDebug(enabled)
    }

    // MARK: - Surveys

    func getAvailableSurveys(completion: @escaping ([SurveySummary]) -> Void) {
        guard consentStore.allowsSurvey else {
            completion([])
            return
        }
        let identity = identityStore.current()
        apiClient.getAvailableSurveys(
            anonymousId: identity.anonymousId,
            externalId: identity.externalId,
            completion: { result in
                switch result {
                case .success(let list): completion(list)
                case .failure: completion([])
                }
            }
        )
    }

    func openSurvey(surveyId: String, language: String?, source: String) {
        guard !resetInProgress, consentStore.allowsSurvey else {
            logger.debug("openSurvey: survey consent not granted")
            return
        }
        logger.debug("survey.open requested: \(surveyId) language=\(language ?? "default") source=\(source)")
        let identity = identityStore.current()
        let isValid = presentationEligibility.validator(for: .survey)
        let beginAttempt: (SurveyCampaignWithFlow) -> Void = { [weak self] survey in
            guard let self, isValid() else { return }
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            self.apiClient.createSurveyAttempt(
                surveyId: surveyId,
                anonymousId: identity.anonymousId,
                externalId: identity.externalId,
                source: self.validSurveySource(source),
                language: language,
                appVersion: appVersion
            ) { [weak self] attemptResult in
                guard let self, isValid() else { return }
                switch attemptResult {
                case .success(let attempt):
                    let resume = self.surveyStore.upsert(
                        surveyId: surveyId,
                        attemptId: attempt.attemptId,
                        answers: attempt.progressSnapshot,
                        currentQuestionId: attempt.currentQuestionId ?? attempt.startQuestionId
                    )
                    self.presentSurveyFlow(survey: survey, attempt: resume, isValid: isValid)
                case .failure(let error):
                    self.logger.warn("survey.open: attempt creation failed (\(error))")
                }
            }
        }
        if let cached = campaignRules.survey(id: surveyId)?.survey {
            beginAttempt(cached)
            return
        }
        apiClient.getSurvey(
            surveyId: surveyId,
            anonymousId: identity.anonymousId,
            externalId: identity.externalId,
            language: language
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let survey):
                beginAttempt(survey)
            case .failure(let err):
                self.logger.warn("survey.open: flow fetch failed (\(err))")
            }
        }
    }

    private func validSurveySource(_ source: String) -> String {
        let accepted = ["triggered", "scheduled", "link", "on_demand", "test"]
        return accepted.contains(source) ? source : "on_demand"
    }

    private func presentSurveyFlow(
        survey: SurveyCampaignWithFlow,
        attempt: SurveyAttempt,
        isValid: @escaping () -> Bool
    ) {
        DispatchQueue.main.async {
            let externalHandlers = UserGist.shared.surveyHandlers
            var handlers = externalHandlers
            handlers.onShow = { [weak self] surveyId in
                self?.work { self?.recordSurveyShown(surveyId) }
                externalHandlers.onShow?(surveyId)
            }
            if #available(iOS 14.0, *) {
                SurveyHost.present(
                    flow: survey.flow,
                    surveyId: survey.id,
                    attemptId: attempt.attemptId,
                    endScreen: survey.endScreen ?? survey.flow.endScreen,
                    theme: ThemeResolver.resolve(
                        server: survey.theme,
                        override: self.themeOverrides
                    ),
                    store: self.surveyStore,
                    handlers: handlers,
                    resume: attempt,
                    logger: self.logger,
                    isValid: isValid,
                    onProgress: { [weak self] attemptId, questionId, answers in
                        self?.work {
                            self?.saveSurveyProgress(
                                attemptId: attemptId,
                                currentQuestionId: questionId,
                                answers: answers
                            )
                        }
                    },
                    onComplete: { [weak self] attemptId, answers, completion in
                        self?.work {
                            self?.completeSurvey(
                                surveyId: survey.id,
                                attemptId: attemptId,
                                answers: answers,
                                completion: completion
                            )
                        }
                    },
                    onAbandon: { [weak self] attemptId, completion in
                        self?.work {
                            self?.abandonSurvey(
                                surveyId: survey.id,
                                attemptId: attemptId,
                                completion: completion
                            )
                        }
                    }
                )
            } else {
                handlers.onShow?(survey.id)
            }
        }
    }

    private func recordSurveyShown(_ surveyId: String) {
        guard pendingSurveyCapIds.remove(surveyId) != nil else { return }
        frequencyCap.recordShown(promptId: "survey:\(surveyId)")
        surveyCooldownByCampaign[surveyId] = Date()
    }

    private func saveSurveyProgress(
        attemptId: String,
        currentQuestionId: String?,
        answers: [String: SurveyAnswerValue]
    ) {
        apiClient.updateSurveyProgress(
            attemptId: attemptId,
            currentQuestionId: currentQuestionId,
            snapshot: answers
        ) { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.warn("survey progress deferred: \(error)")
            }
        }
    }

    private func completeSurvey(
        surveyId: String,
        attemptId: String,
        answers: [String: SurveyAnswerValue],
        completion: @escaping (Bool) -> Void
    ) {
        guard !resetInProgress else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let deliveryGeneration = resetGeneration
        let finalAnswers = answers.map {
            SurveyAnswerSubmission(questionId: $0.key, value: $0.value)
        }
        let payload = SurveyCompleteMutationPayload(
            attemptId: attemptId,
            finalAnswers: finalAnswers
        )
        guard let data = try? JSONEncoder.usergist().encode(payload),
              let mutationId = mutations.enqueue(
                kind: .surveyComplete,
                purpose: .survey,
                payload: data,
                dedupeKey: "survey-complete:\(attemptId)"
              ) else {
            logger.warn("survey completion could not be persisted")
            DispatchQueue.main.async { completion(false) }
            return
        }
        mutationDeliveryCallbacks[mutationId] = { [weak self] delivered in
            guard let self else { return }
            self.work {
                // A transient failure leaves the encrypted mutation queued.
                // It is accepted only while the same reset generation remains
                // active; a reset racing delivery invalidates the completion.
                let accepted = Self.shouldAcceptSurveyCompletion(
                    delivered: delivered,
                    mutationQueued: self.mutations.contains(mutationId),
                    deliveryGeneration: deliveryGeneration,
                    currentGeneration: self.resetGeneration,
                    resetInProgress: self.resetInProgress
                )
                if accepted {
                    self.surveyStore.clear(surveyId: surveyId)
                }
                DispatchQueue.main.async {
                    if accepted {
                        UserGist.shared.surveyHandlers.onComplete?(surveyId, attemptId)
                    }
                    completion(accepted)
                }
            }
        }
        flushMutations()
        if !isFlushingMutations {
            resolveMutationDelivery(mutationId, delivered: false)
        }
    }

    static func shouldAcceptSurveyCompletion(
        delivered: Bool,
        mutationQueued: Bool,
        deliveryGeneration: UInt64,
        currentGeneration: UInt64,
        resetInProgress: Bool
    ) -> Bool {
        !resetInProgress &&
            deliveryGeneration == currentGeneration &&
            (delivered || mutationQueued)
    }

    private func abandonSurvey(
        surveyId: String,
        attemptId: String,
        completion: @escaping (Bool) -> Void
    ) {
        let payload = SurveyAbandonMutationPayload(attemptId: attemptId)
        guard let data = try? JSONEncoder.usergist().encode(payload),
              mutations.enqueue(
                kind: .surveyAbandon,
                purpose: .survey,
                payload: data,
                dedupeKey: "survey-abandon:\(attemptId)"
              ) != nil else {
            logger.warn("survey abandon could not be persisted")
            DispatchQueue.main.async { completion(false) }
            return
        }
        surveyStore.clear(surveyId: surveyId)
        DispatchQueue.main.async { completion(true) }
        flushMutations()
    }

    func resolveSurveyLink(token: String) {
        guard consentStore.allowsSurvey else {
            logger.debug("resolveSurveyLink: survey consent not granted")
            return
        }
        let identity = identityStore.current()
        apiClient.resolveSurveyLink(
            token: token,
            anonymousId: identity.anonymousId,
            externalId: identity.externalId
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let resolved):
                guard !resolved.consentRequired else {
                    self.logger.debug("survey link resolved but survey consent is required")
                    return
                }
                self.work {
                    self.openSurvey(surveyId: resolved.surveyId, language: nil, source: "link")
                }
            case .failure(let err):
                self.logger.warn("resolveSurveyLink failed: \(err)")
            }
        }
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

    private func scheduleMutationFlush() {
        mutationFlushTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(
            deadline: .now() + config.flushInterval,
            repeating: config.flushInterval
        )
        timer.setEventHandler { [weak self] in self?.flushMutations() }
        timer.resume()
        mutationFlushTimer = timer
    }

    private func flushMutations() {
        guard !resetInProgress, !isFlushingMutations, let mutation = mutations.first else { return }
        if mutation.kind == .identify && subjectToken == nil && externalId == nil { return }
        let consent = consentStore.current()
        if mutation.purpose == .analytics && consent.analytics != true { return }
        if mutation.purpose == .feedback && consent.feedback != true { return }
        if mutation.purpose == .survey && consent.survey != true { return }
        let generation = resetGeneration
        isFlushingMutations = true
        if consent.analytics == true && (mutation.kind == .identify || mutation.kind == .userProperties) {
            let override = externalId != nil && mutation.kind == .identify
                ? (try? JSONDecoder.usergist().decode(IdentifyMutationPayload.self, from: mutation.payload))?.subjectToken : nil
            transport.sendConsent(consent, subjectTokenOverride: override) { [weak self] result in
                guard let self, generation == self.resetGeneration, !self.resetInProgress else { return }
                if case .failure = result { self.finishMutation(mutation, result: result, generation: generation); return }
                self.deliverMutation(mutation, generation: generation)
            }
        } else {
            deliverMutation(mutation, generation: generation)
        }
    }

    private func deliverMutation(_ mutation: PendingMutation, generation: UInt64) {
        guard mutation.purpose != .analytics || consentStore.current().analytics == true else {
            finishMutation(mutation, result: .failure(.server(status: 403, body: Data("Analytics consent withdrawn".utf8))), generation: generation)
            return
        }
        switch mutation.kind {
        case .identify:
            guard let payload = try? JSONDecoder.usergist().decode(
                IdentifyMutationPayload.self,
                from: mutation.payload
            ), payload.subjectToken.hasPrefix("st_") else {
                _ = mutations.remove(mutation.id)
                isFlushingMutations = false
                flushMutations()
                return
            }
            apiClient.postJSON(
                path: SDKEndpoint.identify,
                body: IdentifyPayload(
                    previousSubjectToken: subjectToken,
                    anonymousId: payload.anonymousId,
                    externalId: payload.externalId,
                    properties: consentStore.current().analytics == true ? payload.properties : nil
                ),
                responseType: IdentifiedSessionResponse.self,
                subjectTokenOverride: payload.subjectToken
            ) { [weak self] result in
                guard let self else { return }
                self.work {
                    guard generation == self.resetGeneration, !self.resetInProgress else {
                        self.isFlushingMutations = false
                        return
                    }
                    switch result {
                    case .success(let accepted):
                        let sessionToken = accepted.subjectToken ?? payload.subjectToken
                        guard self.secureStore.write(
                            .subjectToken,
                            Data(sessionToken.utf8)
                        ) else {
                            self.isFlushingMutations = false
                            if let callback = self.identityCallbacks.removeValue(forKey: mutation.id) {
                                DispatchQueue.main.async { callback(.queued) }
                            }
                            return
                        }
                        self.subjectToken = sessionToken
                        self.apiClient.setSubjectToken(sessionToken)
                        if self.identityStore.current().externalId != payload.externalId {
                            self.presentationEligibility.invalidateIdentity()
                            self.pendingPromptCapIds.removeAll()
                            self.pendingSurveyCapIds.removeAll()
                        }
                        guard self.identityStore.setExternalId(payload.externalId) else {
                            self.isFlushingMutations = false
                            if let callback = self.identityCallbacks.removeValue(forKey: mutation.id) {
                                DispatchQueue.main.async { callback(.queued) }
                            }
                            self.notifyIdentity(.authenticationRequired)
                            return
                        }
                        self.notifyIdentity(.identified)
                        let supplied = payload.properties?.mapValues(\.value)
                        let clean = accepted.filteredKeys.map { keys in supplied?.filter { !keys.contains($0.key) } }
                            ?? AnyCodable.wrapEventProperties(supplied)?.mapValues(\.value)
                        let stored = self.identityStore.mergeProperties(accepted.properties?.mapValues(\.value) ?? clean, replace: accepted.properties != nil)
                        self.userStateTracker.setPersistedProperties(stored)
                        self.pushRegistrar.retryRegistration()
                        self.startAuthenticatedRuntime()
                        if self.consentStore.current().analytics == true {
                            self.track(
                                eventName: "$identify",
                                properties: clean,
                                purpose: .analytics
                            )
                        }
                        self.finishMutation(mutation, result: result.map { _ in () }, generation: generation)
                    case .failure:
                        self.finishMutation(mutation, result: result.map { _ in () }, generation: generation)
                    }
                }
            }
        case .userProperties:
            guard let payload = try? JSONDecoder.usergist().decode(UserPropertiesPayload.self, from: mutation.payload) else {
                _ = mutations.remove(mutation.id); isFlushingMutations = false; return
            }
            apiClient.postJSON(path: "/v1/sdk/user-properties", body: payload, responseType: UserPropertiesResponse.self) { [weak self] result in
                self?.work {
                    guard let self, generation == self.resetGeneration, !self.resetInProgress else { return }
                    if case .success(let response) = result {
                        let values = payload.set.filter { !response.filteredKeys.contains($0.key) }.mapValues(\.value)
                        let stored = self.identityStore.mergeProperties(values, unset: payload.unset)
                        self.userStateTracker.setPersistedProperties(stored)
                    }
                    self.finishMutation(mutation, result: result.map { _ in () }, generation: generation)
                }
            }
        case .feedbackResponse:
            guard let payload = try? JSONDecoder.usergist().decode(
                SubmitResponsePayload.self,
                from: mutation.payload
            ) else {
                _ = mutations.remove(mutation.id)
                isFlushingMutations = false
                flushMutations()
                return
            }
            apiClient.postVoid(path: SDKEndpoint.responses, body: payload) { [weak self] result in
                self?.work {
                    self?.finishMutation(mutation, result: result, generation: generation)
                }
            }
        case .surveyComplete:
            guard let payload = try? JSONDecoder.usergist().decode(
                SurveyCompleteMutationPayload.self,
                from: mutation.payload
            ) else {
                _ = mutations.remove(mutation.id)
                isFlushingMutations = false
                flushMutations()
                return
            }
            apiClient.postVoid(
                path: SDKEndpoint.surveyComplete(payload.attemptId),
                body: SurveyCompleteBody(finalAnswers: payload.finalAnswers)
            ) { [weak self] result in
                self?.work {
                    self?.finishMutation(mutation, result: result, generation: generation)
                }
            }
        case .surveyAbandon:
            guard let payload = try? JSONDecoder.usergist().decode(
                SurveyAbandonMutationPayload.self,
                from: mutation.payload
            ) else {
                _ = mutations.remove(mutation.id)
                isFlushingMutations = false
                flushMutations()
                return
            }
            apiClient.postVoid(
                path: SDKEndpoint.surveyAbandon(payload.attemptId),
                body: EmptyResponse()
            ) { [weak self] result in
                self?.work {
                    self?.finishMutation(mutation, result: result, generation: generation)
                }
            }
        }
    }

    private func finishMutation(
        _ mutation: PendingMutation,
        result: Result<Void, APIClient.APIError>,
        generation: UInt64
    ) {
        guard generation == resetGeneration, !resetInProgress else {
            isFlushingMutations = false
            return
        }
        isFlushingMutations = false
        if mutation.kind == .identify, case .failure(.server(let status, _)) = result, status == 401 { notifyIdentity(.authenticationRequired) }
        if let callback = identityCallbacks.removeValue(forKey: mutation.id) {
            let status: IdentifyResult
            switch result {
            case .success: status = .synced
            case .failure(.server(let code, _)) where (400..<500).contains(code) && code != 429 && code != 401: status = .rejected
            default: status = .queued
            }
            DispatchQueue.main.async { callback(status) }
        }
        switch result {
        case .success:
            if mutations.remove(mutation.id) {
                resolveMutationDelivery(mutation.id, delivered: true)
                flushMutations()
            } else {
                resolveMutationDelivery(mutation.id, delivered: false)
            }
        case .failure(.server(let status, _))
            where (400..<500).contains(status) && status != 429 && status != 401:
            _ = mutations.remove(mutation.id)
            if mutation.kind == .identify { notifyIdentity(.rejected) }
            resolveMutationDelivery(mutation.id, delivered: false)
            failPendingMutationDeliveries()
            logger.warn("quarantined permanently rejected \(mutation.kind.rawValue) mutation")
        case .failure(let error):
            resolveMutationDelivery(mutation.id, delivered: false)
            failPendingMutationDeliveries()
            logger.warn("mutation delivery deferred: \(error)")
        }
    }

    private func resolveMutationDelivery(_ id: String, delivered: Bool) {
        guard let callback = mutationDeliveryCallbacks.removeValue(forKey: id) else { return }
        DispatchQueue.main.async { callback(delivered) }
    }

    private func failPendingMutationDeliveries() {
        let callbacks = mutationDeliveryCallbacks.values
        mutationDeliveryCallbacks.removeAll()
        let identities = Array(identityCallbacks.values)
        identityCallbacks.removeAll()
        let deliveries = Array(mutationDeliveryCallbacks.values)
        mutationDeliveryCallbacks.removeAll()
        DispatchQueue.main.async {
            identities.forEach { $0(.rejected) }
            deliveries.forEach { $0(false) }
            callbacks.forEach { $0(false) }
        }
    }

    private func refreshTriggersIfStale() {
        let stale: Bool = {
            guard let last = lastTriggerSync else { return true }
            return Date().timeIntervalSince(last) > config.triggerSyncInterval
        }()
        if stale { refreshTriggers() }
    }

    private func requestAppOpen() {
        guard consentStore.current().feedback == true else {
            appOpenPending = true
            return
        }
        appOpenPending = false
        track(eventName: "$app_open", properties: nil, purpose: .feedback)
    }

    private func emitPendingAppOpenIfReady() {
        guard appOpenPending, consentStore.current().feedback == true else { return }
        appOpenPending = false
        track(eventName: "$app_open", properties: nil, purpose: .feedback)
    }

    private func refreshTriggers() {
        let consent = consentStore.current()
        let wantsFeedback = consent.feedback == true
        let wantsSurvey = consent.survey == true
        guard wantsFeedback || wantsSurvey else {
            logger.debug("trigger refresh skipped: consent gate")
            return
        }
        guard !isRefreshingTriggers else { return }
        isRefreshingTriggers = true

        let identity = identityStore.current()
        let query = [
            URLQueryItem(name: "anonymousId", value: identity.anonymousId),
            URLQueryItem(name: "externalId", value: identity.externalId)
        ]
        var remaining = (wantsFeedback ? 2 : 0) + (wantsSurvey ? 1 : 0)
        var anySucceeded = false
        let finishOne: (Bool) -> Void = { [weak self] succeeded in
            guard let self else { return }
            self.work {
                anySucceeded = anySucceeded || succeeded
                remaining -= 1
                guard remaining == 0 else { return }
                self.isRefreshingTriggers = false
                if anySucceeded { self.lastTriggerSync = Date() }
                let windows = UserStateTracker.windows(from: self.rulesCache.snapshot())
                    .union(UserStateTracker.windows(from: self.campaignRules.surveySnapshot()))
                self.userStateTracker.setKnownWindows(windows)
            }
        }

        if wantsFeedback {
            transport.fetchArmedTriggers(
                anonymousId: identity.anonymousId,
                externalId: identity.externalId
            ) { [weak self] result in
                switch result {
                case .success(let response):
                    self?.rulesCache.replace(response.triggers)
                    self?.logger.debug("armed triggers refreshed: \(response.triggers.count)")
                    finishOne(true)
                case .failure(let error):
                    self?.logger.warn("armed triggers refresh failed: \(error)")
                    finishOne(false)
                }
            }
            apiClient.get(
                path: SDKEndpoint.armedInAppMessages,
                query: query,
                responseType: ArmedInAppMessagesResponse.self
            ) { [weak self] result in
                switch result {
                case .success(let response):
                    self?.campaignRules.replace(response)
                    finishOne(true)
                case .failure(let error):
                    self?.logger.warn("armed in-app refresh failed: \(error)")
                    finishOne(false)
                }
            }
        }
        if wantsSurvey {
            apiClient.get(
                path: SDKEndpoint.armedSurveys,
                query: query,
                responseType: ArmedSurveysResponse.self
            ) { [weak self] result in
                switch result {
                case .success(let response):
                    self?.campaignRules.replace(response)
                    finishOne(true)
                case .failure(let error):
                    self?.logger.warn("armed survey refresh failed: \(error)")
                    finishOne(false)
                }
            }
        }
    }

    private func evaluateCampaigns(eventName: String, eventId: String) {
        let consent = consentStore.current()
        let user = userStateTracker.snapshot()

        if consent.survey == true {
            for armed in campaignRules.surveys(for: eventName) {
                if armed.clientSideEligible == false { continue }
                if !SegmentEvaluator.evaluate(armed.segmentRules, user: user) { continue }
                let caps = FrequencyCaps(
                    perPromptDays: armed.frequencyCap.perCampaignDays,
                    perUserDays: armed.frequencyCap.perPillarDays
                )
                let capKey = "survey:\(armed.campaignId)"
                if !frequencyCap.canShow(promptId: capKey, caps: caps) { continue }
                if pendingSurveyCapIds.contains(armed.campaignId) { continue }
                let now = Date()
                if let seconds = armed.cooldownSeconds,
                   seconds > 0,
                   let last = surveyCooldownByCampaign[armed.campaignId],
                   now.timeIntervalSince(last) < Double(seconds) {
                    continue
                }
                pendingSurveyCapIds.insert(armed.campaignId)
                rememberLocalInstruction(
                    type: "survey.offer",
                    refId: armed.campaignId,
                    eventId: eventId
                )
                let summary = SurveySummary(
                    id: armed.campaignId,
                    name: armed.survey.name,
                    mode: "triggered",
                    source: "triggered"
                )
                if let onInvite = UserGist.shared.surveyHandlers.onInvite {
                    DispatchQueue.main.async { onInvite(summary) }
                } else {
                    openSurvey(
                        surveyId: armed.campaignId,
                        language: nil,
                        source: "triggered"
                    )
                }
                break
            }
        }

        if consent.feedback == true {
            for message in campaignRules.inApp(for: eventName) {
                if message.clientSideEligible == false { continue }
                rememberLocalInstruction(
                    type: "inapp.show",
                    refId: message.messageId,
                    eventId: eventId
                )
                presentInApp(message)
                break
            }
        }
    }

    // MARK: - Durable instruction inbox

    private func pollInstructions() {
        guard subjectToken != nil, !resetInProgress else { return }
        guard !isPollingInstructions else {
            instructionPollRequested = true
            return
        }
        isPollingInstructions = true
        let generation = resetGeneration
        let stored = ((try? storage.readJSON(
            InstructionState.self,
            at: storage.instructionStateFile
        )) ?? nil) ?? InstructionState(cursor: 0, seen: [])
        apiClient.get(
            path: SDKEndpoint.instructions,
            query: [
                URLQueryItem(name: "after", value: String(stored.cursor)),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "protocolVersion", value: "2"),
                URLQueryItem(name: "platform", value: "ios"),
                URLQueryItem(name: "anonymousId", value: identityStore.anonymousId)
            ],
            responseType: InstructionEnvelope.self
        ) { [weak self] result in
            guard let self else { return }
            self.work {
                guard generation == self.resetGeneration, !self.resetInProgress else {
                    self.finishInstructionPoll()
                    return
                }
                switch result {
                case .failure(let error):
                    self.finishInstructionPoll()
                    self.logger.warn("instruction poll failed: \(error)")
                case .success(let envelope):
                    self.handleInstructions(envelope.instructions, stored: stored)
                }
            }
        }
    }

    private func handleInstructions(_ instructions: [SDKInstruction], stored: InstructionState) {
        guard !instructions.isEmpty else {
            finishInstructionPoll()
            return
        }
        var seen = stored.seen
        var seenSet = Set(seen)
        var handled: [Int] = []
        do {
            for instruction in instructions where instruction.id > 0 {
                handled.append(instruction.id)
                guard !seenSet.contains(instruction.id) else { continue }
                dispatchInstruction(instruction)
                seen.append(instruction.id)
                seenSet.insert(instruction.id)
                if seen.count > 200 {
                    seen.removeFirst(seen.count - 200)
                    seenSet = Set(seen)
                }
                try storage.writeJSON(
                    InstructionState(cursor: stored.cursor, seen: seen),
                    to: storage.instructionStateFile
                )
            }
            guard !handled.isEmpty else {
                finishInstructionPoll()
                return
            }
            let cursor = max(stored.cursor, handled.max() ?? stored.cursor)
            try storage.writeJSON(
                InstructionState(cursor: cursor, seen: seen),
                to: storage.instructionStateFile
            )
            apiClient.postJSON(
                path: SDKEndpoint.instructionsAck,
                body: InstructionAck(ids: handled),
                responseType: InstructionAckResponse.self
            ) { [weak self] result in
                guard let self else { return }
                self.work {
                    self.finishInstructionPoll()
                    if case .failure(let error) = result {
                        self.logger.warn("instruction acknowledgement failed: \(error)")
                    }
                }
            }
        } catch {
            finishInstructionPoll()
            logger.error("instruction state persistence failed", error: error)
        }
    }

    private func finishInstructionPoll() {
        isPollingInstructions = false
        if instructionPollRequested {
            instructionPollRequested = false
            pollInstructions()
        }
    }

    private func dispatchInstruction(_ instruction: SDKInstruction) {
        switch instruction.type {
        case "prompt.show":
            guard consentStore.current().feedback == true,
                  let promptId = instruction.payload["promptId"]?.value as? String,
                  let promptValue = instruction.payload["prompt"]?.value,
                  JSONSerialization.isValidJSONObject(promptValue),
                  let data = try? JSONSerialization.data(withJSONObject: promptValue),
                  let prompt = try? JSONDecoder.usergist().decode(ClientPrompt.self, from: data)
            else { return }
            if let triggerEventId = instruction.payload["triggerEventId"]?.value as? String,
               consumeLocalInstruction(
                type: instruction.type,
                refId: promptId,
                eventId: triggerEventId
               ) {
                return
            }
            firePrompt(for: ArmedTrigger(
                promptId: promptId,
                eventName: "server",
                segmentRules: nil,
                clientSideEligible: nil,
                frequency: FrequencyCaps(perPromptDays: nil, perUserDays: nil),
                prompt: prompt
            ))
        case "survey.offer":
            guard consentStore.current().allowsSurvey,
                  let surveyId = instruction.payload["surveyId"]?.value as? String
            else { return }
            if let triggerEventId = instruction.payload["triggerEventId"]?.value as? String,
               consumeLocalInstruction(
                type: instruction.type,
                refId: surveyId,
                eventId: triggerEventId
               ) {
                return
            }
            let name = instruction.payload["name"]?.value as? String ?? ""
            let source = instruction.payload["source"]?.value as? String ?? "triggered"
            let summary = SurveySummary(
                id: surveyId,
                name: name,
                mode: "triggered",
                source: source
            )
            if let onInvite = UserGist.shared.surveyHandlers.onInvite {
                DispatchQueue.main.async { onInvite(summary) }
            } else {
                openSurvey(surveyId: surveyId, language: nil, source: source)
            }
        case "inapp.show":
            guard consentStore.current().feedback == true,
                  let rawMessage = instruction.payload["message"]?.value,
                  JSONSerialization.isValidJSONObject(rawMessage),
                  let data = try? JSONSerialization.data(withJSONObject: rawMessage),
                  let message = try? JSONDecoder.usergist().decode(
                    ArmedInAppMessage.self,
                    from: data
                  ),
                  !message.messageId.isEmpty,
                  !message.title.isEmpty
            else { return }
            if let triggerEventId = instruction.payload["triggerEventId"]?.value as? String,
               consumeLocalInstruction(
                type: instruction.type,
                refId: message.messageId,
                eventId: triggerEventId
               ) {
                return
            }
            presentInApp(message)
        default:
            if instruction.type.hasPrefix("request.") {
                UserGist.shared.push.emitSDKEvent(
                    name: "$\(instruction.type.replacingOccurrences(of: ".", with: "_"))",
                    properties: instruction.payload.mapValues(\.value)
                )
            }
        }
    }

    private func instructionKey(type: String, refId: String, eventId: String) -> String {
        "\(type):\(refId):event:\(eventId)"
    }

    private func rememberLocalInstruction(type: String, refId: String, eventId: String) {
        localInstructionDedupe.remember(
            instructionKey(type: type, refId: refId, eventId: eventId)
        )
    }

    private func consumeLocalInstruction(type: String, refId: String, eventId: String) -> Bool {
        localInstructionDedupe.consume(
            instructionKey(type: type, refId: refId, eventId: eventId)
        )
    }

    // MARK: - In-app presentation

    private func presentInApp(_ message: ArmedInAppMessage) {
        guard !resetInProgress else { return }
        let isValid = presentationEligibility.validator(for: .feedback)
        let serverTheme = PromptTheme(
            colors: .init(
                primary: message.accentColor,
                background: message.backgroundColor
            )
        )
        let resolved = ThemeResolver.resolve(server: serverTheme, override: themeOverrides)
        inAppPresenter.present(
            message: message,
            theme: resolved,
            isValid: isValid,
            onShown: { [weak self] in
                guard let self else { return }
                self.work {
                    self.track(
                        eventName: "$inapp_shown",
                        properties: ["message_id": message.messageId],
                        purpose: .feedback
                    )
                }
                DispatchQueue.main.async {
                    UserGist.shared.inAppHandlers.onShow?(message.messageId)
                }
            },
            onDismiss: { [weak self] reason in
                guard let self else { return }
                self.work {
                    self.track(
                        eventName: reason == .auto
                            ? "$inapp_auto_dismissed"
                            : "$inapp_dismissed",
                        properties: ["message_id": message.messageId],
                        purpose: .feedback
                    )
                }
                DispatchQueue.main.async {
                    UserGist.shared.inAppHandlers.onDismiss?(message.messageId, reason)
                }
            },
            onCta: { [weak self] cta, index in
                guard let self else { return }
                self.work {
                    self.track(
                        eventName: "$inapp_cta_clicked",
                        properties: [
                            "message_id": message.messageId,
                            "cta_index": index,
                            "cta_action": cta.action.rawValue,
                            "cta_label": cta.label
                        ],
                        purpose: .feedback
                    )
                    if cta.action == .customEvent,
                       let target = cta.target,
                       !target.isEmpty {
                        self.track(
                            eventName: target,
                            properties: [
                                "message_id": message.messageId,
                                "cta_index": index,
                                "cta_label": cta.label
                            ],
                            purpose: .feedback
                        )
                    }
                }
                DispatchQueue.main.async {
                    let click = InAppCtaClick(
                        messageId: message.messageId,
                        action: cta.action,
                        target: cta.target,
                        label: cta.label,
                        index: index,
                        actionJson: cta.actionJson
                    )
                    UserGist.shared.inAppHandlers.onCtaClick?(click)
                    if cta.action == .json, let actionJson = cta.actionJson {
                        UserGist.shared.inAppHandlers.onJsonAction?(actionJson, click)
                    }
                    if (cta.action == .openURL || cta.action == .deepLink),
                       let target = cta.target,
                       let url = URL(string: target),
                       url.scheme != nil {
                        UIApplication.shared.open(url)
                    }
                }
            }
        )
    }

    // MARK: - Prompt firing

    private func firePrompt(for trigger: ArmedTrigger) {
        guard !resetInProgress else { return }
        let isValid = presentationEligibility.validator(for: .feedback)
        guard pendingPromptCapIds.insert(trigger.promptId).inserted else { return }
        let resolvedTheme = ThemeResolver.resolve(
            server: trigger.prompt.theme,
            override: themeOverrides
        )
        let promptId = trigger.promptId

        // Callback on main queue after presenter work completes.
        let onShown: () -> Void = { [weak self] in
            guard let self else { return }
            // Emit shown callback outside the work queue to avoid re-entrancy.
            DispatchQueue.main.async {
                UserGist.shared.onPromptShown?(promptId)
            }
            // Record `$feedback_prompt_shown` as a first-class event.
            self.work {
                self.pendingPromptCapIds.remove(promptId)
                self.frequencyCap.recordShown(promptId: promptId)
                self.track(
                    eventName: "$feedback_prompt_shown",
                    properties: ["promptId": promptId],
                    purpose: .feedback
                )
            }
        }

        let onFinish: (PromptResponseInfo) -> Void = { [weak self] info in
            guard let self else { return }
            self.work {
                self.handleResponse(info: info)
            }
            DispatchQueue.main.async {
                UserGist.shared.onResponse?(info)
            }
        }

        presenter.present(
            context: .init(prompt: trigger.prompt, theme: resolvedTheme),
            isValid: isValid,
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
            idempotencyKey: UUID().uuidString,
            promptId: info.promptId,
            anonymousId: identity.anonymousId,
            externalId: identity.externalId,
            answers: info.dismissed ? nil : wireAnswers,
            dismissed: info.dismissed,
            latencyMs: info.latencyMs
        )
        if let data = try? JSONEncoder.usergist().encode(payload),
           mutations.enqueue(
            kind: .feedbackResponse,
            purpose: .feedback,
            payload: data
           ) != nil {
            flushMutations()
        } else {
            logger.warn("feedback response could not be persisted")
        }
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
        track(eventName: "$feedback_response", properties: props, purpose: .feedback)
    }
}

private struct SubjectSessionRequest: Encodable {
    let anonymousId: String
}

private struct SubjectSessionResponse: Decodable {
    let subjectToken: String
    let subjectId: String
    let expiresAt: Date
}

private struct SDKInstruction: Decodable {
    let id: Int
    let type: String
    let payload: [String: AnyCodable]
    let emittedAt: Date?
    let expiresAt: Date?
}

private struct InstructionEnvelope: Decodable {
    let instructions: [SDKInstruction]
}

private struct InstructionState: Codable {
    let cursor: Int
    let seen: [Int]
}

private struct InstructionAck: Encodable {
    let ids: [Int]
}

private struct InstructionAckResponse: Decodable {
    let acknowledged: Int
}

private struct IdentifyMutationPayload: Codable {
    let subjectToken: String
    let anonymousId: String
    let externalId: String
    let properties: [String: AnyCodable]?
}

private struct SurveyAnswerSubmission: Codable {
    let questionId: String
    let value: SurveyAnswerValue
}

private struct SurveyCompleteMutationPayload: Codable {
    let attemptId: String
    let finalAnswers: [SurveyAnswerSubmission]
}

private struct SurveyCompleteBody: Encodable {
    let finalAnswers: [SurveyAnswerSubmission]
}

private struct SurveyAbandonMutationPayload: Codable {
    let attemptId: String
}

private struct UserPropertiesPayload: Codable {
    let anonymousId: String
    let mutationId: String
    let set: [String: AnyCodable]
    let unset: [String]
}
private struct UserPropertiesResponse: Decodable {
    let applied: Bool
    let filteredKeys: [String]
}

private struct IdentifiedSessionResponse: Decodable {
    let subjectToken: String?
    let expiresAt: Date?
    let filteredKeys: [String]?
    let properties: [String: AnyCodable]?
}
