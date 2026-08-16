import Foundation
import UIKit

/// Short free-text answer. Backed by `UITextField` (single line is enough for
/// the "short text" contract; the dashboard "long answer" is a separate type
/// out of scope for v1).
final class ShortTextQuestionView: UIView, QuestionView, UITextFieldDelegate {
    private let question: Question.ShortText
    private let theme: ResolvedTheme
    private let textField = UITextField()
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.ShortText, theme: ResolvedTheme) {
        self.question = question
        self.theme = theme
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        let raw = textField.text ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        return .text(trimmed)
    }

    private func buildUI() {
        textField.placeholder = question.placeholder
        textField.borderStyle = .none
        textField.font = theme.font
        textField.textColor = theme.text
        textField.backgroundColor = theme.background
        textField.delegate = self
        textField.layer.borderWidth = 1
        textField.layer.borderColor = theme.border.cgColor
        textField.layer.cornerRadius = min(theme.radius * 0.5, 12)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        let padding = UIView()
        padding.translatesAutoresizingMaskIntoConstraints = false
        padding.widthAnchor.constraint(equalToConstant: 12).isActive = true
        textField.leftView = padding
        textField.leftViewMode = .always

        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func editingChanged() {
        // Enforce `maxLength` if set.
        if let max = question.maxLength, max > 0, let text = textField.text, text.count > max {
            textField.text = String(text.prefix(max))
        }
        onValueChange?(currentAnswer)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

/// Minimal contract all question views satisfy.
protocol QuestionView: UIView {
    var currentAnswer: PromptAnswerValue { get }
    var onValueChange: ((PromptAnswerValue) -> Void)? { get set }
}
