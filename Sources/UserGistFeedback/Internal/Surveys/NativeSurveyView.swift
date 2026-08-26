import SwiftUI
import UIKit

@available(iOS 14.0, *)
final class NativeSurveyViewModel: ObservableObject {
    @Published var currentQuestionId: String?
    @Published var answers: [String: SurveyAnswerValue]
    @Published var isComplete = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
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

    var canGoBack: Bool { flow.backNavigation && !history.isEmpty }

    func select(_ value: SurveyAnswerValue, autoAdvance: Bool) {
        guard let question = currentQuestion else { return }
        answers[question.id] = value
        errorMessage = nil
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

    func goBack() {
        guard canGoBack, let previous = history.popLast() else { return }
        currentQuestionId = previous
        errorMessage = nil
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

@available(iOS 14.0, *)
struct NativeSurveyView: View {
    @ObservedObject var viewModel: NativeSurveyViewModel
    let endScreen: SurveyEndScreen?
    let theme: ResolvedTheme
    let onClose: () -> Void
    let onAbandon: (@escaping (Bool) -> Void) -> Void

    @State private var confirmingAbandon = false
    @State private var abandoning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            progress
            Group {
                if viewModel.isComplete {
                    completionView
                } else if let question = viewModel.currentQuestion {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let imageUrl = question.imageUrl,
                               let url = URL(string: imageUrl) {
                                RemoteSurveyImage(url: url, radius: theme.radius)
                            }
                            Text(question.title)
                                .font(Font(theme.titleFont))
                                .foregroundColor(Color(theme.text))
                                .fixedSize(horizontal: false, vertical: true)
                            if let subtitle = question.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(Font(theme.font))
                                    .foregroundColor(Color(theme.subtext))
                            }
                            questionInput(question)
                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundColor(Color(UIColor.systemRed))
                                    .accessibilityLabel("Error: \(error)")
                            }
                            if needsNextButton(question) {
                                primaryButton(
                                    title: viewModel.isSubmitting ? "Submitting…" :
                                        (question.type == .infoScreen ? "Continue" : "Next"),
                                    disabled: viewModel.isSubmitting,
                                    action: viewModel.advance
                                )
                            }
                        }
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("This survey is unavailable.")
                        .foregroundColor(Color(theme.text))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var header: some View {
        HStack {
            Button(action: viewModel.goBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(!viewModel.canGoBack)
            .opacity(viewModel.canGoBack ? 1 : 0)
            .accessibilityLabel("Back")
            Spacer()
            Button(action: {
                if viewModel.isComplete { onClose() }
                else { confirmingAbandon = true }
            }) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .disabled(abandoning)
            .accessibilityLabel("Close survey")
        }
        .foregroundColor(Color(theme.text))
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
    }

    @ViewBuilder private var progress: some View {
        if !viewModel.isComplete && viewModel.flow.progressStyle == "bar" {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Color(theme.border)
                    Color(theme.primary).frame(
                        width: geometry.size.width * progressFraction
                    )
                }
            }
            .frame(height: 4)
            .accessibilityLabel("Survey progress")
            .accessibilityValue("Question \(viewModel.questionIndex + 1) of \(viewModel.flow.questions.count)")
        } else if !viewModel.isComplete && viewModel.flow.progressStyle == "dots" {
            HStack(spacing: 6) {
                ForEach(viewModel.flow.questions.indices, id: \.self) { index in
                    Circle()
                        .fill(Color(index <= viewModel.questionIndex ? theme.primary : theme.border))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Question \(viewModel.questionIndex + 1) of \(viewModel.flow.questions.count)")
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Color(theme.primary))
                .accessibilityHidden(true)
            Text(endScreen?.headline ?? "Thanks for your feedback")
                .font(Font(theme.titleFont))
                .foregroundColor(Color(theme.text))
                .multilineTextAlignment(.center)
            if let body = endScreen?.body, !body.isEmpty {
                Text(body)
                    .font(Font(theme.font))
                    .foregroundColor(Color(theme.subtext))
                    .multilineTextAlignment(.center)
            }
            primaryButton(
                title: endScreen?.cta?.label ?? "Close",
                disabled: false,
                action: openEndAction
            )
            .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func questionInput(_ question: SurveyQuestion) -> some View {
        switch question.type {
        case .singleChoice:
            ChoiceList(
                choices: question.options ?? [],
                selected: selectedStrings(question.id),
                multiple: false,
                maximum: 1,
                theme: theme
            ) { values in
                if let first = values.first { viewModel.select(.string(first), autoAdvance: true) }
            }
        case .multiChoice:
            ChoiceList(
                choices: question.options ?? [],
                selected: selectedStrings(question.id),
                multiple: true,
                maximum: question.maxSelections,
                theme: theme
            ) { viewModel.select(.stringArray($0), autoAdvance: false) }
        case .rating, .nps:
            let lower = question.type == .nps ? 0 : 1
            let upper = question.type == .nps ? 10 : (question.scale ?? 5)
            ScoreGrid(
                range: lower...upper,
                selected: selectedInt(question.id),
                lowLabel: question.lowLabel,
                highLabel: question.highLabel,
                theme: theme
            ) { viewModel.select(.int($0), autoAdvance: true) }
        case .likert:
            ChoiceList(
                choices: (question.labels ?? [
                    "Strongly disagree", "Disagree", "Neutral", "Agree", "Strongly agree"
                ]).enumerated().map { SurveyChoice(id: String($0.offset + 1), label: $0.element) },
                selected: selectedInt(question.id).map { [String($0)] } ?? [],
                multiple: false,
                maximum: 1,
                theme: theme
            ) { values in
                if let score = values.first.flatMap(Int.init) {
                    viewModel.select(.int(score), autoAdvance: true)
                }
            }
        case .shortText, .longText:
            SurveyTextInput(
                initial: selectedText(question.id),
                placeholder: question.placeholder ?? "",
                multiline: question.type == .longText,
                maxLength: question.maxLength,
                theme: theme
            ) { viewModel.select(.string($0), autoAdvance: false) }
        case .ranking:
            SurveyRankingInput(
                items: question.items ?? [],
                savedOrder: selectedStrings(question.id),
                theme: theme
            ) { viewModel.select(.stringArray($0), autoAdvance: false) }
        case .singleDate:
            SurveyDateInput(
                initial: selectedText(question.id),
                minimum: question.minDate,
                maximum: question.maxDate,
                theme: theme
            ) { viewModel.select(.string($0), autoAdvance: false) }
        case .infoScreen:
            Text(question.body ?? "")
                .font(Font(theme.font))
                .foregroundColor(Color(theme.subtext))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryButton(
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Font(theme.boldFont))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(theme.primary.userGistContrastColor)
        .background(Color(theme.primary))
        .cornerRadius(min(theme.radius, 14))
        .opacity(disabled ? 0.55 : 1)
        .disabled(disabled)
    }

    private func needsNextButton(_ question: SurveyQuestion) -> Bool {
        switch question.type {
        case .singleChoice, .rating, .nps, .likert: return false
        default: return true
        }
    }

    private var progressFraction: CGFloat {
        let total = max(viewModel.flow.questions.count, 1)
        return CGFloat(viewModel.questionIndex + 1) / CGFloat(total)
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

@available(iOS 14.0, *)
private struct ChoiceList: View {
    let choices: [SurveyChoice]
    let selected: [String]
    let multiple: Bool
    let maximum: Int?
    let theme: ResolvedTheme
    let onChange: ([String]) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices, id: \.id) { choice in
                let active = selected.contains(choice.id)
                Button(action: { toggle(choice.id) }) {
                    HStack {
                        Image(systemName: multiple
                            ? (active ? "checkmark.square.fill" : "square")
                            : (active ? "largecircle.fill.circle" : "circle"))
                        Text(choice.label)
                            .font(Font(theme.font))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(active ? Color(theme.primary) : Color(theme.text))
                .background(active ? Color(theme.primary).opacity(0.10) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: min(theme.radius, 14))
                        .stroke(active ? Color(theme.primary) : Color(theme.border), lineWidth: 1)
                )
                .cornerRadius(min(theme.radius, 14))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private func toggle(_ id: String) {
        if !multiple {
            onChange([id])
            return
        }
        var next = selected
        if let index = next.firstIndex(of: id) {
            next.remove(at: index)
        } else if maximum == nil || next.count < maximum! {
            next.append(id)
        }
        onChange(next)
    }
}

@available(iOS 14.0, *)
private struct ScoreGrid: View {
    let range: ClosedRange<Int>
    let selected: Int?
    let lowLabel: String?
    let highLabel: String?
    let theme: ResolvedTheme
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(range), id: \.self) { score in
                    Button(action: { onSelect(score) }) {
                        Text(String(score))
                            .font(Font(theme.boldFont))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(selected == score
                        ? theme.primary.userGistContrastColor
                        : Color(theme.text))
                    .background(selected == score ? Color(theme.primary) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: min(theme.radius, 12))
                            .stroke(Color(theme.border), lineWidth: selected == score ? 0 : 1)
                    )
                    .cornerRadius(min(theme.radius, 12))
                }
            }
            if lowLabel != nil || highLabel != nil {
                HStack {
                    Text(lowLabel ?? "")
                    Spacer()
                    Text(highLabel ?? "")
                }
                .font(.caption)
                .foregroundColor(Color(theme.subtext))
            }
        }
    }
}

@available(iOS 14.0, *)
private struct SurveyTextInput: View {
    @State private var value: String
    let placeholder: String
    let multiline: Bool
    let maxLength: Int?
    let theme: ResolvedTheme
    let onChange: (String) -> Void

    init(
        initial: String,
        placeholder: String,
        multiline: Bool,
        maxLength: Int?,
        theme: ResolvedTheme,
        onChange: @escaping (String) -> Void
    ) {
        _value = State(initialValue: initial)
        self.placeholder = placeholder
        self.multiline = multiline
        self.maxLength = maxLength
        self.theme = theme
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if multiline {
                TextEditor(text: binding)
                    .frame(minHeight: 132)
            } else {
                TextField(placeholder, text: binding)
                    .frame(minHeight: 48)
            }
            if let maxLength {
                Text("\(value.count) / \(maxLength)")
                    .font(.caption)
                    .foregroundColor(Color(theme.subtext))
            }
        }
        .font(Font(theme.font))
        .foregroundColor(Color(theme.text))
        .padding(.horizontal, 12)
        .overlay(
            RoundedRectangle(cornerRadius: min(theme.radius, 12))
                .stroke(Color(theme.border), lineWidth: 1)
        )
    }

    private var binding: Binding<String> {
        Binding(
            get: { value },
            set: { next in
                let clipped = maxLength.map { String(next.prefix($0)) } ?? next
                value = clipped
                onChange(clipped)
            }
        )
    }
}

@available(iOS 14.0, *)
private struct SurveyRankingInput: View {
    @State private var ordered: [SurveyChoice]
    let theme: ResolvedTheme
    let onChange: ([String]) -> Void

    init(
        items: [SurveyChoice],
        savedOrder: [String],
        theme: ResolvedTheme,
        onChange: @escaping ([String]) -> Void
    ) {
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let restored = savedOrder.compactMap { byId[$0] }
        _ordered = State(initialValue: restored.count == items.count ? restored : items)
        self.theme = theme
        self.onChange = onChange
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text("\(index + 1).")
                        .foregroundColor(Color(theme.subtext))
                    Text(item.label)
                        .foregroundColor(Color(theme.text))
                    Spacer()
                    moveButton("chevron.up", disabled: index == 0) { move(index, -1) }
                    moveButton("chevron.down", disabled: index == ordered.count - 1) { move(index, 1) }
                }
                .font(Font(theme.font))
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: min(theme.radius, 12))
                        .stroke(Color(theme.border), lineWidth: 1)
                )
            }
        }
        .onAppear { onChange(ordered.map(\.id)) }
    }

    private func moveButton(
        _ systemName: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName).frame(width: 44, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(disabled ? Color(theme.border) : Color(theme.primary))
        .disabled(disabled)
    }

    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard ordered.indices.contains(index), ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        onChange(ordered.map(\.id))
    }
}

@available(iOS 14.0, *)
private struct SurveyDateInput: View {
    @State private var selected: Date
    let minimum: Date
    let maximum: Date
    let theme: ResolvedTheme
    let onChange: (String) -> Void

    init(
        initial: String,
        minimum: String?,
        maximum: String?,
        theme: ResolvedTheme,
        onChange: @escaping (String) -> Void
    ) {
        let formatter = Self.formatter
        let min = minimum.flatMap(formatter.date) ?? formatter.date(from: "1900-01-01")!
        let max = maximum.flatMap(formatter.date) ?? formatter.date(from: "2100-12-31")!
        let current = initial.isEmpty ? Date() : (formatter.date(from: initial) ?? Date())
        _selected = State(initialValue: Swift.max(min, Swift.min(current, max)))
        self.minimum = min
        self.maximum = max
        self.theme = theme
        self.onChange = onChange
    }

    var body: some View {
        DatePicker(
            "Date",
            selection: Binding(
                get: { selected },
                set: {
                    selected = $0
                    onChange(Self.formatter.string(from: $0))
                }
            ),
            in: minimum...maximum,
            displayedComponents: .date
        )
        .font(Font(theme.font))
        .foregroundColor(Color(theme.text))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

@available(iOS 14.0, *)
private final class SurveyImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: URLSessionDataTask?

    func load(_ url: URL) {
        task?.cancel()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= 10 * 1_024 * 1_024,
                  let data, data.count <= 10 * 1_024 * 1_024,
                  let image = UIImage(data: data)
            else { return }
            DispatchQueue.main.async { self?.image = image }
        }
        task?.resume()
    }

    deinit { task?.cancel() }
}

@available(iOS 14.0, *)
private struct RemoteSurveyImage: View {
    let url: URL
    let radius: CGFloat
    @StateObject private var loader = SurveyImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(UIColor.secondarySystemBackground)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
        .clipped()
        .cornerRadius(radius)
        .accessibilityHidden(true)
        .onAppear { loader.load(url) }
    }
}

private extension UIColor {
    var userGistContrastColor: Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance < 0.45 ? .white : .black
    }
}
