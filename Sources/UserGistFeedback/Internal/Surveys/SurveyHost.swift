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
    static func present(
        flow: SurveyFlow,
        surveyId: String,
        attemptId: String,
        store: SurveyStore,
        handlers: SurveyHandlers,
        resume: SurveyAttempt?,
        logger: UserGistLogger
    ) {
        guard let presenter = TopViewControllerLocator.topMost() else {
            logger.warn("SurveyHost: no presentable view controller found")
            return
        }
        let viewModel = SurveyViewModel(
            flow: flow,
            surveyId: surveyId,
            attemptId: attemptId,
            store: store,
            resume: resume
        )
        let dismissAction = { [weak presenter] in
            presenter?.presentedViewController?.dismiss(animated: true) {
                handlers.onComplete?(surveyId, attemptId)
                store.clear(surveyId: surveyId)
            }
        }
        let view = SurveyView(viewModel: viewModel, onDismiss: dismissAction)
        let hosting = UIHostingController(rootView: view)
        hosting.modalPresentationStyle = .pageSheet
        handlers.onShow?(surveyId)
        presenter.present(hosting, animated: true)
    }

}
