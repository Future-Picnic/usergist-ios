import Foundation
import UIKit

/// Hosts `PromptView` in a content-sized bottom sheet. The background spans the
/// full screen width in every orientation with rounded top corners (RN
/// PromptSheet); the prompt view keeps its controls inside the safe area.
final class BottomSheetController: UIViewController {
    private let promptView: PromptView
    private let theme: ResolvedTheme
    private let sheetTransition = PromptSheetTransitioning()

    init(promptView: PromptView, theme: ResolvedTheme) {
        self.promptView = promptView
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = sheetTransition
        let hintWidth = promptView.layoutHint?.size.width ?? UIScreen.main.bounds.width
        preferredContentSize = CGSize(width: 0, height: promptView.preferredHeight(forWidth: hintWidth))
        promptView.onPreferredHeightChange = { [weak self] height in
            guard let self, abs(self.preferredContentSize.height - height) > 0.5 else { return }
            self.preferredContentSize = CGSize(width: 0, height: height)
            self.presentationController?.containerView?.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        overrideUserInterfaceStyle = theme.interfaceStyle
        view.clipsToBounds = true
        view.layer.cornerRadius = theme.radius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        promptView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(promptView)

        NSLayoutConstraint.activate([
            promptView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            promptView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            promptView.topAnchor.constraint(equalTo: view.topAnchor),
            promptView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func requestDismiss() {
        promptView.dismiss()
    }
}

// MARK: - Custom content-sized sheet

private final class PromptSheetTransitioning: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        PromptSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        PromptSheetAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PromptSheetAnimator(presenting: false)
    }
}

private final class PromptSheetPresentationController: UIPresentationController {
    private let dimmer = UIView()
    private var keyboardOverlap: CGFloat = 0
    private var keyboardObservers: [NSObjectProtocol] = []

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        return PromptSheetLayout.frame(
            containerBounds: container.bounds,
            safeTop: container.safeAreaInsets.top,
            requestedHeight: presentedViewController.preferredContentSize.height,
            keyboardOverlap: keyboardOverlap
        )
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        observeKeyboard()
        dimmer.frame = container.bounds
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dimmer.alpha = 0
        dimmer.isAccessibilityElement = true
        dimmer.accessibilityLabel = "Dismiss"
        dimmer.accessibilityTraits = .button
        container.insertSubview(dimmer, at: 0)
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapDimmer))
        dimmer.addGestureRecognizer(tap)

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { [weak self] _ in
            self?.dimmer.alpha = 1
        })
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { [weak self] _ in
            self?.dimmer.alpha = 0
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        if completed { stopObservingKeyboard() }
    }

    @objc private func didTapDimmer() {
        (presentedViewController as? BottomSheetController)?.requestDismiss()
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        dimmer.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        containerView?.setNeedsLayout()
    }

    deinit {
        stopObservingKeyboard()
    }

    private func observeKeyboard() {
        guard keyboardObservers.isEmpty else { return }
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.keyboardFrameWillChange(notification)
            },
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.keyboardFrameWillChange(notification)
            },
        ]
    }

    private func stopObservingKeyboard() {
        let center = NotificationCenter.default
        keyboardObservers.forEach(center.removeObserver)
        keyboardObservers.removeAll()
    }

    private func keyboardFrameWillChange(_ notification: Notification) {
        guard let container = containerView else { return }
        let info = notification.userInfo
        let screenFrame = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let frame = container.convert(screenFrame, from: nil)
        let hiding = notification.name == UIResponder.keyboardWillHideNotification
        keyboardOverlap = hiding ? 0 : max(0, container.bounds.maxY - frame.minY)

        let duration = (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.presentedView?.frame = self.frameOfPresentedViewInContainerView
            self.presentedView?.layoutIfNeeded()
        }
    }
}

enum PromptSheetLayout {
    /// Shortest sheet; below this the header and one control would crowd.
    static let minimumHeight: CGFloat = 160

    static func frame(
        containerBounds: CGRect,
        safeTop: CGFloat,
        requestedHeight: CGFloat,
        keyboardOverlap: CGFloat
    ) -> CGRect {
        let overlap = min(max(keyboardOverlap, 0), containerBounds.height)
        let usableBottom = containerBounds.maxY - overlap
        let maxHeight = max(0, usableBottom - safeTop - 16)
        let height = min(max(requestedHeight, minimumHeight), maxHeight)
        return CGRect(
            x: containerBounds.minX,
            y: usableBottom - height,
            width: containerBounds.width,
            height: height
        )
    }
}

private final class PromptSheetAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool

    init(presenting: Bool) {
        self.presenting = presenting
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.28
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let duration = transitionDuration(using: transitionContext)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if presenting {
            guard let toView = transitionContext.view(forKey: .to),
                  let toController = transitionContext.viewController(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            transitionContext.containerView.addSubview(toView)
            let finalFrame = transitionContext.finalFrame(for: toController)
            toView.frame = reduceMotion ? finalFrame : finalFrame.offsetBy(dx: 0, dy: finalFrame.height)
            toView.alpha = reduceMotion ? 0 : 1
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                toView.frame = finalFrame
                toView.alpha = 1
            } completion: { finished in
                transitionContext.completeTransition(finished)
            }
        } else {
            guard let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
                if reduceMotion {
                    fromView.alpha = 0
                } else {
                    fromView.frame = fromView.frame.offsetBy(dx: 0, dy: fromView.frame.height)
                }
            } completion: { finished in
                transitionContext.completeTransition(finished)
            }
        }
    }
}
