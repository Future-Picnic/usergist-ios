import Foundation
import UIKit

/// Single- or multi-select list on the shared choice row (radio / checkbox).
final class MultipleChoiceQuestionView: UIView, QuestionView {
    private let question: Question.MultipleChoice
    private var rows: [SurfaceChoiceRow] = []
    private var selectedIds: [String] = []
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.MultipleChoice, theme: ResolvedTheme) {
        self.question = question
        super.init(frame: .zero)
        let stack = UIStackView()
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
        let kind: SurfaceChoiceRow.Kind = question.multiSelect == true ? .checkbox : .radio
        for (index, option) in question.options.enumerated() {
            let row = SurfaceChoiceRow(label: option.label, kind: kind, theme: theme)
            row.tag = index
            row.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
            rows.append(row)
            stack.addArrangedSubview(row)
        }
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        selectedIds.isEmpty ? .none : .choices(selectedIds)
    }

    @objc private func didTap(_ sender: UIButton) {
        guard question.options.indices.contains(sender.tag) else { return }
        let option = question.options[sender.tag]
        Haptics.impactLight()
        if question.multiSelect == true {
            selectedIds = selectedIds.contains(option.id)
                ? selectedIds.filter { $0 != option.id }
                : selectedIds + [option.id]
        } else {
            selectedIds = [option.id]
        }
        for (index, row) in rows.enumerated() {
            row.isChosen = selectedIds.contains(question.options[index].id)
        }
        onValueChange?(currentAnswer)
    }
}
