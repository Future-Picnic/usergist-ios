import Foundation
import UIKit

/// NPS scale (RN NpsQuestion).
/// - Wide (the question's own content width >= 524, e.g. the 560pt landscape
///   column): the 0–10 row, each numeral centred in its cell, end labels below.
/// - Narrow: a vertical list with 10 at the top so no number is squeezed
///   below a usable touch target.
/// The decision uses the surface's actual content width, never the window,
/// so a narrow sheet or preview on a wide screen keeps the readable list.
final class NpsQuestionView: UIView, QuestionView {
    static let wideThreshold: CGFloat = 524

    static func isWide(contentWidth: CGFloat) -> Bool { contentWidth >= wideThreshold }

    private let question: Question.Nps
    private let theme: ResolvedTheme
    private let root = UIStackView()
    private let scaleHost = UIStackView()
    private let followUpStack = UIStackView()
    private var cells: [NpsCell] = []
    private var selectedValue: Int?
    private var followUpField: SurfaceTextField?
    var onValueChange: ((PromptAnswerValue) -> Void)?
    var onFollowUpChange: ((String) -> Void)?

    /// Rebuilds the scale when it flips; `onWideChange` lets the host re-align
    /// the title and re-measure the sheet.
    var wide: Bool = false {
        didSet {
            guard wide != oldValue else { return }
            buildScale()
            onWideChange?(wide)
        }
    }
    var onWideChange: ((Bool) -> Void)?

    override func layoutSubviews() {
        if bounds.width > 0 { wide = Self.isWide(contentWidth: bounds.width) }
        super.layoutSubviews()
    }

    private var lowLabel: String { question.lowLabel ?? "Not at all likely" }
    private var highLabel: String { question.highLabel ?? "Extremely likely" }

    init(question: Question.Nps, theme: ResolvedTheme, wide: Bool = false) {
        self.question = question
        self.theme = theme
        self.wide = wide
        super.init(frame: .zero)
        root.axis = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        root.addArrangedSubview(scaleHost)
        buildFollowUp()
        root.addArrangedSubview(followUpStack)
        buildScale()
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        guard let selectedValue else { return .none }
        return .number(Double(selectedValue))
    }

    private func buildScale() {
        scaleHost.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cells = []
        scaleHost.axis = .vertical
        scaleHost.spacing = wide ? 10 : 6
        let values = wide ? Array(0...10) : Array((0...10).reversed())
        let container = UIStackView()
        container.axis = wide ? .horizontal : .vertical
        container.distribution = wide ? .fillEqually : .fill
        container.spacing = 6
        for value in values {
            let endpoint = wide ? nil : (value == 10 ? highLabel : value == 0 ? lowLabel : nil)
            let cell = NpsCell(value: value, endpoint: endpoint, wide: wide, theme: theme)
            cell.accessibilityLabel = "Score \(value)" + (value == 10 ? ", \(highLabel)" : value == 0 ? ", \(lowLabel)" : "")
            cell.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
            cell.isChosen = value == selectedValue
            cells.append(cell)
            container.addArrangedSubview(cell)
        }
        scaleHost.addArrangedSubview(container)
        if wide {
            let labels = UIStackView()
            labels.axis = .horizontal
            labels.distribution = .fillEqually
            labels.spacing = 16
            let low = SurfaceLabel.make(lowLabel, font: theme.surfaceFont(13), color: theme.subtext)
            let high = SurfaceLabel.make(highLabel, font: theme.surfaceFont(13), color: theme.subtext)
            high.textAlignment = .right
            labels.addArrangedSubview(low)
            labels.addArrangedSubview(high)
            scaleHost.addArrangedSubview(labels)
        }
    }

    @objc private func didTap(_ sender: UIButton) {
        guard let cell = sender as? NpsCell else { return }
        selectedValue = cell.value
        Haptics.impactLight()
        cells.forEach { $0.isChosen = $0.value == selectedValue }
        if question.followUp?.isEmpty == false { followUpStack.isHidden = false }
        onValueChange?(currentAnswer)
    }

    private func buildFollowUp() {
        followUpStack.axis = .vertical
        followUpStack.spacing = 10
        followUpStack.isHidden = true
        followUpStack.isLayoutMarginsRelativeArrangement = true
        followUpStack.layoutMargins = UIEdgeInsets(top: 24, left: 0, bottom: 0, right: 0)
        guard let prompt = question.followUp, !prompt.isEmpty else { return }
        followUpStack.addArrangedSubview(SurfaceLabel.make(prompt, font: theme.surfaceFont(16, .semibold),
                                                           color: theme.text))
        let field = SurfaceTextField(theme: theme, placeholder: "Tell us more", maxLength: nil,
                                     minHeight: 80, accessibilityLabel: prompt)
        field.onChange = { [weak self] text in self?.onFollowUpChange?(text) }
        followUpStack.addArrangedSubview(field)
        followUpField = field
    }
}

/// One NPS score cell. Wide cells centre the numeral; tall rows keep a fixed
/// number column so the endpoint labels line up.
private final class NpsCell: UIButton {
    let value: Int
    private let theme: ResolvedTheme
    private let number = UILabel()
    private let endpoint: UILabel?

    var isChosen = false { didSet { refresh() } }

    init(value: Int, endpoint text: String?, wide: Bool, theme: ResolvedTheme) {
        self.value = value
        self.theme = theme
        endpoint = text.map { SurfaceLabel.make($0, font: theme.surfaceFont(14), color: theme.subtext) }
        super.init(frame: .zero)
        layer.borderWidth = 1.5
        layer.cornerRadius = theme.cappedRadius(12)
        number.text = String(value)
        number.font = theme.surfaceFont(16, .bold).withMonospacedDigits()
        number.adjustsFontForContentSizeCategory = true
        number.isUserInteractionEnabled = false
        number.translatesAutoresizingMaskIntoConstraints = false
        addSubview(number)
        if wide {
            number.textAlignment = .center
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 48),
                number.centerXAnchor.constraint(equalTo: centerXAnchor),
                number.centerYAnchor.constraint(equalTo: centerYAnchor),
                number.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2)
            ])
        } else {
            NSLayoutConstraint.activate([
                heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                number.centerYAnchor.constraint(equalTo: centerYAnchor),
                number.widthAnchor.constraint(greaterThanOrEqualToConstant: 22)
            ])
            if let endpoint {
                endpoint.isUserInteractionEnabled = false
                endpoint.translatesAutoresizingMaskIntoConstraints = false
                addSubview(endpoint)
                NSLayoutConstraint.activate([
                    endpoint.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 10),
                    endpoint.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
                    endpoint.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                    endpoint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
                ])
            }
        }
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { refresh() }
    }

    private func refresh() {
        layer.borderColor = (isChosen ? theme.primary : theme.border).cgColor
        backgroundColor = isChosen ? theme.primary : (isHighlighted ? theme.fill : .clear)
        number.textColor = isChosen ? theme.onPrimary : theme.text
        endpoint?.textColor = isChosen ? theme.onPrimary : theme.subtext
        accessibilityTraits = isChosen ? [.button, .selected] : .button
    }
}

private extension UIFont {
    func withMonospacedDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.featureIdentifier: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.typeIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
