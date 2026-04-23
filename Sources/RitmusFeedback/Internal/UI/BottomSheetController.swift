import Foundation
import UIKit

/// Hosts the `PromptView` inside a bottom sheet. Uses the native
/// `UISheetPresentationController` on iOS 15+, falls back to a custom
/// transitioning delegate on iOS 14.
final class BottomSheetController: UIViewController {
    private let promptView: PromptView
    private let theme: ResolvedTheme

    init(promptView: PromptView, theme: ResolvedTheme) {
        self.promptView = promptView
        self.theme = theme
        super.init(nibName: nil, bundle: nil)

        if #available(iOS 15.0, *) {
            modalPresentationStyle = .pageSheet
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = theme.radius
            }
        } else {
            modalPresentationStyle = .custom
            transitioningDelegate = Fallback14Transitioning.shared
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
}

// MARK: - iOS 14 fallback transitioning

private final class Fallback14Transitioning: NSObject, UIViewControllerTransitioningDelegate {
    static let shared = Fallback14Transitioning()

    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        Fallback14PresentationController(presentedViewController: presented, presenting: presenting)
    }
}

private final class Fallback14PresentationController: UIPresentationController {
    private let dimmer = UIView()

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let height = min(container.bounds.height * 0.6, container.bounds.height - 80)
        let y = container.bounds.height - height
        return CGRect(x: 0, y: y, width: container.bounds.width, height: height)
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        dimmer.frame = container.bounds
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimmer.alpha = 0
        container.addSubview(dimmer)
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
        presentedViewController.dismiss(animated: true)
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}
