import Foundation
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/InAppMessageLayout.tsx
//
// Presentational body for in-app messages. InAppMessageController owns
// timing, animation and dismissal; this file owns layout.
//   - card:  deliberate centred card, Close leading, pinned actions.
//   - full:  full screen, content in the 560pt readable column.
//   - slide: floating inset card (all corners rounded) above the home indicator.
// Actions keep their natural height up to `maxFooterHeight`, then scroll, so
// long labels or large text are never clipped and the body keeps >= 96pt.

enum InAppLayoutFormat { case card, full, slide }

struct InAppMessageLayout {
    let message: ArmedInAppMessage
    let format: InAppLayoutFormat
    let theme: ResolvedTheme
    let landscape: Bool
    let maxFooterHeight: CGFloat
    let close: UIButton
    let makeCta: (Int, UIButton) -> Void

    /// Builds the content stack to pin inside the card (or full-screen root).
    func build() -> UIView {
        switch format {
        case .slide: return buildSlide()
        case .full: return buildFull()
        case .card: return buildCard()
        }
    }

    // MARK: Formats

    private func buildCard() -> UIView {
        let root = verticalStack(spacing: 0)
        root.addArrangedSubview(padded(closeRow(), insets: UIEdgeInsets(top: 8, left: 8, bottom: 0, right: 8)))
        let body = verticalStack(spacing: 0)
        if let image = imageView(height: landscape ? 128 : 168) {
            body.addArrangedSubview(image)
            body.setCustomSpacing(18, after: image)
        }
        body.addArrangedSubview(textBlock(titleSize: 19, titleLine: 25, bodySize: 15, bodyLine: 22, gap: 8))
        root.addArrangedSubview(bodyScroll(body, insets: UIEdgeInsets(top: 0, left: 22, bottom: 8, right: 22)))
        if let footer = footer(stacked: !landscape, compact: false,
                               insets: UIEdgeInsets(top: 16, left: 22, bottom: 22, right: 22)) {
            root.addArrangedSubview(footer)
        }
        return root
    }

    private func buildFull() -> UIView {
        let root = verticalStack(spacing: 0)
        root.addArrangedSubview(padded(closeRow(), insets: UIEdgeInsets(top: 4, left: 12, bottom: 0, right: 12)))
        let body = verticalStack(spacing: 0)
        if let image = imageView(height: landscape ? 128 : 240) {
            body.addArrangedSubview(image)
            body.setCustomSpacing(24, after: image)
        }
        body.addArrangedSubview(textBlock(titleSize: 26, titleLine: 32, bodySize: 17, bodyLine: 26, gap: 8))
        let scroll = bodyScroll(measured(body), insets: UIEdgeInsets(top: 8, left: 24, bottom: 24, right: 24),
                                centerVertically: true)
        root.addArrangedSubview(scroll)
        if let footer = footer(stacked: !landscape, compact: false,
                               insets: UIEdgeInsets(top: 8, left: 24, bottom: 0, right: 24), measured: true) {
            root.addArrangedSubview(footer)
        }
        return root
    }

    private func buildSlide() -> UIView {
        let root = verticalStack(spacing: 10)
        root.isLayoutMarginsRelativeArrangement = true
        root.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 14, right: 8)
        let content = verticalStack(spacing: 10)
        let text = textBlock(titleSize: 19, titleLine: 25, bodySize: 15, bodyLine: 22, gap: 4)
        content.addArrangedSubview(padded(text, insets: UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 8)))
        if let image = imageView(height: 120) { content.addArrangedSubview(image) }
        let row = UIStackView(arrangedSubviews: [close, bodyScroll(content, insets: UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0), minHeight: 44)])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 4
        root.addArrangedSubview(row)
        if let footer = footer(stacked: false, compact: true, insets: UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)) {
            root.addArrangedSubview(footer)
        }
        return root
    }

    // MARK: Parts

    private func closeRow() -> UIView {
        let row = UIStackView(arrangedSubviews: [close, UIView()])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func textBlock(titleSize: CGFloat, titleLine: CGFloat, bodySize: CGFloat,
                           bodyLine: CGFloat, gap: CGFloat) -> UIView {
        let stack = verticalStack(spacing: gap)
        let title = SurfaceLabel.make(message.title, font: theme.surfaceFont(titleSize, .bold),
                                      color: theme.text, lineHeight: titleLine)
        title.accessibilityTraits = .header
        stack.addArrangedSubview(title)
        if let body = message.body, !body.isEmpty {
            stack.addArrangedSubview(SurfaceLabel.make(body, font: theme.surfaceFont(bodySize),
                                                       color: theme.subtext, lineHeight: bodyLine))
        }
        return stack
    }

    private func imageView(height: CGFloat) -> UIView? {
        guard let url = message.imageUrl.flatMap(URL.init(string:)) else { return nil }
        let image = SurfaceRemoteImageView(url: url, radius: max(8, theme.radius - 8), placeholder: theme.fill)
        image.heightAnchor.constraint(equalToConstant: height).isActive = true
        return image
    }

    /// Body scroller: natural height, shrinks (and scrolls) first, keeps a readable minimum.
    private func bodyScroll(_ content: UIView, insets: UIEdgeInsets, minHeight: CGFloat = 96,
                            centerVertically: Bool = false) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = true
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        var constraints = [
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -insets.right),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -(insets.left + insets.right)),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)
        ]
        let natural = scroll.heightAnchor.constraint(equalTo: scroll.contentLayoutGuide.heightAnchor)
        natural.priority = UILayoutPriority(749)
        constraints.append(natural)
        if centerVertically {
            // Short content sits centred; tall content scrolls from the top.
            let frame = scroll.frameLayoutGuide
            constraints += [
                content.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: insets.top),
                content.bottomAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.bottomAnchor, constant: -insets.bottom),
                scroll.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor),
                content.centerYAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerYAnchor)
            ]
            let snug = scroll.contentLayoutGuide.heightAnchor.constraint(equalTo: content.heightAnchor,
                                                                         constant: insets.top + insets.bottom)
            snug.priority = .defaultLow
            constraints.append(snug)
        } else {
            constraints += [
                content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: insets.top),
                content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -insets.bottom)
            ]
        }
        NSLayoutConstraint.activate(constraints)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return scroll
    }

    /// Pinned actions: stacked in portrait, side by side (primary trailing)
    /// in landscape and in the slide-up. First CTA is the primary action.
    private func footer(stacked: Bool, compact: Bool, insets: UIEdgeInsets, measured: Bool = false) -> UIView? {
        guard !message.ctas.isEmpty else { return nil }
        var buttons: [UIButton] = []
        for (index, cta) in message.ctas.enumerated() {
            let button: UIButton = index == 0
                ? SurfacePrimaryButton(title: cta.label, theme: theme, compact: compact)
                : SurfaceSecondaryButton(title: cta.label, theme: theme, compact: compact)
            button.accessibilityLabel = cta.label
            makeCta(index, button)
            buttons.append(button)
        }
        let row = UIStackView(arrangedSubviews: stacked ? buttons : buttons.reversed())
        row.axis = stacked ? .vertical : .horizontal
        row.distribution = stacked ? .fill : .fillEqually
        row.alignment = stacked ? .fill : .top
        row.spacing = 10
        let content: UIView = measured ? self.measured(row) : row
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let natural = scroll.heightAnchor.constraint(equalTo: scroll.contentLayoutGuide.heightAnchor)
        natural.priority = UILayoutPriority(760)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -insets.bottom),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -(insets.left + insets.right)),
            scroll.heightAnchor.constraint(lessThanOrEqualToConstant: maxFooterHeight),
            natural
        ])
        scroll.setContentCompressionResistancePriority(UILayoutPriority(760), for: .vertical)
        return scroll
    }

    /// Wraps a view in a centred column capped at the readable measure.
    private func measured(_ view: UIView) -> UIView {
        let host = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        let fill = view.widthAnchor.constraint(equalTo: host.widthAnchor)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            view.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            view.widthAnchor.constraint(lessThanOrEqualToConstant: SurfaceMetrics.contentMaxWidth),
            view.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor),
            fill
        ])
        return host
    }

    private func padded(_ view: UIView, insets: UIEdgeInsets) -> UIView {
        let host = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: host.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -insets.bottom)
        ])
        return host
    }

    private func verticalStack(spacing: CGFloat) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = spacing
        return stack
    }
}
