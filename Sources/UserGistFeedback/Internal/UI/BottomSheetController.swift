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

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let safeTop = container.safeAreaInsets.top
        let maxHeight = max(280, container.bounds.height - safeTop - 16)
        let requested = presentedViewController.preferredContentSize.height
        let height = min(max(requested, 280), maxHeight)
        let y = container.bounds.height - height
        return CGRect(x: 0, y: y, width: container.bounds.width, height: height)
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        dimmer.frame = container.bounds
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.35)
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

    @objc private func didTapDimmer() {
        (presentedViewController as? BottomSheetController)?.requestDismiss()
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
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
