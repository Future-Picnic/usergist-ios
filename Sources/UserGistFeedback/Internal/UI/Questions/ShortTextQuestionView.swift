import Foundation
import UIKit

/// Multiline short-text answer on the shared soft field (RN ShortTextQuestion).
final class ShortTextQuestionView: UIView, QuestionView {
    private let question: Question.ShortText
    private let field: SurfaceTextField
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.ShortText, theme: ResolvedTheme) {
        self.question = question
        field = SurfaceTextField(
            theme: theme,
            placeholder: question.placeholder,
            maxLength: question.maxLength,
            minHeight: 96,
            accessibilityLabel: "Feedback text answer"
        )
        super.init(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        field.onChange = { [weak self] _ in
            guard let self else { return }
            self.onValueChange?(self.currentAnswer)
        }
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        let trimmed = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .none : .text(trimmed)
    }
}

/// Minimal contract all question views satisfy.
protocol QuestionView: UIView {
    var currentAnswer: PromptAnswerValue { get }
    var onValueChange: ((PromptAnswerValue) -> Void)? { get set }
}
