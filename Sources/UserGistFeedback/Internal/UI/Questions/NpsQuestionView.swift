import Foundation
import UIKit

/// NPS 0-10 renderer. Uses two rows of 6 and 5 buttons for readability.
final class NpsQuestionView: UIView, QuestionView {
    private let question: Question.Nps
    private let theme: ResolvedTheme
    private let vStack = UIStackView()
    private var buttons: [UIButton] = []
    private var selectedValue: Int?
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.Nps, theme: ResolvedTheme) {
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
        vStack.axis = .vertical
        vStack.spacing = 8
        vStack.distribution = .fillEqually
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let row1 = makeRow(values: Array(0...5))
        let row2 = makeRow(values: Array(6...10))
        vStack.addArrangedSubview(row1)
        vStack.addArrangedSubview(row2)
    }

    private func makeRow(values: [Int]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6
        for v in values {
            let button = makeButton(value: v)
            buttons.append(button)
            row.addArrangedSubview(button)
        }
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return row
    }

    private func makeButton(value: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(String(value), for: .normal)
        button.titleLabel?.font = theme.boldFont
        button.setTitleColor(theme.text, for: .normal)
        button.backgroundColor = theme.background
        button.layer.borderWidth = 1
        button.layer.borderColor = theme.border.cgColor
        button.layer.cornerRadius = min(theme.radius * 0.5, 10)
        button.tag = value + 1 // avoid 0 collision
        button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func didTap(_ sender: UIButton) {
        let value = sender.tag - 1
        selectedValue = value
        Haptics.impactLight()
        for button in buttons {
            let isSelected = button.tag - 1 == value
            button.backgroundColor = isSelected ? theme.primary : theme.background
            button.setTitleColor(isSelected ? .white : theme.text, for: .normal)
        }
        onValueChange?(currentAnswer)
    }
}
