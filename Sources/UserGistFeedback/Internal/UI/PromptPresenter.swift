import Foundation
import UIKit

/// Coordinates finding the right window/view-controller and presenting the
/// bottom sheet over it, then translates the UI outcome into the payloads
/// the rest of the SDK expects.
final class PromptPresenter {
    struct PresentationContext {
        let prompt: ClientPrompt
        let theme: ResolvedTheme
    }

    private weak var currentController: UIViewController?
    private var releaseCurrent: (() -> Void)?

    /// Presents the prompt and delivers the outcome via `onFinish`.
    /// Safe to call from any thread — always dispatches to main.
    func present(
        context: PresentationContext,
        isValid: @escaping () -> Bool = { true },
        onShown: @escaping () -> Void,
        onFinish: @escaping (PromptResponseInfo) -> Void
    ) {
        let prompt = context.prompt
        let theme = context.theme

        SDKModalCoordinator.shared.enqueue(owner: self, key: prompt.id, isValid: isValid) { [weak self] release in
            guard let self else { return false }
            guard let top = Self.resolveTopViewController() else {
                return false
            }

            var container: BottomSheetController!
            var shownAt: Date?
            let view = PromptView(prompt: prompt, theme: theme) { outcome in
                let latency = Int(Date().timeIntervalSince(shownAt ?? Date()) * 1000)
                let info: PromptResponseInfo
                switch outcome {
                case .submitted(let answers):
                    info = PromptResponseInfo(
                        promptId: prompt.id,
                        answers: answers,
                        dismissed: false,
                        latencyMs: max(0, latency)
                    )
                case .dismissed(let answers):
                    info = PromptResponseInfo(
                        promptId: prompt.id,
                        answers: answers,
                        dismissed: true,
                        latencyMs: max(0, latency)
                    )
                }
                container?.dismiss(animated: true) {
                    onFinish(info)
                    self.currentController = nil
                    self.releaseCurrent = nil
                    release()
                }
            }
            container = BottomSheetController(promptView: view, theme: theme)
            self.currentController = container
            self.releaseCurrent = release
            top.present(container, animated: true) {
                shownAt = Date()
                onShown()
            }
            return true
        }
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SDKModalCoordinator.shared.cancelPending(owner: self)
            self.currentController?.dismiss(animated: false)
            self.currentController = nil
            self.releaseCurrent?()
            self.releaseCurrent = nil
        }
    }

    /// Uses the same foreground/transition checks as other campaign surfaces.
    static func resolveTopViewController() -> UIViewController? {
        TopViewControllerLocator.topMost()
    }
}
