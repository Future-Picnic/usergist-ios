import Foundation
import UIKit

/// Serializes native in-app presentation and translates UI outcomes into the
/// same lifecycle contract used by the React Native reference implementation.
final class InAppPresenter {
    private weak var currentController: InAppMessageController?
    private var releaseCurrent: (() -> Void)?

    func present(
        message: ArmedInAppMessage,
        theme: ResolvedTheme,
        isValid: @escaping () -> Bool = { true },
        onShown: @escaping () -> Void,
        onDismiss: @escaping (InAppDismissReason) -> Void,
        onCta: @escaping (InAppCta, Int) -> Void
    ) {
        SDKModalCoordinator.shared.enqueue(owner: self, key: message.messageId, isValid: isValid) { [weak self] release in
            guard let self, let top = TopViewControllerLocator.topMost() else {
                return false
            }
            let controller = InAppMessageController(
                message: message,
                theme: theme,
                onDismiss: { [weak self] reason in
                    onDismiss(reason)
                    self?.finishCurrent()
                },
                onCta: { [weak self] cta, index in
                    onCta(cta, index)
                    self?.finishCurrent()
                }
            )
            self.currentController = controller
            self.releaseCurrent = release
            top.present(controller, animated: true, completion: onShown)
            return true
        }
    }

    func retryPending() {
        SDKModalCoordinator.shared.retryPending()
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SDKModalCoordinator.shared.cancelPending(owner: self)
            self.currentController?.cancelWithoutOutcome()
            self.currentController = nil
            self.releaseCurrent?()
            self.releaseCurrent = nil
        }
    }

    private func finishCurrent() {
        DispatchQueue.main.async { [weak self] in
            self?.currentController = nil
            self?.releaseCurrent?()
            self?.releaseCurrent = nil
        }
    }
}

/// Hosts one in-app message (PORTED FROM RN InAppMessageView). Card and
/// slide-up float over a themed scrim; full screen uses the theme background.
final class InAppMessageController: UIViewController,
    UIAdaptivePresentationControllerDelegate, UIGestureRecognizerDelegate {
    private let message: ArmedInAppMessage
    private let theme: ResolvedTheme
    private let onDismiss: (InAppDismissReason) -> Void
    private let onCta: (InAppCta, Int) -> Void
    private var delivered = false
    private var autoDismissTimer: Timer?
    private let card = UIView()
    private var cardConstraints: [NSLayoutConstraint] = []
    private var builtForLandscape: Bool?

    private var format: InAppLayoutFormat {
        switch message.format {
        case .modal: return .card
        case .modalFull: return .full
        case .slideup: return .slide
        }
    }

    init(
        message: ArmedInAppMessage,
        theme: ResolvedTheme,
        onDismiss: @escaping (InAppDismissReason) -> Void,
        onCta: @escaping (InAppCta, Int) -> Void
    ) {
        self.message = message
        self.theme = theme
        self.onDismiss = onDismiss
        self.onCta = onCta
        super.init(nibName: nil, bundle: nil)
        if message.format == .modalFull {
            modalPresentationStyle = .fullScreen
        } else {
            modalPresentationStyle = .overFullScreen
            modalTransitionStyle = .crossDissolve
        }
        presentationController?.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        presentingViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let overlay = format != .full
        overrideUserInterfaceStyle = theme.interfaceStyle
        view.backgroundColor = overlay
            ? (message.backdropEnabled ? theme.scrim : .clear)
            : theme.background
        if overlay {
            // The backdrop always dismisses, even when it is transparent.
            let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        card.accessibilityIdentifier = "usergist_inapp_card"
        card.backgroundColor = theme.background
        card.layer.cornerRadius = overlay ? theme.radius : 0
        card.layer.masksToBounds = true
        if overlay {
            card.layer.borderWidth = 1 / UIScreen.main.scale
            card.layer.borderColor = theme.text.withAlphaComponent(0.08).cgColor
        }
        view.addSubview(card)
        rebuild(for: view.bounds.size == .zero ? UIScreen.main.bounds.size : view.bounds.size)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let size = view.bounds.size
        if size != .zero, builtForLandscape != (size.width > size.height) { rebuild(for: size) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard format == .slide, animated, !UIAccessibility.isReduceMotionEnabled else { return }
        view.layoutIfNeeded()
        card.transform = CGAffineTransform(translationX: 0, y: view.bounds.height - card.frame.minY)
        UIView.animate(withDuration: 0.36, delay: 0, options: [.curveEaseOut]) {
            self.card.transform = .identity
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
        if message.format == .slideup,
           let seconds = message.autoDismissSeconds,
           seconds > 0 {
            autoDismissTimer = Timer.scheduledTimer(
                withTimeInterval: seconds,
                repeats: false
            ) { [weak self] _ in
                self?.dismiss(reason: .auto)
            }
        }
    }

    deinit {
        autoDismissTimer?.invalidate()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        deliverDismiss(.user)
    }

    // MARK: - Layout

    private func rebuild(for size: CGSize) {
        let landscape = size.width > size.height
        builtForLandscape = landscape
        card.subviews.forEach { $0.removeFromSuperview() }
        NSLayoutConstraint.deactivate(cardConstraints)

        let close = SurfaceIconButton(glyph: .close, color: theme.text)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let layout = InAppMessageLayout(
            message: message,
            format: format,
            theme: theme,
            landscape: landscape,
            maxFooterHeight: max(120, (size.height * 0.4).rounded()),
            close: close,
            makeCta: { [weak self] index, button in
                button.tag = index
                button.addTarget(self, action: #selector(Self.ctaTapped(_:)), for: .touchUpInside)
            }
        )
        let content = layout.build()
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        let safe = view.safeAreaLayoutGuide
        var constraints = [
            content.leadingAnchor.constraint(equalTo: format == .full ? safe.leadingAnchor : card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: format == .full ? safe.trailingAnchor : card.trailingAnchor),
            content.topAnchor.constraint(equalTo: format == .full ? safe.topAnchor : card.topAnchor,
                                         constant: format == .full ? 4 : 0),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor,
                                            constant: format == .full ? -max(view.safeAreaInsets.bottom, 12) : 0)
        ]
        switch format {
        case .full:
            constraints += [
                content.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor),
                card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                card.topAnchor.constraint(equalTo: view.topAnchor),
                card.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
        case .card:
            constraints += overlayConstraints(maxWidth: landscape ? SurfaceMetrics.contentMaxWidth : 400,
                                              sideInset: 16)
            constraints.append(card.centerYAnchor.constraint(equalTo: safe.centerYAnchor))
        case .slide:
            constraints += overlayConstraints(maxWidth: landscape ? SurfaceMetrics.contentMaxWidth : .greatestFiniteMagnitude,
                                              sideInset: 12)
            let bottomInset = max(view.safeAreaInsets.bottom, 12) + 4
            constraints.append(card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottomInset))
        }
        cardConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    /// Centred, width-capped card that never leaves the safe area.
    private func overlayConstraints(maxWidth: CGFloat, sideInset: CGFloat) -> [NSLayoutConstraint] {
        let safe = view.safeAreaLayoutGuide
        let preferredWidth = card.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -2 * sideInset)
        preferredWidth.priority = .defaultHigh
        var constraints = [
            card.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: sideInset),
            card.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -sideInset),
            card.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 8),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor,
                                         constant: -(max(view.safeAreaInsets.bottom, 12))),
            preferredWidth
        ]
        if maxWidth < .greatestFiniteMagnitude {
            constraints.append(card.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth))
        }
        return constraints
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if builtForLandscape != nil { rebuild(for: view.bounds.size) }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(reason: .user)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        return !touched.isDescendant(of: card)
    }

    @objc private func backdropTapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: view)
        if !card.frame.contains(point) { dismiss(reason: .user) }
    }

    @objc private func ctaTapped(_ sender: UIButton) {
        guard message.ctas.indices.contains(sender.tag), !delivered else { return }
        delivered = true
        autoDismissTimer?.invalidate()
        let cta = message.ctas[sender.tag]
        let index = sender.tag
        animateOut { [weak self] in
            self?.dismiss(animated: true) { [onCta = self?.onCta] in onCta?(cta, index) }
        }
    }

    private func dismiss(reason: InAppDismissReason) {
        guard !delivered else { return }
        delivered = true
        autoDismissTimer?.invalidate()
        animateOut { [weak self] in
            self?.dismiss(animated: true) { [onDismiss = self?.onDismiss] in onDismiss?(reason) }
        }
    }

    /// Slide-up leaves the way it came in; other formats cross-fade.
    private func animateOut(_ completion: @escaping () -> Void) {
        guard format == .slide, !UIAccessibility.isReduceMotionEnabled, view.window != nil else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.card.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height - self.card.frame.minY)
        } completion: { _ in completion() }
    }

    private func deliverDismiss(_ reason: InAppDismissReason) {
        guard !delivered else { return }
        delivered = true
        autoDismissTimer?.invalidate()
        onDismiss(reason)
    }

    func cancelWithoutOutcome() {
        delivered = true
        autoDismissTimer?.invalidate()
        dismiss(animated: false)
    }
}
