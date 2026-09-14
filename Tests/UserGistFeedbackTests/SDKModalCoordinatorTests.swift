import XCTest
import UIKit
@testable import UserGistFeedback

@MainActor
final class SDKModalCoordinatorTests: XCTestCase {
    func testStartupGateLetsHostNavigationFinishBeforeCampaignsAndResumesOnce() async {
        let coordinator = SDKModalCoordinator()
        let owner = NSObject()
        coordinator.setPaused(true)
        var hostReady = false
        var presentations: [String] = []
        var release: (() -> Void)?
        for kind in ["feedback", "survey", "inapp"] {
            coordinator.enqueue(owner: owner) { finish in
                XCTAssertTrue(hostReady, "Campaign interrupted startup navigation")
                presentations.append(kind)
                release = finish
                return true
            }
        }
        await settle()
        XCTAssertTrue(presentations.isEmpty)
        hostReady = true
        coordinator.setPaused(false)
        coordinator.setPaused(false)
        await settle()
        XCTAssertEqual(presentations, ["feedback"])
        release?()
        release?() // duplicate completion must not release the next modal
        await settle()
        XCTAssertEqual(presentations, ["feedback", "survey"])
        release?()
        await settle()
        XCTAssertEqual(presentations, ["feedback", "survey", "inapp"])
        release?()
    }

    func testPausingVisibleCampaignDefersTheNextWithoutDismissingCurrent() async {
        let coordinator = SDKModalCoordinator()
        let owner = NSObject()
        var shown = 0
        var release: (() -> Void)?
        for _ in 0..<2 {
            coordinator.enqueue(owner: owner) { finish in
                shown += 1
                release = finish
                return true
            }
        }
        await settle()
        coordinator.setPaused(true)
        XCTAssertEqual(shown, 1)
        release?()
        await settle()
        XCTAssertEqual(shown, 1)
        coordinator.setPaused(false)
        await settle()
        XCTAssertEqual(shown, 2)
        release?()
    }

    func testTransitionRetriesWithoutAnotherAppOpen() async {
        let coordinator = SDKModalCoordinator()
        let owner = NSObject()
        var transitioning = true
        var shown = 0
        coordinator.enqueue(owner: owner) { release in
            guard !transitioning else { return false }
            shown += 1
            release()
            return true
        }
        await settle()
        XCTAssertEqual(shown, 0)
        transitioning = false
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(shown, 1)
    }

    func testRevocationAndAccountChangeDiscardQueuedCampaigns() async {
        let coordinator = SDKModalCoordinator()
        let eligibility = CampaignPresentationEligibility()
        let owner = NSObject()
        coordinator.setPaused(true)
        eligibility.updateConsent(Consent(feedback: true, survey: true))
        var shown: [String] = []
        coordinator.enqueue(owner: owner, isValid: eligibility.validator(for: .feedback)) { release in
            shown.append("revoked")
            release()
            return true
        }
        eligibility.updateConsent(Consent(feedback: false, survey: true))
        eligibility.updateConsent(Consent(feedback: true, survey: true))
        coordinator.enqueue(owner: owner, isValid: eligibility.validator(for: .survey)) { release in
            shown.append("old-user")
            release()
            return true
        }
        eligibility.invalidateIdentity()
        coordinator.enqueue(owner: owner, isValid: eligibility.validator(for: .survey)) { release in
            shown.append("current-user")
            release()
            return true
        }
        coordinator.setPaused(false)
        await settle()
        XCTAssertEqual(shown, ["current-user"])
    }

    func testConsentChangesOnlyInvalidateTheirOwnPurpose() {
        let eligibility = CampaignPresentationEligibility()
        let beforeConsent = eligibility.validator(for: .feedback)
        eligibility.updateConsent(Consent(analytics: true, feedback: true, survey: true))
        let feedback = eligibility.validator(for: .feedback)
        let survey = eligibility.validator(for: .survey)
        eligibility.updateConsent(Consent(analytics: false, feedback: true, survey: false))
        XCTAssertFalse(beforeConsent())
        XCTAssertTrue(feedback())
        XCTAssertFalse(survey())
    }

    func testCancellationWhilePausedNeverPresents() async {
        let coordinator = SDKModalCoordinator()
        let owner = NSObject()
        coordinator.setPaused(true)
        coordinator.enqueue(owner: owner) { _ in
            XCTFail("Cancelled campaign presented")
            return true
        }
        coordinator.cancelPending(owner: owner)
        await settle()
        coordinator.setPaused(false)
        await settle()
    }

    func testRepeatedTriggersWhilePausedAndVisibleDoNotDuplicateCampaign() async {
        let coordinator = SDKModalCoordinator()
        let owner = NSObject()
        coordinator.setPaused(true)
        var shown = 0
        var finish: (() -> Void)?
        let enqueue = {
            coordinator.enqueue(owner: owner, key: "campaign") { release in
                shown += 1
                finish = release
                return true
            }
        }
        enqueue()
        enqueue()
        coordinator.setPaused(false)
        await settle()
        enqueue()
        await settle()
        finish?()
        await settle()
        XCTAssertEqual(shown, 1)
        // A genuinely later trigger can show again, subject to runtime caps.
        enqueue()
        await settle()
        XCTAssertEqual(shown, 2)
        finish?()
    }

    func testLocatorRejectsDetachedAndTransitioningControllers() {
        let controller = TransitioningController()
        XCTAssertNil(TopViewControllerLocator.presentableController(from: controller))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        XCTAssertTrue(TopViewControllerLocator.presentableController(from: controller) === controller)
        controller.dismissing = true
        XCTAssertNil(TopViewControllerLocator.presentableController(from: controller))
        controller.dismissing = false
        controller.presenting = true
        XCTAssertNil(TopViewControllerLocator.presentableController(from: controller))
        window.isHidden = true
    }

    private func settle() async {
        // Drain the coordinator's enqueue, completion, and retry dispatches.
        for _ in 0..<5 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}

private final class TransitioningController: UIViewController {
    var dismissing = false
    var presenting = false
    override var isBeingDismissed: Bool { dismissing }
    override var isBeingPresented: Bool { presenting }
}
