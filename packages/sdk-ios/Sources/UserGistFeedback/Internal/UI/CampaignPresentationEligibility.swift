import Foundation

/// A thread-safe validity ticket crosses the runtime queue → UIKit boundary.
/// Revoking consent or changing subjects permanently invalidates queued work,
/// even if consent is granted again before the host resumes presentation.
final class CampaignPresentationEligibility {
    enum Purpose { case feedback, survey }
    private let lock = NSLock()
    private var identity = UUID()
    private var feedback = UUID()
    private var survey = UUID()
    private var feedbackAllowed = false
    private var surveyAllowed = false

    func updateConsent(_ consent: Consent) {
        lock.lock()
        defer { lock.unlock() }
        if feedbackAllowed && consent.feedback != true { feedback = UUID() }
        if surveyAllowed && consent.survey != true { survey = UUID() }
        feedbackAllowed = consent.feedback == true
        surveyAllowed = consent.survey == true
    }

    func invalidateIdentity() {
        lock.lock()
        identity = UUID()
        lock.unlock()
    }

    func validator(for purpose: Purpose) -> () -> Bool {
        lock.lock()
        let capturedIdentity = identity
        let capturedPurpose = purpose == .survey ? survey : feedback
        let capturedAllowed = purpose == .survey ? surveyAllowed : feedbackAllowed
        lock.unlock()
        return { [weak self] in
            guard let self else { return false }
            self.lock.lock()
            defer { self.lock.unlock() }
            let allowed = purpose == .survey ? self.surveyAllowed : self.feedbackAllowed
            let current = purpose == .survey ? self.survey : self.feedback
            return capturedAllowed && allowed && self.identity == capturedIdentity && current == capturedPurpose
        }
    }
}
