import Foundation
import UIKit

/// Renders single- or multi-select choice list as vertical stacked rows.
final class MultipleChoiceQuestionView: UIView, QuestionView {
    private let question: Question.MultipleChoice
    private let theme: ResolvedTheme
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private var selectedIds: [String] = []
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.MultipleChoice, theme: ResolvedTheme) {
        self.question = question
        self.theme = theme
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        selectedIds.isEmpty ? .none : .choices(selectedIds)
    }

    private func buildUI() {
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for (idx, option) in question.options.enumerated() {
            let button = makeButton(option: option, index: idx)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    private func makeButton(option: QuestionChoice, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(option.label, for: .normal)
        button.titleLabel?.font = theme.boldFont
        button.setTitleColor(theme.text, for: .normal)
        button.backgroundColor = theme.background
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        button.layer.borderWidth = 1
        button.layer.borderColor = theme.border.cgColor
        button.layer.cornerRadius = 14
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.tag = index
        button.accessibilityLabel = option.label
        button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func didTap(_ sender: UIButton) {
        let option = question.options[sender.tag]
        Haptics.impactLight()
        if question.multiSelect == true {
            if let index = selectedIds.firstIndex(of: option.id) {
                selectedIds.remove(at: index)
            } else {
                selectedIds.append(option.id)
            }
        } else {
            selectedIds = [option.id]
        }
        refreshStyles()
        onValueChange?(currentAnswer)
    }

    private func refreshStyles() {
        for (idx, button) in buttons.enumerated() {
            let option = question.options[idx]
            let isSelected = selectedIds.contains(option.id)
            button.backgroundColor = isSelected ? theme.primary : theme.background
            button.layer.borderColor = (isSelected ? theme.primary : theme.border).cgColor
            button.setTitleColor(isSelected ? theme.background : theme.text, for: .normal)
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}
