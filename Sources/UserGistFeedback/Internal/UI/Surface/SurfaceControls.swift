import Foundation
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/SurfaceControls.tsx
//
// Shared UIKit chrome for the feedback sheet and in-app messages: one Close,
// one Back, one primary action and one header layout.
//   - Close is always the leading header control.
//   - Portrait: the primary action sits in a footer below the content.
//   - Landscape: the primary action moves to the trailing side of the header,
//     so the content and the keyboard keep the remaining height.

/// Close (drawn thin cross) or Back (drawn chevron) on a 32pt themed wash,
/// inside a 44pt touch target.
final class SurfaceIconButton: UIButton {
    enum Glyph { case close, back }

    private let face = UIView()
    private let glyphLayer = CAShapeLayer()
    private let glyph: Glyph

    init(glyph: Glyph, color: UIColor, label: String? = nil) {
        self.glyph = glyph
        super.init(frame: .zero)
        accessibilityLabel = label ?? (glyph == .close ? "Close" : "Back")
        face.isUserInteractionEnabled = false
        face.backgroundColor = color.withAlphaComponent(0.08)
        face.layer.cornerRadius = SurfaceMetrics.iconFace / 2
        face.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)
        glyphLayer.strokeColor = color.cgColor
        glyphLayer.fillColor = UIColor.clear.cgColor
        glyphLayer.lineWidth = 1.75
        glyphLayer.lineCap = .round
        glyphLayer.lineJoin = .round
        face.layer.addSublayer(glyphLayer)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: SurfaceMetrics.iconHit),
            heightAnchor.constraint(equalToConstant: SurfaceMetrics.iconHit),
            face.widthAnchor.constraint(equalToConstant: SurfaceMetrics.iconFace),
            face.heightAnchor.constraint(equalToConstant: SurfaceMetrics.iconFace),
            face.centerXAnchor.constraint(equalTo: centerXAnchor),
            face.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let c = CGPoint(x: SurfaceMetrics.iconFace / 2, y: SurfaceMetrics.iconFace / 2)
        let path = UIBezierPath()
        switch glyph {
        case .close:
            let h: CGFloat = 13 / (2 * 2.squareRoot())
            path.move(to: CGPoint(x: c.x - h, y: c.y - h))
            path.addLine(to: CGPoint(x: c.x + h, y: c.y + h))
            path.move(to: CGPoint(x: c.x + h, y: c.y - h))
            path.addLine(to: CGPoint(x: c.x - h, y: c.y + h))
        case .back:
            let s: CGFloat = 4.5
            path.move(to: CGPoint(x: c.x + s * 0.5, y: c.y - s))
            path.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y))
            path.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y + s))
        }
        glyphLayer.frame = face.bounds
        glyphLayer.path = path.cgPath
    }
}

/// Solid primary action. Labels wrap instead of truncating; disabled uses a
/// neutral fill, never a faded brand colour; loading shows a spinner.
final class SurfacePrimaryButton: UIButton {
    private let theme: ResolvedTheme
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var lastWidth: CGFloat = 0

    var compact: Bool { didSet { applyMetrics() } }
    var isLoading = false { didSet { refresh() } }
    /// Logical enabled state, separate from loading (which also blocks taps).
    var isActionEnabled = true { didSet { refresh() } }

    init(title: String, theme: ResolvedTheme, compact: Bool = false) {
        self.theme = theme
        self.compact = compact
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.numberOfLines = 0
        titleLabel?.lineBreakMode = .byWordWrapping
        titleLabel?.textAlignment = .center
        titleLabel?.adjustsFontForContentSizeCategory = true
        spinner.hidesWhenStopped = true
        spinner.color = theme.onPrimary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        applyMetrics()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.82 : 1 }
    }

    private func applyMetrics() {
        titleLabel?.font = theme.surfaceFont(compact ? 15 : 16, .bold)
        contentEdgeInsets = compact
            ? UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
            : UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        layer.cornerRadius = compact ? 22 : 25
        invalidateIntrinsicContentSize()
    }

    private func refresh() {
        let inactive = !isActionEnabled && !isLoading
        isEnabled = isActionEnabled && !isLoading
        backgroundColor = inactive ? theme.fill : theme.primary
        let label = inactive ? theme.disabledLabel : theme.onPrimary
        for state: UIControl.State in [.normal, .disabled, .highlighted] {
            setTitleColor(isLoading ? .clear : label, for: state)
        }
        isLoading ? spinner.startAnimating() : spinner.stopAnimating()
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        accessibilityValue = isLoading ? "In progress" : nil
    }

    override var intrinsicContentSize: CGSize {
        let insets = contentEdgeInsets
        let minHeight = compact ? SurfaceMetrics.compactMinHeight : SurfaceMetrics.primaryMinHeight
        let available = bounds.width > 0 ? bounds.width - insets.left - insets.right : CGFloat.greatestFiniteMagnitude
        let label = titleLabel?.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)) ?? .zero
        let width = max(compact ? SurfaceMetrics.compactMinWidth : 0, ceil(label.width) + insets.left + insets.right)
        return CGSize(width: width, height: max(minHeight, ceil(label.height) + insets.top + insets.bottom))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(compact ? 22 : 25, bounds.height / 2)
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// Quiet secondary action: theme text colour with a neutral outline, so it
/// stays readable when the brand colour is light (yellow, mint).
final class SurfaceSecondaryButton: UIButton {
    private let theme: ResolvedTheme
    private let compact: Bool
    private var lastWidth: CGFloat = 0

    init(title: String, theme: ResolvedTheme, compact: Bool = false) {
        self.theme = theme
        self.compact = compact
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        setTitleColor(theme.text, for: .normal)
        titleLabel?.font = theme.surfaceFont(compact ? 15 : 16, .bold)
        titleLabel?.numberOfLines = 0
        titleLabel?.textAlignment = .center
        titleLabel?.adjustsFontForContentSizeCategory = true
        contentEdgeInsets = compact
            ? UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
            : UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        layer.cornerRadius = compact ? 22 : 25
        outline.fillColor = UIColor.clear.cgColor
        outline.strokeColor = theme.quietOutline.cgColor
        outline.lineWidth = 1.5
        layer.addSublayer(outline)
    }

    /// Explicit rounded outline: crisp pill ends at any height.
    private let outline = CAShapeLayer()

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? theme.fill : .clear }
    }

    override var intrinsicContentSize: CGSize {
        let insets = contentEdgeInsets
        let available = bounds.width > 0 ? bounds.width - insets.left - insets.right : CGFloat.greatestFiniteMagnitude
        let label = titleLabel?.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)) ?? .zero
        let minHeight = compact ? SurfaceMetrics.compactMinHeight : SurfaceMetrics.primaryMinHeight
        return CGSize(width: ceil(label.width) + insets.left + insets.right,
                      height: max(minHeight, ceil(label.height) + insets.top + insets.bottom))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Never exceed half the height, or the outline's rounded ends clip.
        let radius = min(compact ? 22 : 25, bounds.height / 2)
        layer.cornerRadius = radius
        outline.frame = bounds
        outline.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
                                    cornerRadius: max(0, radius - 0.75)).cgPath
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// Three-slot header. Leading and trailing size to their content; the centre
/// takes the remaining width. Long trailing labels wrap within 320pt.
final class SurfaceHeaderView: UIView {
    let leading = UIStackView()
    let centerSlot = UIView()
    let trailing = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        centerSlot.setContentHuggingPriority(.defaultLow, for: .horizontal)
        centerSlot.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for side in [leading, trailing] {
            side.axis = .horizontal
            side.alignment = .center
            side.spacing = 4
            side.setContentHuggingPriority(.required, for: .horizontal)
            side.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let row = UIStackView(arrangedSubviews: [leading, centerSlot, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SurfaceMetrics.headerMinHeight),
            leading.widthAnchor.constraint(greaterThanOrEqualToConstant: SurfaceMetrics.iconHit),
            trailing.widthAnchor.constraint(greaterThanOrEqualToConstant: SurfaceMetrics.iconHit),
            trailing.widthAnchor.constraint(lessThanOrEqualToConstant: SurfaceMetrics.trailingMaxWidth)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setCenter(_ view: UIView?) {
        centerSlot.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        centerSlot.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerSlot.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerSlot.centerYAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: centerSlot.leadingAnchor),
            view.topAnchor.constraint(greaterThanOrEqualTo: centerSlot.topAnchor)
        ])
    }

    func setTrailing(_ views: [UIView]) {
        trailing.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { trailing.addArrangedSubview($0) }
    }
}
