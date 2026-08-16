import Foundation

/// Decides whether a given event should fire a prompt.
///
/// Evaluation order matches DEV_PRD §6:
///   1. consent gate
///   2. event-name lookup against armed triggers
///   3. segment rules (client-side, pure function)
///   4. per-prompt frequency caps
///   5. per-user frequency caps
///
/// Returns the first matching trigger or `nil`.
final class TriggerMatcher {
    private let rulesCache: RulesCache
    private let frequencyCap: FrequencyCapStore
    private let consent: ConsentStore
    private let logger: UserGistLogger
    private let userState: () -> UserState

    init(
        rulesCache: RulesCache,
        frequencyCap: FrequencyCapStore,
        consent: ConsentStore,
        logger: UserGistLogger,
        userState: @escaping () -> UserState
    ) {
        self.rulesCache = rulesCache
        self.frequencyCap = frequencyCap
        self.consent = consent
        self.logger = logger
        self.userState = userState
    }

    func match(eventName: String) -> ArmedTrigger? {
        guard consent.allowsTransport else {
            logger.debug("trigger[\(eventName)] suppressed: consent gate")
            return nil
        }
        let candidates = rulesCache.triggers(for: eventName)
        if candidates.isEmpty { return nil }
        let user = userState()
        for trigger in candidates {
            if !SegmentEvaluator.evaluate(trigger.segmentRules, user: user) {
                logger.debug("trigger[\(trigger.promptId)] suppressed: segment miss")
                continue
            }
            if !frequencyCap.canShow(promptId: trigger.promptId, caps: trigger.frequency) {
                logger.debug("trigger[\(trigger.promptId)] suppressed: frequency cap")
                continue
            }
            logger.debug("trigger[\(trigger.promptId)] matched for event=\(eventName)")
            return trigger
        }
        return nil
    }
}
