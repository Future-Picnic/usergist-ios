import Foundation
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/PromptSheet.tsx
//
// One question at a time, tap-to-select auto-advance, one Close. The sheet
// background spans the full width; the header sits at the safe-area edges
// (Close leading, step centred) and the scrolling question plus the
// full-width Next/Submit footer share one centred 560pt readable column. The
// footer sits outside the scroll and the sheet rides above the keyboard.
final class PromptView: UIView {
    enum Outcome {
        case submitted(answers: [PromptAnswerInfo])
        case dismissed(answers: [PromptAnswerInfo])
    }

    private let prompt: ClientPrompt
    private let theme: ResolvedTheme
    private let onFinish: (Outcome) -> Void

    private let header = SurfaceHeaderView()
    private let stepLabel = UILabel()
    private let measure = UIStackView()
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let questionHost = UIView()
    private let footer = UIView()
    private lazy var closeButton = SurfaceIconButton(glyph: .close, color: theme.text)
    private lazy var nextButton = SurfacePrimaryButton(title: "Next", theme: theme)
    private var bottomPadding: NSLayoutConstraint?
    private var currentQuestionView: QuestionView?
    private var currentTitle: UILabel?
    private var currentSubtitle: UILabel?
    private var answers: [String: PromptAnswerValue] = [:]
    private var index = 0
    private var advanceWorkItem: DispatchWorkItem?
    private var closing = false
    private var editingObservers: [NSObjectProtocol] = []
    private var landscape: Bool?
    private var lastReportedHeight: CGFloat = 0

    /// Window size and safe area before this view is on screen, so the first
    /// sheet frame already has the right height and orientation.
    var layoutHint: (size: CGSize, insets: UIEdgeInsets)?

    var onPreferredHeightChange: ((CGFloat) -> Void)? {
        didSet { reportPreferredHeight(force: true) }
    }

    init(prompt: ClientPrompt, theme: ResolvedTheme, onFinish: @escaping (Outcome) -> Void) {
        self.prompt = prompt
        self.theme = theme
        self.onFinish = onFinish
        super.init(frame: .zero)
        backgroundColor = theme.background
        buildUI()
        renderCurrentQuestion(animated: false)
        for name in [UITextView.textDidBeginEditingNotification, UITextView.textDidChangeNotification,
                     UITextField.textDidBeginEditingNotification, UITextField.textDidChangeNotification] {
            editingObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self, let input = notification.object as? UIView,
                      input.isDescendant(of: self.questionHost) else { return }
                self.setNeedsLayout()
            })
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        editingObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func layoutSubviews() {
        applyEnvironment()
        super.layoutSubviews()
        scroll.superview?.layoutIfNeeded()
        scroll.layoutIfNeeded()
        content.layoutIfNeeded()
        keepEditingLineVisible(in: questionHost)
        reportPreferredHeight(force: false)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    private func keepEditingLineVisible(in root: UIView) {
        if root.isFirstResponder, let input = root as? (UIView & UITextInput),
           let selection = input.selectedTextRange {
            let caret = input.caretRect(for: selection.end)
            scroll.scrollRectToVisible(input.convert(caret, to: scroll).insetBy(dx: 0, dy: -12), animated: false)
            return
        }
        for child in root.subviews {
            keepEditingLineVisible(in: child)
        }
    }

    // MARK: - Layout

    private func buildUI() {
        stepLabel.font = theme.surfaceFont(13, .semibold)
        stepLabel.adjustsFontForContentSizeCategory = true
        stepLabel.textColor = theme.subtext
        closeButton.addTarget(self, action: #selector(didTapDismiss), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)
        header.leading.addArrangedSubview(closeButton)
        header.setCenter(stepLabel)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.keyboardDismissMode = .interactive
        content.axis = .vertical
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(questionHost)
        scroll.addSubview(content)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(nextButton)

        measure.axis = .vertical
        measure.addArrangedSubview(scroll)
        measure.addArrangedSubview(footer)
        measure.translatesAutoresizingMaskIntoConstraints = false
        addSubview(measure)

        let fullWidth = measure.widthAnchor.constraint(equalTo: widthAnchor, constant: -24)
        fullWidth.priority = .defaultHigh
        let bottom = measure.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        bottomPadding = bottom
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            measure.topAnchor.constraint(equalTo: header.bottomAnchor),
            measure.centerXAnchor.constraint(equalTo: centerXAnchor),
            measure.widthAnchor.constraint(lessThanOrEqualToConstant: SurfaceMetrics.contentMaxWidth),
            fullWidth,
            bottom,
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24),
            nextButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            nextButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            nextButton.topAnchor.constraint(equalTo: footer.topAnchor, constant: 4),
            nextButton.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        ])
        // The scroll region gives up height first; header and footer stay put.
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private var environmentSize: CGSize {
        window?.bounds.size ?? layoutHint?.size ?? UIScreen.main.bounds.size
    }

    private var environmentBottomInset: CGFloat {
        window != nil ? safeAreaInsets.bottom : (layoutHint?.insets.bottom ?? 0)
    }

    /// Orientation decides where the main action lives. The NPS layout follows
    /// the question's own content width (see `NpsQuestionView`), not the window.
    private func applyEnvironment() {
        let size = environmentSize
        let isLandscape = size.width > size.height
        bottomPadding?.constant = -max(environmentBottomInset, isLandscape ? 12 : 16)
        guard landscape != isLandscape else { return }
        landscape = isLandscape
        placeActions()
    }

    /// Feedback has no Back: Close stays leading and the trailing slot stays
    /// empty. Next/Submit is one full-width footer action in both
    /// orientations; the sheet sits above the keyboard, so the footer does too.
    private func placeActions() {
        guard prompt.questions.indices.contains(index) else { return }
        let needsNext = PromptFlow.needsExplicitNext(prompt.questions[index])
        header.setTrailing([])
        nextButton.compact = false
        nextButton.isHidden = !needsNext
        footer.isHidden = !needsNext
        setNeedsLayout()
    }

    /// Width the question actually gets: sheet minus 12pt edges, capped to the
    /// 560pt column, minus the column's 12pt content padding.
    static func contentWidth(forSheetWidth width: CGFloat) -> CGFloat {
        max(0, min(max(0, width - 24), SurfaceMetrics.contentMaxWidth) - 24)
    }

    private var expectedContentWidth: CGFloat {
        Self.contentWidth(forSheetWidth: bounds.width > 0 ? bounds.width : environmentSize.width)
    }

    /// Natural sheet height: header, question, footer and bottom padding.
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let size = environmentSize
        let isLandscape = size.width > size.height
        let column = min(max(0, width - 24), SurfaceMetrics.contentMaxWidth)
        let fitting = CGSize(width: Self.contentWidth(forSheetWidth: width),
                             height: UIView.layoutFittingCompressedSize.height)
        // Measure NPS in the layout it will actually use at this width.
        (currentQuestionView as? NpsQuestionView)?.wide = NpsQuestionView.isWide(contentWidth: fitting.width)
        let question = questionHost.subviews.first?.systemLayoutSizeFitting(
            fitting, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height ?? 0
        let headerHeight = max(SurfaceMetrics.headerMinHeight, header.systemLayoutSizeFitting(
            CGSize(width: max(0, width - 24), height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height)
        var footerHeight: CGFloat = 0
        if !footer.isHidden {
            footerHeight = 4 + nextButton.systemLayoutSizeFitting(
                CGSize(width: max(0, column - 24), height: 0),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
            ).height
        }
        let bottom = max(environmentBottomInset, isLandscape ? 12 : 16)
        return ceil(8 + headerHeight + question + 24 + footerHeight + bottom)
    }

    private func reportPreferredHeight(force: Bool) {
        guard let onPreferredHeightChange else { return }
        let width = bounds.width > 0 ? bounds.width : environmentSize.width
        if !force && bounds.width <= 0 { return }
        let height = preferredHeight(forWidth: width)
        guard force || abs(height - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = height
        onPreferredHeightChange(height)
    }

    // MARK: - Questions

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

        let total = prompt.questions.count
        stepLabel.text = total > 1 ? "\(index + 1) of \(total)" : nil
        stepLabel.isHidden = total <= 1
        nextButton.setTitle(index >= total - 1 ? "Submit" : "Next", for: .normal)
        nextButton.accessibilityLabel = nextButton.title(for: .normal)
        landscape = nil
        applyEnvironment()
        updateNextButton()
        scroll.setContentOffset(.zero, animated: false)
        reportPreferredHeight(force: true)

        guard animated, !UIAccessibility.isReduceMotionEnabled else { return }
        block.alpha = 0
        block.transform = CGAffineTransform(translationX: 36, y: 0)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            block.alpha = 1
            block.transform = .identity
        }
    }

    private func makeQuestionBlock(question: Question) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        let centered: Bool
        switch question {
        case .rating: centered = true
        case .nps: centered = NpsQuestionView.isWide(contentWidth: expectedContentWidth)
        default: centered = false
        }
        var subtitle = question.subtitle
        if case .multipleChoice(let value) = question, value.multiSelect == true, subtitle?.isEmpty != false {
            subtitle = "Choose all that apply"
        }
        let headerBlock = SurfaceQuestionHeader.make(
            title: question.title,
            subtitle: subtitle,
            imageURL: question.imageUrl.flatMap(URL.init(string:)),
            theme: theme,
            centered: centered
        )
        currentTitle = headerBlock.title
        currentSubtitle = headerBlock.subtitle
        stack.addArrangedSubview(headerBlock.view)
        stack.setCustomSpacing(16, after: headerBlock.view)

        let view = makeQuestionView(question: question)
        currentQuestionView = view
        view.onValueChange = { [weak self, weak view] value in
            guard let self, let view, self.currentQuestionView === view else { return }
            self.answers[question.id] = value
            self.updateNextButton()
            if PromptFlow.shouldAutoAdvance(question) {
                self.scheduleAdvance(for: question.id)
            }
            self.setNeedsLayout()
        }
        if let nps = view as? NpsQuestionView {
            nps.onFollowUpChange = { [weak self] text in
                self?.answers["\(question.id)__followUp"] = .text(text)
            }
            // The 0–10 row centres its title; the narrow list stays leading.
            nps.onWideChange = { [weak self] wide in
                let alignment: NSTextAlignment = wide ? .center : .natural
                self?.currentTitle?.textAlignment = alignment
                self?.currentSubtitle?.textAlignment = alignment
                self?.setNeedsLayout()
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
            return NpsQuestionView(question: q, theme: theme,
                                   wide: NpsQuestionView.isWide(contentWidth: expectedContentWidth))
        case .multipleChoice(let q):
            return MultipleChoiceQuestionView(question: q, theme: theme)
        case .shortText(let q):
            return ShortTextQuestionView(question: q, theme: theme)
        }
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
        nextButton.isActionEnabled = enabled
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
}
