import Foundation
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/SurfacePrimitives.tsx
//
// Content primitives shared by feedback questions: title block, selectable
// choice row and text field. Theme colours only, no fixed greys.

enum SurfaceQuestionHeader {
    /// Optional image, title (20/26 bold) and subtitle (15/21), 16pt below.
    static func make(
        title: String,
        subtitle: String?,
        imageURL: URL?,
        theme: ResolvedTheme,
        centered: Bool
    ) -> (view: UIStackView, title: UILabel, subtitle: UILabel?) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        if let imageURL {
            let image = SurfaceRemoteImageView(url: imageURL, radius: max(8, theme.radius - 6))
            stack.addArrangedSubview(image)
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 9.0 / 16.0).isActive = true
            stack.setCustomSpacing(16, after: image)
        }
        let titleLabel = SurfaceLabel.make(title, font: theme.surfaceFont(20, .bold), color: theme.text,
                                           lineHeight: 26)
        titleLabel.textAlignment = centered ? .center : .natural
        titleLabel.accessibilityTraits = .header
        stack.addArrangedSubview(titleLabel)
        var subtitleLabel: UILabel?
        if let subtitle, !subtitle.isEmpty {
            stack.setCustomSpacing(6, after: titleLabel)
            let label = SurfaceLabel.make(subtitle, font: theme.surfaceFont(15), color: theme.subtext, lineHeight: 21)
            label.textAlignment = centered ? .center : .natural
            stack.addArrangedSubview(label)
            subtitleLabel = label
        }
        return (stack, titleLabel, subtitleLabel)
    }
}

/// Multi-line label that wraps at its laid-out width on the first pass, so
/// titles never collapse to one truncated line inside stacks and scrollers.
final class SurfaceWrappingLabel: UILabel {
    override var bounds: CGRect {
        didSet {
            guard abs(bounds.width - preferredMaxLayoutWidth) > 0.5, bounds.width > 0 else { return }
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

enum SurfaceLabel {
    static func make(_ text: String, font: UIFont, color: UIColor, lineHeight: CGFloat? = nil) -> UILabel {
        let label = SurfaceWrappingLabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = font
        label.textColor = color
        label.text = text
        if let lineHeight {
            let style = NSMutableParagraphStyle()
            let scaled = UIFontMetrics.default.scaledValue(for: lineHeight)
            style.minimumLineHeight = scaled
            style.maximumLineHeight = scaled
            label.attributedText = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style
            ])
        }
        return label
    }
}

/// Selectable row: tinted fill, primary border and a radio/checkbox indicator.
/// Never a solid flood of the brand colour.
final class SurfaceChoiceRow: UIButton {
    enum Kind { case radio, checkbox }

    private let theme: ResolvedTheme
    private let kind: Kind
    private let indicator = UIView()
    private let mark = CAShapeLayer()
    private let label: UILabel

    var isChosen = false { didSet { refresh() } }

    init(label text: String, kind: Kind, theme: ResolvedTheme) {
        self.theme = theme
        self.kind = kind
        label = SurfaceLabel.make(text, font: theme.surfaceFont(16, .medium), color: theme.text, lineHeight: 21)
        super.init(frame: .zero)
        accessibilityLabel = text
        layer.borderWidth = 1.5
        layer.cornerRadius = theme.cappedRadius(16)
        label.isUserInteractionEnabled = false
        indicator.isUserInteractionEnabled = false
        indicator.layer.borderWidth = 1.75
        indicator.layer.cornerRadius = kind == .radio ? 11 : 7
        indicator.layer.addSublayer(mark)
        let row = UIStackView(arrangedSubviews: [label, indicator])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            indicator.widthAnchor.constraint(equalToConstant: 22),
            indicator.heightAnchor.constraint(equalToConstant: 22)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { refresh() }
    }

    private func refresh() {
        let accent = theme.primary
        layer.borderColor = (isChosen ? accent : theme.border).cgColor
        backgroundColor = isChosen ? theme.tint : (isHighlighted ? theme.fill : .clear)
        indicator.layer.borderColor = (isChosen ? accent : theme.text.withAlphaComponent(0.25)).cgColor
        indicator.backgroundColor = isChosen && kind == .checkbox ? accent : .clear
        mark.isHidden = !isChosen
        if kind == .radio {
            mark.path = UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 10, height: 10)).cgPath
            mark.fillColor = accent.cgColor
            mark.strokeColor = nil
        } else {
            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: 6.5, y: 11.2))
            tick.addLine(to: CGPoint(x: 9.6, y: 14.2))
            tick.addLine(to: CGPoint(x: 15.6, y: 8.2))
            mark.path = tick.cgPath
            mark.fillColor = UIColor.clear.cgColor
            mark.strokeColor = theme.onPrimary.cgColor
            mark.lineWidth = 2
            mark.lineCap = .round
            mark.lineJoin = .round
        }
        let base: UIAccessibilityTraits = .button
        accessibilityTraits = isChosen ? base.union(.selected) : base
    }
}

/// Soft text field: neutral fill, primary border while focused, placeholder
/// and an optional character count. Multiline by default.
final class SurfaceTextField: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let placeholder = UILabel()
    private let counter = UILabel()
    private let theme: ResolvedTheme
    private let maxLength: Int?
    var onChange: ((String) -> Void)?

    init(theme: ResolvedTheme, placeholder text: String?, maxLength: Int?, minHeight: CGFloat,
         accessibilityLabel: String) {
        self.theme = theme
        self.maxLength = maxLength.flatMap { $0 > 0 ? $0 : nil }
        super.init(frame: .zero)
        textView.delegate = self
        textView.font = theme.surfaceFont(16)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = theme.text
        textView.tintColor = theme.primary
        textView.backgroundColor = theme.fill
        textView.layer.cornerRadius = theme.cappedRadius(14)
        textView.layer.borderWidth = 1.5
        textView.layer.borderColor = UIColor.clear.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.accessibilityLabel = accessibilityLabel
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = text
        placeholder.font = textView.font
        placeholder.numberOfLines = 0
        placeholder.textColor = theme.subtext.withAlphaComponent(0.8)
        placeholder.isAccessibilityElement = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        counter.font = theme.surfaceFont(12)
        counter.textAlignment = .right
        counter.isHidden = self.maxLength == nil
        counter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        textView.addSubview(placeholder)
        addSubview(counter)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 15),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholder.widthAnchor.constraint(equalTo: textView.widthAnchor, constant: -30),
            counter.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: self.maxLength == nil ? 0 : 6),
            counter.trailingAnchor.constraint(equalTo: trailingAnchor),
            counter.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        textView.isScrollEnabled = false
        updateCounter()
    }

    required init?(coder: NSCoder) { nil }

    var text: String { textView.text ?? "" }

    func textViewDidBeginEditing(_ textView: UITextView) {
        textView.layer.borderColor = theme.primary.cgColor
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        textView.layer.borderColor = UIColor.clear.cgColor
    }

    func textViewDidChange(_ textView: UITextView) {
        if let maxLength, textView.text.count > maxLength {
            textView.text = String(textView.text.prefix(maxLength))
        }
        updateCounter()
        onChange?(textView.text)
    }

    private func updateCounter() {
        placeholder.isHidden = !text.isEmpty
        guard let maxLength else { counter.text = nil; return }
        counter.text = "\(text.count)/\(maxLength)"
        counter.textColor = Double(text.count) >= Double(maxLength) * 0.9 ? theme.text : theme.subtext
    }
}

/// Remote image with a themed placeholder; never dropped on slow loads.
final class SurfaceRemoteImageView: UIImageView {
    private var task: URLSessionDataTask?

    init(url: URL, radius: CGFloat, placeholder: UIColor? = nil) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = radius
        backgroundColor = placeholder
        accessibilityIgnoresInvertColors = true
        isAccessibilityElement = false
        task = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return }
            guard let data, data.count <= 10 * 1_024 * 1_024, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.image = image }
        }
        task?.resume()
    }

    required init?(coder: NSCoder) { nil }

    deinit { task?.cancel() }
}
