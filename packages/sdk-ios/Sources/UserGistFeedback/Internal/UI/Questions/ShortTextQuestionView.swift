import Foundation
import UIKit

/// Multiline short-text answer matching the React Native prompt renderer.
final class ShortTextQuestionView: UIView, QuestionView, UITextViewDelegate {
    private let question: Question.ShortText
    private let theme: ResolvedTheme
    private let textView = UITextView()
    private let placeholder = UILabel()
    var onValueChange: ((PromptAnswerValue) -> Void)?

    init(question: Question.ShortText, theme: ResolvedTheme) {
        self.question = question
        self.theme = theme
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    var currentAnswer: PromptAnswerValue {
        let raw = textView.text ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        return .text(trimmed)
    }

    private func buildUI() {
        textView.font = theme.font
        textView.textColor = theme.text
        textView.backgroundColor = theme.background
        textView.delegate = self
        textView.layer.borderWidth = 1
        textView.layer.borderColor = theme.border.cgColor
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.accessibilityLabel = "Feedback text answer"

        placeholder.text = question.placeholder
        placeholder.font = theme.font
        placeholder.textColor = theme.subtext
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textView)
        textView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10)
        ])
    }

    func textViewDidChange(_ textView: UITextView) {
        if let max = question.maxLength, max > 0, textView.text.count > max {
            textView.text = String(textView.text.prefix(max))
        }
        placeholder.isHidden = !textView.text.isEmpty
        onValueChange?(currentAnswer)
    }
}

/// Minimal contract all question views satisfy.
protocol QuestionView: UIView {
    var currentAnswer: PromptAnswerValue { get }
    var onValueChange: ((PromptAnswerValue) -> Void)? { get set }
}
