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
    private var lastContext: PresentationContext?
    private weak var savedNotice: UIView?

    /// Confirms durable local storage, rather than server delivery.
    func showSavedNotice(promptId: String, isValid: @escaping () -> Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, isValid(), let context = self.lastContext,
                  context.prompt.id == promptId,
                  let window = Self.resolveTopViewController()?.view.window else { return }
            self.savedNotice?.removeFromSuperview()
            let notice = UIView()
            notice.backgroundColor = context.theme.background
            notice.layer.cornerRadius = context.theme.radius
            notice.layer.borderWidth = 1
            notice.layer.borderColor = context.theme.border.cgColor
            notice.isUserInteractionEnabled = false
            let label = UILabel()
            label.text = "Feedback saved. We’ll send it automatically."
            label.textColor = context.theme.text
            label.font = context.theme.font
            label.numberOfLines = 0
            label.textAlignment = .center
            notice.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false
            notice.addSubview(label)
            window.addSubview(notice)
            NSLayoutConstraint.activate([
                notice.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                notice.leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                notice.trailingAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                notice.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
                notice.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                label.leadingAnchor.constraint(equalTo: notice.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: notice.trailingAnchor, constant: -20),
                label.topAnchor.constraint(equalTo: notice.topAnchor, constant: 14),
                label.bottomAnchor.constraint(equalTo: notice.bottomAnchor, constant: -14)
            ])
            self.savedNotice = notice
            UIAccessibility.post(notification: .announcement, argument: label.text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak notice] in
                notice?.removeFromSuperview()
            }
        }
    }

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
            if let window = top.view.window {
                view.layoutHint = (window.bounds.size, window.safeAreaInsets)
            }
            container = BottomSheetController(promptView: view, theme: theme)
            self.lastContext = context
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
            self.savedNotice?.removeFromSuperview()
            self.lastContext = nil
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
