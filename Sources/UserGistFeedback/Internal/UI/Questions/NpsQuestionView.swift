import Foundation
import UIKit

/// NPS 0-10 renderer matching the React Native vertical score list.
final class NpsQuestionView: UIView, QuestionView, UITextViewDelegate {
    private let question: Question.Nps
    private let theme: ResolvedTheme
    private let vStack = UIStackView()
    private var buttons: [UIButton] = []
    private var selectedValue: Int?
    private let followUpStack = UIStackView()
    private let followUpInput = UITextView()
    private let followUpPlaceholder = UILabel()
    var onValueChange: ((PromptAnswerValue) -> Void)?
    var onFollowUpChange: ((String) -> Void)?

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
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for value in stride(from: 10, through: 0, by: -1) {
            let button = makeButton(value: value)
            buttons.append(button)
            vStack.addArrangedSubview(button)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }

        buildFollowUp()
        vStack.addArrangedSubview(followUpStack)
    }

    private func makeButton(value: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = theme.background
        button.layer.borderWidth = 1
        button.layer.borderColor = theme.border.cgColor
        button.layer.cornerRadius = 12
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        button.tag = value + 1 // avoid 0 collision
        button.accessibilityLabel = "Score \(value)"
        applyTitle(to: button, selected: false)
        button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func didTap(_ sender: UIButton) {
        let value = sender.tag - 1
        selectedValue = value
        Haptics.impactLight()
        refreshStyles()
        followUpStack.isHidden = question.followUp?.isEmpty != false
        onValueChange?(currentAnswer)
    }

    private func buildFollowUp() {
        followUpStack.axis = .vertical
        followUpStack.spacing = 8
        followUpStack.isHidden = true

        let prompt = UILabel()
        prompt.text = question.followUp
        prompt.textColor = theme.text
        prompt.font = theme.font
        prompt.textAlignment = .center
        prompt.numberOfLines = 0
        followUpStack.addArrangedSubview(prompt)

        followUpInput.delegate = self
        followUpInput.font = theme.font
        followUpInput.textColor = theme.text
        followUpInput.backgroundColor = theme.background
        followUpInput.layer.borderWidth = 1
        followUpInput.layer.borderColor = theme.border.cgColor
        followUpInput.layer.cornerRadius = 12
        followUpInput.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        followUpInput.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        followUpInput.accessibilityLabel = "NPS follow-up answer"
        followUpStack.addArrangedSubview(followUpInput)

        followUpPlaceholder.text = "Tell us more..."
        followUpPlaceholder.textColor = theme.subtext
        followUpPlaceholder.font = theme.font
        followUpPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        followUpInput.addSubview(followUpPlaceholder)
        NSLayoutConstraint.activate([
            followUpPlaceholder.leadingAnchor.constraint(equalTo: followUpInput.leadingAnchor, constant: 13),
            followUpPlaceholder.topAnchor.constraint(equalTo: followUpInput.topAnchor, constant: 10)
        ])
    }

    private func refreshStyles() {
        for button in buttons {
            let selected = button.tag - 1 == selectedValue
            button.backgroundColor = selected ? theme.primary : theme.background
            button.layer.borderColor = (selected ? theme.primary : theme.border).cgColor
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            applyTitle(to: button, selected: selected)
        }
    }

    private func applyTitle(to button: UIButton, selected: Bool) {
        let value = button.tag - 1
        let endpoint: String?
        if value == 10 {
            endpoint = question.highLabel ?? "Extremely likely"
        } else if value == 0 {
            endpoint = question.lowLabel ?? "Not at all likely"
        } else {
            endpoint = nil
        }
        let number = String(value)
        let full = endpoint.map { "\(number)    \($0)" } ?? number
        let foreground = selected ? theme.background : theme.text
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [.font: theme.font, .foregroundColor: foreground]
        )
        attributed.addAttributes(
            [.font: theme.boldFont],
            range: NSRange(location: 0, length: number.utf16.count)
        )
        if endpoint != nil, !selected {
            attributed.addAttributes(
                [.foregroundColor: theme.subtext, .font: UIFont.systemFont(ofSize: 13)],
                range: NSRange(location: number.utf16.count + 4, length: full.utf16.count - number.utf16.count - 4)
            )
        }
        button.setAttributedTitle(attributed, for: .normal)
    }

    func textViewDidChange(_ textView: UITextView) {
        followUpPlaceholder.isHidden = !textView.text.isEmpty
        onFollowUpChange?(textView.text)
    }
}
