import Foundation
import UIKit

/// Renders the dashboard-selected rating style. Stars are the wire default.
final class RatingQuestionView: UIView, QuestionView {
    private static let emoji = ["😡", "😕", "😐", "🙂", "😍"]

    private let question: Question.Rating
    private let theme: ResolvedTheme
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private var selectedValue: Int?
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.Rating, theme: ResolvedTheme) {
        self.question = question
        self.theme = theme
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        guard let selectedValue else { return .none }
        return .number(Double(selectedValue))
    }

    private func buildUI() {
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let values = Array(1...max(2, question.scale))
        let rowSize = values.count > 5 ? 5 : values.count
        for start in stride(from: 0, to: values.count, by: rowSize) {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8
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
            labels.distribution = .equalSpacing
            let low = UILabel()
            low.text = question.lowLabel
            low.textColor = theme.subtext
            low.font = UIFont.systemFont(ofSize: 12)
            let high = UILabel()
            high.text = question.highLabel
            high.textColor = theme.subtext
            high.font = UIFont.systemFont(ofSize: 12)
            labels.addArrangedSubview(low)
            labels.addArrangedSubview(high)
            labels.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            stack.addArrangedSubview(labels)
        }
    }

    private func makeButton(value: Int) -> UIButton {
        let button = UIButton(type: .system)
        switch displayMode {
        case .stars:
            button.setTitle("★", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .regular)
            button.setTitleColor(theme.border, for: .normal)
            button.backgroundColor = .clear
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        case .emoji:
            button.setTitle(Self.emoji[value - 1], for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 28)
            button.backgroundColor = .clear
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        case .numeric:
            button.setTitle(String(value), for: .normal)
            button.titleLabel?.font = theme.boldFont
            button.setTitleColor(theme.text, for: .normal)
            button.backgroundColor = theme.background
            button.layer.borderWidth = 1
            button.layer.borderColor = theme.border.cgColor
            button.layer.cornerRadius = 20
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        button.tag = value
        button.accessibilityLabel = "Rate \(value)"
        button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func didTap(_ sender: UIButton) {
        selectedValue = sender.tag
        Haptics.impactLight()
        for button in buttons {
            switch displayMode {
            case .stars:
                button.setTitleColor(
                    button.tag <= sender.tag ? theme.primary : theme.border,
                    for: .normal
                )
            case .emoji:
                button.alpha = button.tag == sender.tag ? 1 : 0.35
            case .numeric:
                let isSelected = button.tag == sender.tag
                button.backgroundColor = isSelected ? theme.primary : theme.background
                button.setTitleColor(isSelected ? theme.background : theme.text, for: .normal)
            }
            button.accessibilityTraits = button.tag == sender.tag ? [.button, .selected] : .button
        }
        onValueChange?(currentAnswer)
    }

    private var displayMode: Question.Rating.Display {
        let requested = question.display ?? .stars
        return requested == .emoji && question.scale != 5 ? .stars : requested
    }
}
