import Foundation
import UIKit

/// Renders a 1-5 or 1-10 rating scale as a horizontal stack of buttons.
final class RatingQuestionView: UIView, QuestionView {
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
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 48)
        ])

        for i in 1...max(2, question.scale) {
            let button = makeButton(value: i)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    private func makeButton(value: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(String(value), for: .normal)
        button.titleLabel?.font = theme.boldFont
        button.setTitleColor(theme.text, for: .normal)
        button.backgroundColor = theme.background
        button.layer.borderWidth = 1
        button.layer.borderColor = theme.border.cgColor
        button.layer.cornerRadius = min(theme.radius * 0.5, 12)
        button.tag = value
        button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func didTap(_ sender: UIButton) {
        selectedValue = sender.tag
        Haptics.impactLight()
        for button in buttons {
            let isSelected = button.tag == sender.tag
            button.backgroundColor = isSelected ? theme.primary : theme.background
            button.setTitleColor(isSelected ? .white : theme.text, for: .normal)
        }
        onValueChange?(currentAnswer)
    }
}
