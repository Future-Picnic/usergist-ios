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
        onShown: @escaping () -> Void,
        onDismiss: @escaping (InAppDismissReason) -> Void,
        onCta: @escaping (InAppCta, Int) -> Void
    ) {
        SDKModalCoordinator.shared.enqueue(owner: self) { [weak self] release in
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

private final class InAppMessageController: UIViewController,
    UIAdaptivePresentationControllerDelegate, UIGestureRecognizerDelegate {
    private let message: ArmedInAppMessage
    private let theme: ResolvedTheme
    private let onDismiss: (InAppDismissReason) -> Void
    private let onCta: (InAppCta, Int) -> Void
    private var delivered = false
    private var autoDismissTimer: Timer?
    private var imageTask: URLSessionDataTask?
    private let card = UIView()

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

        switch message.format {
        case .modal:
            modalPresentationStyle = .overFullScreen
            modalTransitionStyle = .crossDissolve
        case .modalFull:
            modalPresentationStyle = .fullScreen
        case .slideup:
            modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *), let sheet = sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = theme.radius
                if !message.backdropEnabled {
                    sheet.largestUndimmedDetentIdentifier = .large
                }
            }
        }
        presentationController?.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = message.format == .modal && message.backdropEnabled
            ? UIColor.black.withAlphaComponent(0.4)
            : (message.format == .modal ? .clear : theme.background)
        buildInterface()
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
        imageTask?.cancel()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        deliverDismiss(.user)
    }

    private func buildInterface() {
        let isFull = message.format == .modalFull
        let isSlide = message.format == .slideup

        if message.format == .modal {
            let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = theme.background
        card.layer.cornerRadius = isFull ? 0 : theme.radius
        card.layer.masksToBounds = true
        view.addSubview(card)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        card.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let closeRow = UIView()
        closeRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = theme.text
        close.accessibilityLabel = "Close"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeRow.addSubview(close)
        NSLayoutConstraint.activate([
            close.trailingAnchor.constraint(equalTo: closeRow.trailingAnchor, constant: -8),
            close.topAnchor.constraint(equalTo: closeRow.topAnchor, constant: 4),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44)
        ])
        stack.addArrangedSubview(closeRow)

        if let imageURL = message.imageUrl.flatMap(URL.init(string:)) {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isAccessibilityElement = false
            imageView.heightAnchor.constraint(equalToConstant: isFull ? 260 : 176).isActive = true
            stack.addArrangedSubview(imageView)
            loadImage(imageURL, into: imageView)
        }

        let copy = UIStackView()
        copy.axis = .vertical
        copy.spacing = 8
        copy.isLayoutMarginsRelativeArrangement = true
        copy.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 12, right: 24)

        let title = UILabel()
        title.text = message.title
        title.textColor = theme.text
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        title.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: theme.titleFont)
        copy.addArrangedSubview(title)

        if let body = message.body, !body.isEmpty {
            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.textColor = theme.subtext
            bodyLabel.numberOfLines = 0
            bodyLabel.adjustsFontForContentSizeCategory = true
            bodyLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: theme.font)
            copy.addArrangedSubview(bodyLabel)
        }
        stack.addArrangedSubview(copy)

        if !message.ctas.isEmpty {
            let buttons = UIStackView()
            buttons.axis = .vertical
            buttons.spacing = 8
            buttons.isLayoutMarginsRelativeArrangement = true
            buttons.layoutMargins = UIEdgeInsets(top: 12, left: 24, bottom: 24, right: 24)
            for (index, cta) in message.ctas.enumerated() {
                let button = UIButton(type: .system)
                button.tag = index
                button.setTitle(cta.label, for: .normal)
                button.titleLabel?.font = theme.boldFont
                button.titleLabel?.adjustsFontForContentSizeCategory = true
                button.layer.cornerRadius = min(theme.radius, 14)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
                if index == 0 {
                    button.backgroundColor = theme.primary
                    button.setTitleColor(Self.contrastColor(on: theme.primary), for: .normal)
                } else {
                    button.backgroundColor = .clear
                    button.setTitleColor(theme.primary, for: .normal)
                    button.layer.borderWidth = 1
                    button.layer.borderColor = theme.primary.cgColor
                }
                button.addTarget(self, action: #selector(ctaTapped(_:)), for: .touchUpInside)
                buttons.addArrangedSubview(button)
            }
            stack.addArrangedSubview(buttons)
        }

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        if isFull || isSlide {
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                card.topAnchor.constraint(equalTo: view.topAnchor),
                card.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else {
            let preferredWidth = card.widthAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.widthAnchor,
                constant: -32
            )
            preferredWidth.priority = .defaultHigh
            NSLayoutConstraint.activate([
                card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                card.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                card.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                card.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
                card.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.86),
                preferredWidth
            ])
        }
    }

    private func loadImage(_ url: URL, into imageView: UIImageView) {
        imageTask = URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= 10 * 1_024 * 1_024,
                  let data,
                  data.count <= 10 * 1_024 * 1_024,
                  let image = UIImage(data: data)
            else { return }
            DispatchQueue.main.async { [weak imageView] in imageView?.image = image }
        }
        imageTask?.resume()
    }

    @objc private func closeTapped() {
        dismiss(reason: .user)
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
        dismiss(animated: true) { [onCta] in onCta(cta, sender.tag) }
    }

    private func dismiss(reason: InAppDismissReason) {
        guard !delivered else { return }
        delivered = true
        autoDismissTimer?.invalidate()
        dismiss(animated: true) { [onDismiss] in onDismiss(reason) }
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

    private static func contrastColor(on color: UIColor) -> UIColor {
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: nil) {
            return white < 0.58 ? .white : .black
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance < 0.58 ? .white : .black
    }
}
