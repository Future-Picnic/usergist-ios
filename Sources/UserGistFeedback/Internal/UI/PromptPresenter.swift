import Foundation
import UIKit

/// Coordinates finding the right window/view-controller and presenting the
/// bottom sheet over it, then translates the UI outcome into the payloads
/// the rest of the SDK expects.
final class PromptPresenter {
    struct PresentationContext {
        let prompt: ClientPrompt
        let theme: ResolvedTheme
        let shownAt: Date
    }

    private weak var currentController: UIViewController?
    private var releaseCurrent: (() -> Void)?

    /// Presents the prompt and delivers the outcome via `onFinish`.
    /// Safe to call from any thread — always dispatches to main.
    func present(
        context: PresentationContext,
        onShown: @escaping () -> Void,
        onFinish: @escaping (PromptResponseInfo) -> Void
    ) {
        let prompt = context.prompt
        let theme = context.theme
        let shownAt = context.shownAt

        SDKModalCoordinator.shared.enqueue(owner: self) { [weak self] release in
            guard let self else { return false }
            guard let top = Self.resolveTopViewController() else {
                return false
            }

            var container: BottomSheetController!
            let view = PromptView(prompt: prompt, theme: theme) { outcome in
                let latency = Int(Date().timeIntervalSince(shownAt) * 1000)
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

    /// Resolves the top-most presented controller in the key window of the
    /// active scene. Falls back to any connected scene if no key window.
    static func resolveTopViewController() -> UIViewController? {
        let window = activeKeyWindow()
        guard let root = window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private static func activeKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
        if let w = active?.windows.first(where: { $0.isKeyWindow }) {
            return w
        }
        return active?.windows.first ?? UIApplication.shared.windows.first
    }
}
