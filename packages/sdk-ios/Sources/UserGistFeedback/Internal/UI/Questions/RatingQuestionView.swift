import Foundation
import UIKit

/// Renders the dashboard-selected rating style (RN RatingQuestion). Stars are
/// the wire default. The control is centred so preview and device match.
final class RatingQuestionView: UIView, QuestionView {
    private static let emoji = ["😡", "😕", "😐", "🙂", "😍"]
    static let controlSize: CGFloat = 48
    static let rowSpacing: CGFloat = 8

    private let question: Question.Rating
    private let theme: ResolvedTheme
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private var selectedValue: Int?
    // Match the API's supported scales and bound allocation for malformed data.
    private var scale: Int { question.scale == 10 ? 10 : 5 }
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.Rating, theme: ResolvedTheme, initialValue: Int? = nil) {
        self.question = question
        self.theme = theme
        super.init(frame: .zero)
        buildUI()
        setSelectedValue(initialValue)
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        guard let selectedValue else { return .none }
        return .number(Double(selectedValue))
    }

    private func buildUI() {
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Five per row keeps a 10-point scale centred and tappable on phones.
        let values = Array(1...scale)
        let rowSize = min(values.count, 5)
        for start in stride(from: 0, to: values.count, by: rowSize) {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = Self.rowSpacing
            for value in values[start..<min(start + rowSize, values.count)] {
                let button = makeButton(value: value)
                buttons.append(button)
                row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }

        if question.lowLabel != nil || question.highLabel != nil {
            let labels = UIStackView()
            labels.axis = .horizontal
            labels.distribution = .fillEqually
            labels.spacing = 16
            for (text, alignment) in [(question.lowLabel, NSTextAlignment.natural), (question.highLabel, .right)] {
                guard let text else { continue }
                let label = SurfaceLabel.make(text, font: theme.surfaceFont(13), color: theme.subtext)
                label.textAlignment = alignment
                labels.addArrangedSubview(label)
            }
            stack.setCustomSpacing(10, after: stack.arrangedSubviews.last ?? stack)
            stack.addArrangedSubview(labels)
            labels.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }

    private func makeButton(value: Int) -> UIButton {
        let button = UIButton(type: .custom)
        let size = Self.controlSize
        switch displayMode {
        case .stars:
            button.setTitle("★", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 34)
            button.widthAnchor.constraint(equalToConstant: size).isActive = true
        case .emoji:
            button.setTitle(Self.emoji[value - 1], for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 30)
            button.layer.cornerRadius = 26
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
        case .numeric:
            button.setTitle(String(value), for: .normal)
            button.titleLabel?.font = theme.surfaceFont(16, .bold)
            button.layer.borderWidth = 1.5
            button.layer.cornerRadius = theme.cappedRadius(12)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: size).isActive = true
        }
        button.heightAnchor.constraint(equalToConstant: displayMode == .emoji ? 52 : size).isActive = true
        button.tag = value
        button.accessibilityLabel = "Rate \(value)"
        button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func didTap(_ sender: UIButton) {
        setSelectedValue(sender.tag)
        Haptics.impactLight()
        onValueChange?(currentAnswer)
    }

    func setSelectedValue(_ value: Int?) {
        selectedValue = value.flatMap { (1...scale).contains($0) ? $0 : nil }
        for button in buttons {
            let isSelected = button.tag == selectedValue
            switch displayMode {
            case .stars:
                let isFilled = selectedValue.map { button.tag <= $0 } ?? false
                button.setTitleColor(isFilled ? theme.primary : theme.text.withAlphaComponent(0.16), for: .normal)
            case .emoji:
                button.backgroundColor = isSelected ? theme.tint : .clear
                button.alpha = selectedValue == nil || isSelected ? 1 : 0.4
            case .numeric:
                button.backgroundColor = isSelected ? theme.primary : .clear
                button.layer.borderColor = (isSelected ? theme.primary : theme.border).cgColor
                button.setTitleColor(isSelected ? theme.onPrimary : theme.text, for: .normal)
            }
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    private var displayMode: Question.Rating.Display {
        let requested = question.display ?? .stars
        return requested == .emoji && question.scale != 5 ? .stars : requested
    }
}
