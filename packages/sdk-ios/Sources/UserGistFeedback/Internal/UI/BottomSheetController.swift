import Foundation
import UIKit

/// Hosts `PromptView` inside a content-sized bottom sheet whose visible
/// structure matches the React Native/dashboard preview on every iOS version.
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
        preferredContentSize = CGSize(width: 0, height: 280)
        promptView.onPreferredHeightChange = { [weak self] height in
            guard let self else { return }
            self.preferredContentSize = CGSize(width: 0, height: height)
            self.presentationController?.containerView?.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        view.clipsToBounds = true
        view.layer.cornerRadius = theme.radius

        promptView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(promptView)

        NSLayoutConstraint.activate([
            promptView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            promptView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            promptView.topAnchor.constraint(equalTo: view.topAnchor),
            promptView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
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
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmer.alpha = 0
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
        keyboardOverlap = max(0, container.bounds.maxY - frame.minY)

        let duration = (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.presentedView?.frame = self.frameOfPresentedViewInContainerView
        }
    }
}

enum PromptSheetLayout {
    static func frame(
        containerBounds: CGRect,
        safeTop: CGFloat,
        requestedHeight: CGFloat,
        keyboardOverlap: CGFloat
    ) -> CGRect {
        let overlap = min(max(keyboardOverlap, 0), containerBounds.height)
        let usableBottom = containerBounds.maxY - overlap
        let maxHeight = max(0, usableBottom - safeTop - 16)
        let height = min(max(requestedHeight, 280), maxHeight)
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
        0.28
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let duration = transitionDuration(using: transitionContext)
        if presenting {
            guard let toView = transitionContext.view(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            transitionContext.containerView.addSubview(toView)
            let finalFrame = transitionContext.finalFrame(for: transitionContext.viewController(forKey: .to)!)
            toView.frame = finalFrame.offsetBy(dx: 0, dy: finalFrame.height)
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                toView.frame = finalFrame
            } completion: { finished in
                transitionContext.completeTransition(finished)
            }
        } else {
            guard let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                fromView.frame = fromView.frame.offsetBy(dx: 0, dy: fromView.frame.height)
            } completion: { finished in
                transitionContext.completeTransition(finished)
            }
        }
    }
}
