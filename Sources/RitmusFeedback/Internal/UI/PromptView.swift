import Foundation
import UIKit

/// Root view assembled inside the bottom-sheet controller.
///
/// Lays out the question list vertically with title/subtitle and
/// primary/dismiss controls. Collects the answer values and hands them
/// back via the completion callback.
final class PromptView: UIView {
    enum Outcome {
        case submitted(answers: [PromptAnswerInfo])
        case dismissed
    }

    private let prompt: ClientPrompt
    private let theme: ResolvedTheme
    private let onFinish: (Outcome) -> Void

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private var questionViews: [(id: String, view: QuestionView)] = []
    private lazy var submitButton: UIButton = makeSubmitButton()

    init(prompt: ClientPrompt, theme: ResolvedTheme, onFinish: @escaping (Outcome) -> Void) {
        self.prompt = prompt
        self.theme = theme
        self.onFinish = onFinish
        super.init(frame: .zero)
        backgroundColor = theme.background
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.keyboardDismissMode = .onDrag
        addSubview(scroll)

        content.axis = .vertical
        content.spacing = 20
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let header = makeHeader()
        content.addArrangedSubview(header)

        for question in prompt.questions {
            let block = makeQuestionBlock(question: question)
            content.addArrangedSubview(block)
        }

        content.addArrangedSubview(submitButton)

        let dismiss = makeDismissButton()
        addSubview(dismiss)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),

            submitButton.heightAnchor.constraint(equalToConstant: 52),

            dismiss.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            dismiss.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dismiss.widthAnchor.constraint(equalToConstant: 32),
            dismiss.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func makeHeader() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6

        if let firstQuestion = prompt.questions.first {
            let title = UILabel()
            title.text = firstQuestion.title
            title.font = theme.titleFont
            title.textColor = theme.text
            title.numberOfLines = 0
            container.addArrangedSubview(title)

            if let subtitle = firstQuestion.subtitle, !subtitle.isEmpty {
                let sub = UILabel()
                sub.text = subtitle
                sub.font = theme.font
                sub.textColor = theme.subtext
                sub.numberOfLines = 0
                container.addArrangedSubview(sub)
            }
        }
        return container
    }

    private func makeQuestionBlock(question: Question) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10

        // For non-first questions, repeat title/subtitle inline.
        if prompt.questions.count > 1 && question.id != prompt.questions.first?.id {
            let title = UILabel()
            title.text = question.title
            title.font = theme.boldFont
            title.textColor = theme.text
            title.numberOfLines = 0
            container.addArrangedSubview(title)
            if let subtitle = question.subtitle, !subtitle.isEmpty {
                let sub = UILabel()
                sub.text = subtitle
                sub.font = theme.font
                sub.textColor = theme.subtext
                sub.numberOfLines = 0
                container.addArrangedSubview(sub)
            }
        }

        let view = makeQuestionView(question: question)
        questionViews.append((id: question.id, view: view))
        container.addArrangedSubview(view)
        return container
    }

    private func makeQuestionView(question: Question) -> QuestionView {
        switch question {
        case .rating(let q):
            return RatingQuestionView(question: q, theme: theme)
        case .nps(let q):
            return NpsQuestionView(question: q, theme: theme)
        case .multipleChoice(let q):
            return MultipleChoiceQuestionView(question: q, theme: theme)
        case .shortText(let q):
            return ShortTextQuestionView(question: q, theme: theme)
        }
    }

    private func makeSubmitButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Submit", for: .normal)
        button.titleLabel?.font = theme.boldFont
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = theme.primary
        button.layer.cornerRadius = min(theme.radius * 0.6, 14)
        button.addTarget(self, action: #selector(didTapSubmit), for: .touchUpInside)
        return button
    }

    private func makeDismissButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("✕", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        button.setTitleColor(theme.subtext, for: .normal)
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapDismiss), for: .touchUpInside)
        button.accessibilityLabel = "Dismiss"
        return button
    }

    @objc private func didTapSubmit() {
        Haptics.success()
        let answers: [PromptAnswerInfo] = questionViews.map { pair in
            PromptAnswerInfo(questionId: pair.id, value: pair.view.currentAnswer)
        }
        onFinish(.submitted(answers: answers))
    }

    @objc private func didTapDismiss() {
        onFinish(.dismissed)
    }
}
