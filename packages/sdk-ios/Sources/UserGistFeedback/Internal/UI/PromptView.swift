import Foundation
import UIKit

/// React Native-parity prompt surface: one question at a time, with
/// tap-to-select auto-advance and a single explicit close affordance.
final class PromptView: UIView {
    enum Outcome {
        case submitted(answers: [PromptAnswerInfo])
        case dismissed(answers: [PromptAnswerInfo])
    }

    private let prompt: ClientPrompt
    private let theme: ResolvedTheme
    private let onFinish: (Outcome) -> Void

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let questionHost = UIView()
    private lazy var nextButton: UIButton = makeNextButton()
    private var currentQuestionView: QuestionView?
    private var answers: [String: PromptAnswerValue] = [:]
    private var index = 0
    private var advanceWorkItem: DispatchWorkItem?
    private var closing = false

    var onPreferredHeightChange: ((CGFloat) -> Void)? {
        didSet {
            guard prompt.questions.indices.contains(index) else { return }
            onPreferredHeightChange?(estimatedHeight(for: prompt.questions[index]))
        }
    }

    init(prompt: ClientPrompt, theme: ResolvedTheme, onFinish: @escaping (Outcome) -> Void) {
        self.prompt = prompt
        self.theme = theme
        self.onFinish = onFinish
        super.init(frame: .zero)
        backgroundColor = theme.background
        buildUI()
        renderCurrentQuestion(animated: false)
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.keyboardDismissMode = .onDrag
        addSubview(scroll)

        content.axis = .vertical
        content.spacing = 0
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        content.addArrangedSubview(makeHeader())
        content.addArrangedSubview(spacer(height: 24))
        content.addArrangedSubview(questionHost)
        content.addArrangedSubview(spacer(height: 20))
        content.addArrangedSubview(nextButton)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            nextButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func makeHeader() -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let handle = UIView()
        handle.backgroundColor = theme.border
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(handle)

        let close = UIButton(type: .system)
        close.setTitle("✕", for: .normal)
        close.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        close.setTitleColor(theme.text, for: .normal)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        close.layer.cornerRadius = 16
        close.accessibilityLabel = "Close"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(didTapDismiss), for: .touchUpInside)
        container.addSubview(close)

        NSLayoutConstraint.activate([
            handle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            handle.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            handle.widthAnchor.constraint(equalToConstant: 40),
            handle.heightAnchor.constraint(equalToConstant: 4),
            close.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            close.topAnchor.constraint(equalTo: container.topAnchor),
            close.widthAnchor.constraint(equalToConstant: 32),
            close.heightAnchor.constraint(equalToConstant: 32)
        ])
        return container
    }

    private func renderCurrentQuestion(animated: Bool) {
        advanceWorkItem?.cancel()
        guard prompt.questions.indices.contains(index) else { return }
        let question = prompt.questions[index]
        questionHost.subviews.forEach { $0.removeFromSuperview() }

        let block = makeQuestionBlock(question: question)
        block.translatesAutoresizingMaskIntoConstraints = false
        questionHost.addSubview(block)
        NSLayoutConstraint.activate([
            block.leadingAnchor.constraint(equalTo: questionHost.leadingAnchor),
            block.trailingAnchor.constraint(equalTo: questionHost.trailingAnchor),
            block.topAnchor.constraint(equalTo: questionHost.topAnchor),
            block.bottomAnchor.constraint(equalTo: questionHost.bottomAnchor)
        ])

        let explicitNext = PromptFlow.needsExplicitNext(question)
        nextButton.isHidden = !explicitNext
        updateNextButton()
        onPreferredHeightChange?(estimatedHeight(for: question))

        guard animated else { return }
        block.alpha = 0
        block.transform = CGAffineTransform(translationX: 36, y: 0)
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            block.alpha = 1
            block.transform = .identity
        }
    }

    private func makeQuestionBlock(question: Question) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill

        if let rawURL = question.imageUrl, let url = URL(string: rawURL) {
            let image = PromptQuestionImageView(url: url, radius: theme.radius)
            stack.addArrangedSubview(image)
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 9.0 / 16.0).isActive = true
            stack.setCustomSpacing(16, after: image)
        }

        let centered = isCentered(question)
        let title = UILabel()
        title.text = question.title
        title.font = theme.titleFont
        title.textColor = theme.text
        title.numberOfLines = 0
        title.textAlignment = centered ? .center : .left
        stack.addArrangedSubview(title)

        if let subtitle = question.subtitle, !subtitle.isEmpty {
            stack.setCustomSpacing(4, after: title)
            let label = UILabel()
            label.text = subtitle
            label.font = theme.font.withSize(14)
            label.textColor = theme.subtext
            label.numberOfLines = 0
            label.textAlignment = centered ? .center : .left
            stack.addArrangedSubview(label)
            stack.setCustomSpacing(spacingBeforeControl(question, hasSubtitle: true), after: label)
        } else {
            stack.setCustomSpacing(spacingBeforeControl(question, hasSubtitle: false), after: title)
        }

        let view = makeQuestionView(question: question)
        currentQuestionView = view
        view.onValueChange = { [weak self, weak view] value in
            guard let self, let view, self.currentQuestionView === view else { return }
            self.answers[question.id] = value
            self.updateNextButton()
            if PromptFlow.shouldAutoAdvance(question) {
                self.scheduleAdvance(for: question.id)
            }
        }
        if let nps = view as? NpsQuestionView {
            nps.onFollowUpChange = { [weak self] text in
                self?.answers["\(question.id)__followUp"] = .text(text)
            }
        }
        stack.addArrangedSubview(view)
        return stack
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

    private func makeNextButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Next", for: .normal)
        button.titleLabel?.font = theme.titleFont.withSize(16)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = theme.primary
        button.layer.cornerRadius = 26
        button.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)
        return button
    }

    private func updateNextButton() {
        guard prompt.questions.indices.contains(index) else { return }
        let question = prompt.questions[index]
        let enabled: Bool
        if case .shortText = question {
            enabled = currentQuestionView.map { PromptFlow.hasValue($0.currentAnswer) } ?? false
        } else if case .nps(let value) = question, value.followUp?.isEmpty == false {
            enabled = currentQuestionView.map { PromptFlow.hasValue($0.currentAnswer) } ?? false
        } else {
            enabled = true
        }
        nextButton.isEnabled = enabled
        nextButton.alpha = enabled ? 1 : 0.4
    }

    private func scheduleAdvance(for questionId: String) {
        advanceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.closing,
                  self.prompt.questions.indices.contains(self.index),
                  self.prompt.questions[self.index].id == questionId else { return }
            self.advance()
        }
        advanceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    @objc private func didTapNext() {
        advance()
    }

    private func advance() {
        guard !closing else { return }
        advanceWorkItem?.cancel()
        if index < prompt.questions.count - 1 {
            index += 1
            renderCurrentQuestion(animated: true)
            return
        }
        closing = true
        Haptics.success()
        onFinish(.submitted(answers: PromptFlow.orderedAnswers(prompt: prompt, answers: answers)))
    }

    @objc private func didTapDismiss() {
        dismiss()
    }

    func dismiss() {
        guard !closing else { return }
        closing = true
        advanceWorkItem?.cancel()
        onFinish(.dismissed(answers: PromptFlow.orderedAnswers(prompt: prompt, answers: answers)))
    }

    private func isCentered(_ question: Question) -> Bool {
        switch question {
        case .rating, .nps: return true
        default: return false
        }
    }

    private func spacingBeforeControl(_ question: Question, hasSubtitle: Bool) -> CGFloat {
        switch question {
        case .rating: return hasSubtitle ? 24 : 12
        case .nps: return hasSubtitle ? 24 : 16
        case .multipleChoice: return hasSubtitle ? 16 : 12
        case .shortText: return hasSubtitle ? 12 : 4
        }
    }

    private func estimatedHeight(for question: Question) -> CGFloat {
        var height: CGFloat = 20 + 32 + 24 + 30 + 48
        if question.subtitle?.isEmpty == false { height += 24 }
        if question.imageUrl != nil {
            height += max(0, UIScreen.main.bounds.width - 40) * 9.0 / 16.0 + 16
        }
        switch question {
        case .rating(let value):
            height += value.scale > 5 ? 88 : 44
        case .nps:
            height += 11 * 52
        case .multipleChoice(let value):
            height += CGFloat(value.options.count * 56) + 72
        case .shortText:
            height += 172
        }
        return max(280, height)
    }

    private func spacer(height: CGFloat) -> UIView {
        let view = UIView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

private final class PromptQuestionImageView: UIImageView {
    private var task: URLSessionDataTask?

    init(url: URL, radius: CGFloat) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = radius
        accessibilityIgnoresInvertColors = true
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.image = image }
        }
        task?.resume()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        task?.cancel()
    }
}
