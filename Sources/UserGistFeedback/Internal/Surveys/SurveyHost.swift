import Foundation
import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/UserGist.ts (openSurvey flow)
//
// Bridge between UIKit's "present a modal" world and SwiftUI's SurveyView.
// Walks `UIApplication.shared.connectedScenes` for the foreground key
// window's rootViewController, mirroring the pattern PromptPresenter
// already uses elsewhere in the SDK.

@available(iOS 14.0, *)
enum SurveyHost {
    private static let modalOwner = NSObject()
    private static weak var currentController: UIViewController?
    private static var releaseCurrent: (() -> Void)?

    static func reset() {
        DispatchQueue.main.async {
            SDKModalCoordinator.shared.cancelPending(owner: modalOwner)
            currentController?.dismiss(animated: false)
            currentController = nil
            releaseCurrent?()
            releaseCurrent = nil
        }
    }

    static func present(
        flow: SurveyFlow,
        surveyId: String,
        attemptId: String,
        endScreen: SurveyEndScreen?,
        theme: ResolvedTheme,
        store: SurveyStore,
        handlers: SurveyHandlers,
        resume: SurveyAttempt?,
        logger: UserGistLogger,
        onProgress: @escaping (String, String?, [String: SurveyAnswerValue]) -> Void,
        onComplete: @escaping (
            String,
            [String: SurveyAnswerValue],
            @escaping (Bool) -> Void
        ) -> Void,
        onAbandon: @escaping (String, @escaping (Bool) -> Void) -> Void
    ) {
        SDKModalCoordinator.shared.enqueue(owner: modalOwner) { release in
            guard let presenter = TopViewControllerLocator.topMost() else {
                logger.warn("SurveyHost: no presentable view controller found")
                return false
            }
            let viewModel = NativeSurveyViewModel(
                flow: flow,
                surveyId: surveyId,
                attemptId: attemptId,
                store: store,
                resume: resume,
                onProgress: onProgress,
                onComplete: onComplete
            )
            var hosting: UIHostingController<NativeSurveyView>!
            let closeAction: () -> Void = { [weak hosting] in
                hosting?.dismiss(animated: true) {
                    currentController = nil
                    releaseCurrent = nil
                    release()
                }
            }
            let abandonAction: (@escaping (Bool) -> Void) -> Void = {
                [weak hosting] outcome in
                onAbandon(attemptId) { persisted in
                    guard persisted else {
                        outcome(false)
                        return
                    }
                    hosting?.dismiss(animated: true) {
                        handlers.onAbandon?(surveyId, attemptId)
                        outcome(true)
                        currentController = nil
                        releaseCurrent = nil
                        release()
                    }
                }
            }
            let view = NativeSurveyView(
                viewModel: viewModel,
                endScreen: endScreen,
                theme: theme,
                onClose: closeAction,
                onAbandon: abandonAction
            )
            hosting = UIHostingController(rootView: view)
            currentController = hosting
            releaseCurrent = release
            hosting.modalPresentationStyle = .fullScreen
            hosting.view.backgroundColor = theme.background
            presenter.present(hosting, animated: true) {
                handlers.onShow?(surveyId)
            }
            return true
        }
    }

}
