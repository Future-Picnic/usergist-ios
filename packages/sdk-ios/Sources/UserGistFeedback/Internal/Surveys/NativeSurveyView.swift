import SwiftUI
import UIKit

@available(iOS 14.0, *)
final class NativeSurveyViewModel: ObservableObject {
    @Published var currentQuestionId: String?
    @Published var answers: [String: SurveyAnswerValue]
    @Published var isComplete = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    /// True after completion delivery failed; the error offers "Try again".
    @Published private(set) var canRetrySubmit = false
    @Published private(set) var history: [String] = []

    let flow: SurveyFlow
    private let surveyId: String
    private let attemptId: String
    private let store: SurveyStore
    private let onProgress: (String, String?, [String: SurveyAnswerValue]) -> Void
    private let onComplete: (
        String,
        [String: SurveyAnswerValue],
        @escaping (Bool) -> Void
    ) -> Void

    init(
        flow: SurveyFlow,
        surveyId: String,
        attemptId: String,
        store: SurveyStore,
        resume: SurveyAttempt?,
        onProgress: @escaping (String, String?, [String: SurveyAnswerValue]) -> Void,
        onComplete: @escaping (
            String,
            [String: SurveyAnswerValue],
            @escaping (Bool) -> Void
        ) -> Void
    ) {
        self.flow = flow
        self.surveyId = surveyId
        self.attemptId = attemptId
        self.store = store
        self.onProgress = onProgress
        self.onComplete = onComplete
        answers = resume?.answers ?? [:]
        currentQuestionId = resume?.currentQuestionId ?? flow.startQuestionId
    }

    var currentQuestion: SurveyQuestion? {
        guard let currentQuestionId else { return nil }
        return BranchEvaluator.findQuestion(flow: flow, questionId: currentQuestionId)
    }

    var questionIndex: Int {
        flow.questions.firstIndex { $0.id == currentQuestionId } ?? 0
    }

    var progress: Double {
        BranchEvaluator.estimateProgress(flow: flow, currentQuestionId: currentQuestionId)
    }

    var canGoBack: Bool { flow.backNavigation && !history.isEmpty }

    /// Last step of the current branch: the main action reads "Submit".
    var isFinalQuestion: Bool {
        guard let question = currentQuestion else { return false }
        return BranchEvaluator.nextQuestionId(flow: flow, currentQuestionId: question.id, answers: answers) == nil
    }

    var canAdvanceCurrentQuestion: Bool {
        guard let question = currentQuestion else { return false }
        if question.type == .shortText || question.type == .longText {
            return Self.isAnswered(answers[question.id])
        }
        return true
    }

    func select(_ value: SurveyAnswerValue, autoAdvance: Bool) {
        guard let question = currentQuestion else { return }
        answers[question.id] = value
        errorMessage = nil
        canRetrySubmit = false
        if autoAdvance {
            advance()
        } else {
            persist(questionId: question.id, nextQuestionId: question.id, value: value)
        }
    }

    func advance() {
        guard !isSubmitting, let question = currentQuestion else { return }
        if question.type == .infoScreen {
            answers[question.id] = .string("")
        }
        let answer = answers[question.id]
        if question.required == true && !Self.isAnswered(answer) {
            errorMessage = "Please answer this question to continue."
            return
        }
        if question.type == .multiChoice,
           let minimum = question.minSelections,
           Self.selectionCount(answer) < minimum {
            errorMessage = "Select at least \(minimum) options."
            return
        }
        errorMessage = nil
        canRetrySubmit = false
        let next = BranchEvaluator.nextQuestionId(
            flow: flow,
            currentQuestionId: question.id,
            answers: answers
        )
        if let value = answers[question.id] {
            persist(questionId: question.id, nextQuestionId: next, value: value)
        }
        if let next {
            history.append(question.id)
            currentQuestionId = next
        } else {
            submitCompletion()
        }
    }

    func advance(ifCurrentQuestionId questionId: String) {
        guard currentQuestionId == questionId else { return }
        advance()
    }

    func goBack() {
        guard canGoBack, !isSubmitting, let previous = history.popLast() else { return }
        currentQuestionId = previous
        errorMessage = nil
        canRetrySubmit = false
        onProgress(attemptId, previous, answers)
    }

    private func submitCompletion() {
        isSubmitting = true
        onComplete(attemptId, answers) { [weak self] delivered in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if delivered {
                    self.isComplete = true
                    self.currentQuestionId = nil
                } else {
                    self.errorMessage = "Your answers are saved on this device. Reconnect and retry to finish."
                    self.canRetrySubmit = true
                }
            }
        }
    }

    private func persist(
        questionId: String,
        nextQuestionId: String?,
        value: SurveyAnswerValue
    ) {
        store.recordAnswer(
            surveyId: surveyId,
            questionId: questionId,
            value: value,
            nextQuestionId: nextQuestionId
        )
        onProgress(attemptId, nextQuestionId, answers)
    }

    private static func isAnswered(_ value: SurveyAnswerValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null: return false
        case .string(let string): return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stringArray(let values): return !values.isEmpty
        case .intArray(let values): return !values.isEmpty
        default: return true
        }
    }

    private static func selectionCount(_ value: SurveyAnswerValue?) -> Int {
        switch value {
        case .stringArray(let values): return values.count
        case .intArray(let values): return values.count
        default: return 0
        }
    }
}

/// Approved navigation slots. Landscape groups Close then Back at the leading
/// edge and moves the primary action into the same row. Portrait retains its
/// full-width footer. Leading/trailing follow the layout direction.
struct SurveyNavigationLayout: Equatable {
    enum Slot: Equatable { case back, close, closeAndBack, next, endAction, empty }
    enum Footer: Equatable { case next, endAction, none }

    let leading: Slot
    let trailing: Slot
    let footer: Footer

    init(canGoBack: Bool, isComplete: Bool, needsNext: Bool, landscape: Bool = false) {
        let showBack = canGoBack && !isComplete
        if landscape {
            leading = showBack ? .closeAndBack : .close
            trailing = isComplete ? .endAction : (needsNext ? .next : .empty)
            footer = .none
        } else {
            leading = showBack ? .back : .close
            trailing = showBack ? .close : .empty
            footer = isComplete ? .endAction : (needsNext ? .next : .none)
        }
    }
}

// PORTED FROM: packages/sdk-react-native/src/ui/SurveyView.tsx
//
// Full-screen survey. Header: Back leading + Close trailing when Back is
// usable, otherwise Close leading; progress centred. Landscape groups Close
// then Back leading, with compact Next/Submit or the end CTA trailing in one
// readable header row. Portrait keeps the full-width footer above the keyboard.
@available(iOS 14.0, *)
struct NativeSurveyView: View {
    @ObservedObject var viewModel: NativeSurveyViewModel
    let endScreen: SurveyEndScreen?
    let theme: ResolvedTheme
    let onClose: () -> Void
    let onAbandon: (@escaping (Bool) -> Void) -> Void

    @State private var confirmingAbandon = false
    @State private var abandoning = false
    /// Scroll anchor of the focused answer field; drives `FocusedFieldReveal`.
    @State private var focusedAnswer: String?
    @StateObject private var keyboard = KeyboardVisibility()

    static func answerAnchor(_ questionId: String) -> String { "answer-\(questionId)" }
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            // Include the keyboard safe area so opening it in portrait cannot
            // turn a short available content region into landscape navigation.
            let landscape = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
                > geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            VStack(spacing: 0) {
                header(landscape: landscape)
                    .frame(maxWidth: landscape ? SurfaceMetrics.contentMaxWidth : .infinity)
                    .padding(.horizontal, landscape ? 24 : 12)
                    .frame(maxWidth: .infinity)
                    .padding(.top, landscape ? 8 : 4)
                    .padding(.bottom, 4)
                // NPS layout follows the content column (560pt cap, 24pt
                // side padding), not the window — same rule as the sheet.
                content(landscape: landscape, wide: NpsQuestionView.isWide(
                    contentWidth: min(max(0, geometry.size.width - 48), SurfaceMetrics.contentMaxWidth)))
                // Portrait's full-width action stays outside the scroll and
                // inside the keyboard-adjusted safe area. No landscape footer.
                if let footer = footerActions(landscape: landscape) {
                    footer
                        .frame(maxWidth: SurfaceMetrics.contentMaxWidth)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, max(8, 16 - geometry.safeAreaInsets.bottom))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(theme.background).ignoresSafeArea())
        .alert(isPresented: $confirmingAbandon) {
            Alert(
                title: Text("Leave this survey?"),
                message: Text("Your current answers will be saved, but the survey will be marked abandoned."),
                primaryButton: .destructive(Text("Leave survey")) {
                    abandoning = true
                    onAbandon { persisted in
                        DispatchQueue.main.async {
                            abandoning = false
                            if !persisted {
                                viewModel.errorMessage = "Unable to save your progress. Please try again."
                            }
                        }
                    }
                },
                secondaryButton: .cancel(Text("Keep answering"))
            )
        }
    }

    // MARK: Header and actions

    private func navigation(landscape: Bool) -> SurveyNavigationLayout {
        SurveyNavigationLayout(
            canGoBack: viewModel.canGoBack,
            isComplete: viewModel.isComplete,
            needsNext: viewModel.currentQuestion.map(needsNextButton) ?? false,
            landscape: landscape
        )
    }

    private func header(landscape: Bool) -> some View {
        let layout = navigation(landscape: landscape)
        return SurfaceHeaderBar(
            balancedSides: landscape && !viewModel.isComplete,
            leading: {
                headerControls(layout.leading, landscape: landscape)
            },
            center: { progress.frame(maxWidth: 320).padding(.horizontal, 8) },
            trailing: {
                headerControls(layout.trailing, landscape: landscape)
            }
        )
    }

    @ViewBuilder private func headerControls(_ slot: SurveyNavigationLayout.Slot, landscape: Bool) -> some View {
        switch slot {
        case .back: backButton(landscape: landscape)
        case .close: closeButton(landscape: landscape)
        case .closeAndBack:
            closeButton(landscape: landscape)
            backButton(landscape: landscape)
        case .next: nextButton(compact: true)
        case .endAction: endAction(compact: true)
        case .empty: EmptyView()
        }
    }

    private func closeButton(landscape: Bool) -> some View {
        SurfaceIconView(glyph: .close, color: theme.text, label: "Close survey",
                        size: landscape ? .regular : .small) {
            if viewModel.isComplete { onClose() } else { confirmingAbandon = true }
        }
        .disabled(abandoning)
    }

    /// Back stays in place (disabled) while submitting so Close does not jump
    /// sides mid-request; `goBack` already refuses while submitting.
    private func backButton(landscape: Bool) -> some View {
        SurfaceIconView(glyph: .back, color: theme.text, label: "Back",
                        size: landscape ? .regular : .small, action: viewModel.goBack)
            .disabled(viewModel.isSubmitting)
    }

    private func nextButton(compact: Bool) -> some View {
        SurfacePrimaryButtonView(
            title: viewModel.isFinalQuestion ? "Submit" : "Next",
            theme: theme,
            disabled: !viewModel.canAdvanceCurrentQuestion,
            loading: viewModel.isSubmitting,
            compact: compact,
            fillWidth: !compact,
            action: viewModel.advance
        )
    }

    private func endAction(compact: Bool) -> some View {
        SurfacePrimaryButtonView(title: endScreen?.cta?.label ?? "Done", theme: theme,
                                 compact: compact, fillWidth: !compact, action: openEndAction)
    }

    private func footerActions(landscape: Bool) -> AnyView? {
        switch navigation(landscape: landscape).footer {
        case .endAction: return AnyView(endAction(compact: false))
        case .next: return AnyView(nextButton(compact: false))
        case .none: return nil
        }
    }

    @ViewBuilder private var progress: some View {
        if !viewModel.isComplete && viewModel.flow.progressStyle == "bar" {
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(theme.fillStrong))
                    Capsule().fill(Color(theme.primary))
                        .frame(width: bar.size.width * CGFloat(min(max(viewModel.progress, 0), 1)))
                }
            }
            .frame(height: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Survey progress"))
            .accessibility(value: Text("\(Int((viewModel.progress * 100).rounded())) percent"))
        } else if !viewModel.isComplete && viewModel.flow.progressStyle == "dots" {
            HStack(spacing: 6) {
                ForEach(viewModel.flow.questions.indices, id: \.self) { index in
                    Capsule()
                        .fill(Color(index <= viewModel.questionIndex ? theme.primary : theme.fillStrong))
                        .frame(width: index == viewModel.questionIndex ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Question \(viewModel.questionIndex + 1) of \(viewModel.flow.questions.count)"))
        }
    }

    // MARK: Content

    /// Short landscape + keyboard leaves a tiny scroll viewport. When the
    /// answer field is focused (or the keyboard settles/resizes), scroll the
    /// field to the top so its first line shows in the scroll viewport; the
    /// question title may scroll away. Same helper as the request composer.
    private func content(landscape: Bool, wide: Bool) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                scrollContent(landscape: landscape, wide: wide, viewportHeight: viewport.size.height)
                    // Not animated: an animated scrollTo was dropped in the
                    // short-landscape test (offset stayed 0); the jump rides
                    // the keyboard's own animation.
                    .onChange(of: focusedAnswer) {
                        FocusedFieldReveal.reveal($0, in: proxy, reduceMotion: true)
                    }
                    .onChange(of: keyboard.settledFrames) { _ in
                        FocusedFieldReveal.reveal(focusedAnswer, in: proxy, reduceMotion: true)
                    }
                    .onChange(of: viewport.size) { _ in
                        FocusedFieldReveal.reveal(focusedAnswer, in: proxy, reduceMotion: true)
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: viewModel.currentQuestionId)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.62), value: viewModel.isComplete)
    }

    private func scrollContent(landscape: Bool, wide: Bool, viewportHeight: CGFloat) -> some View {
            ScrollView {
                Group {
                    if viewModel.isComplete {
                        SurveyEndScreenView(screen: endScreen, theme: theme)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    } else if let question = viewModel.currentQuestion {
                        questionBlock(question, wide: wide)
                            .id(question.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: AnyTransition.offset(x: 36).combined(with: .opacity),
                                removal: .opacity))
                    } else {
                        Text("This survey is unavailable.")
                            .font(Font(theme.surfaceFont(16)))
                            .foregroundColor(Color(theme.text))
                    }
                }
                .frame(maxWidth: SurfaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, landscape ? 8 : 24)
                .padding(.bottom, landscape ? 24 : 40)
                .frame(maxWidth: .infinity, minHeight: viewportHeight,
                       alignment: viewModel.isComplete ? .center : .top)
            }
    }

    private func questionBlock(_ question: SurveyQuestion, wide: Bool) -> some View {
        let centered = question.type == .rating || (question.type == .nps && wide)
        return VStack(alignment: .leading, spacing: 0) {
            SurfaceQuestionHeaderView(
                title: question.title,
                subtitle: subtitle(for: question),
                imageURL: question.imageUrl.flatMap(URL.init(string:)),
                theme: theme,
                centered: centered
            )
            questionInput(question, wide: wide)
            if let error = viewModel.errorMessage {
                errorBox(error)
            }
        }
    }

    private func subtitle(for question: SurveyQuestion) -> String? {
        if let subtitle = question.subtitle, !subtitle.isEmpty { return subtitle }
        switch question.type {
        case .multiChoice:
            return question.maxSelections.map { "Choose up to \($0)" } ?? "Choose all that apply"
        case .ranking: return "Most important first"
        default: return nil
        }
    }

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(Font(theme.surfaceFont(15)))
                .foregroundColor(Color(theme.text))
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.canRetrySubmit {
                SurfaceSecondaryButtonView(title: "Try again", theme: theme, compact: true, fillWidth: false,
                                           action: viewModel.advance)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.cappedRadius(14)).fill(Color(theme.fill)))
        .padding(.top, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Error: \(message)"))
    }

    @ViewBuilder
    private func questionInput(_ question: SurveyQuestion, wide: Bool) -> some View {
        switch question.type {
        case .singleChoice:
            SurveyChoiceList(choices: question.options ?? [], selected: selectedStrings(question.id),
                             multiple: false, maximum: 1, theme: theme) { values in
                if let first = values.first { viewModel.select(.string(first), autoAdvance: true) }
            }
        case .multiChoice:
            SurveyChoiceList(choices: question.options ?? [], selected: selectedStrings(question.id),
                             multiple: true, maximum: question.maxSelections, theme: theme) {
                viewModel.select(.stringArray($0), autoAdvance: false)
            }
        case .rating:
            SurveyRatingInput(
                question: question,
                selected: selectedInt(question.id),
                theme: theme,
                onSelect: { viewModel.select(.int($0), autoAdvance: false) },
                onAutoAdvance: { viewModel.advance(ifCurrentQuestionId: question.id) }
            )
            .frame(height: SurveyRatingInput.preferredHeight(for: question))
        case .nps:
            SurveyNpsScale(selected: selectedInt(question.id), lowLabel: question.lowLabel,
                           highLabel: question.highLabel, wide: wide, theme: theme) {
                viewModel.select(.int($0), autoAdvance: true)
            }
        case .likert:
            SurveyChoiceList(
                choices: (question.labels ?? [
                    "Strongly disagree", "Disagree", "Neutral", "Agree", "Strongly agree"
                ]).enumerated().map { SurveyChoice(id: String($0.offset + 1), label: $0.element) },
                selected: selectedInt(question.id).map { [String($0)] } ?? [],
                multiple: false, maximum: 1, theme: theme
            ) { values in
                if let score = values.first.flatMap(Int.init) {
                    viewModel.select(.int(score), autoAdvance: true)
                }
            }
        case .shortText, .longText:
            SurveyTextInput(
                initial: selectedText(question.id),
                accessibilityLabel: question.title,
                placeholder: question.placeholder ?? "",
                longForm: question.type == .longText,
                maxLength: question.maxLength,
                theme: theme,
                onFocusChange: { focused in
                    let anchor = Self.answerAnchor(question.id)
                    if focused { focusedAnswer = anchor } else if focusedAnswer == anchor { focusedAnswer = nil }
                }
            ) { viewModel.select(.string($0), autoAdvance: false) }
            .id(Self.answerAnchor(question.id))
        case .ranking:
            SurveyRankingInput(items: question.items ?? [], savedOrder: selectedStrings(question.id),
                               theme: theme) { viewModel.select(.stringArray($0), autoAdvance: false) }
        case .singleDate:
            SurveyDateInput(initial: selectedText(question.id), minimum: question.minDate,
                            maximum: question.maxDate, theme: theme) {
                viewModel.select(.string($0), autoAdvance: false)
            }
        case .infoScreen:
            Text(question.body ?? "")
                .font(Font(theme.surfaceFont(16)))
                .lineSpacing(6)
                .foregroundColor(Color(theme.subtext))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -4)
        }
    }

    private func needsNextButton(_ question: SurveyQuestion) -> Bool {
        switch question.type {
        case .singleChoice, .rating, .nps, .likert: return false
        default: return true
        }
    }

    private func selectedStrings(_ id: String) -> [String] {
        switch viewModel.answers[id] {
        case .string(let value): return [value]
        case .stringArray(let values): return values
        default: return []
        }
    }

    private func selectedInt(_ id: String) -> Int? {
        if case .int(let value) = viewModel.answers[id] { return value }
        return nil
    }

    private func selectedText(_ id: String) -> String {
        if case .string(let value) = viewModel.answers[id] { return value }
        return ""
    }

    private func openEndAction() {
        if let cta = endScreen?.cta,
           (cta.kind == "url" || cta.kind == "deep_link"),
           let target = cta.target,
           let url = URL(string: target) {
            UIApplication.shared.open(url)
        }
        onClose()
    }
}
