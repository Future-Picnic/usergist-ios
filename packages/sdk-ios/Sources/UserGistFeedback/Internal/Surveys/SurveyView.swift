import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/SurveyView.tsx
//
// Minimal SwiftUI renderer that walks the survey flow using the branching
// evaluator. Each answer is persisted via SurveyStore so a force-quit
// resumes at the same question on the next launch.

@available(iOS 14.0, *)
final class SurveyViewModel: ObservableObject {
    @Published var currentQuestionId: String?
    @Published var answers: [String: SurveyAnswerValue]
    @Published var isComplete: Bool = false

    let flow: SurveyFlow
    let surveyId: String
    let attemptId: String
    private let store: SurveyStore
    private let onProgress: (String, String?, [String: SurveyAnswerValue]) -> Void
    private let onComplete: (String, [String: SurveyAnswerValue]) -> Void

    init(
        flow: SurveyFlow,
        surveyId: String,
        attemptId: String,
        store: SurveyStore,
        resume: SurveyAttempt?,
        onProgress: @escaping (String, String?, [String: SurveyAnswerValue]) -> Void,
        onComplete: @escaping (String, [String: SurveyAnswerValue]) -> Void
    ) {
        self.flow = flow
        self.surveyId = surveyId
        self.attemptId = attemptId
        self.store = store
        self.onProgress = onProgress
        self.onComplete = onComplete
        if let resume = resume {
            self.answers = resume.answers
            self.currentQuestionId = resume.currentQuestionId
        } else {
            self.answers = [:]
            self.currentQuestionId = flow.startQuestionId
        }
    }

    var currentQuestion: SurveyQuestion? {
        guard let id = currentQuestionId else { return nil }
        return BranchEvaluator.findQuestion(flow: flow, questionId: id)
    }

    var progress: Double {
        BranchEvaluator.estimateProgress(flow: flow, currentQuestionId: currentQuestionId)
    }

    func recordAnswer(_ value: SurveyAnswerValue) {
        guard let id = currentQuestionId else { return }
        answers[id] = value
        let next = BranchEvaluator.nextQuestionId(
            flow: flow,
            currentQuestionId: id,
            answers: answers
        )
        currentQuestionId = next
        store.recordAnswer(
            surveyId: surveyId,
            questionId: id,
            value: value,
            nextQuestionId: next
        )
        onProgress(attemptId, next, answers)
        if next == nil {
            isComplete = true
            onComplete(attemptId, answers)
        }
    }

    func recordRatingSelection(_ value: SurveyAnswerValue, questionId: String) {
        guard currentQuestionId == questionId else { return }
        answers[questionId] = value
        store.recordAnswer(
            surveyId: surveyId,
            questionId: questionId,
            value: value,
            nextQuestionId: questionId
        )
        onProgress(attemptId, questionId, answers)
    }

    func advanceRatingSelection(questionId: String) {
        guard currentQuestionId == questionId,
              let value = answers[questionId]
        else { return }
        recordAnswer(value)
    }
}

@available(iOS 14.0, *)
struct SurveyView: View {
    @ObservedObject var viewModel: SurveyViewModel
    let onClose: () -> Void
    let onAbandon: () -> Void
    @State private var textAnswer: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(action: viewModel.isComplete ? onClose : onAbandon) {
                    Image(systemName: "xmark")
                        .padding(8)
                }
                .accessibilityLabel("Close survey")
            }
            ProgressView(value: viewModel.progress)
            if viewModel.isComplete {
                completionView
            } else if let q = viewModel.currentQuestion {
                questionView(q)
            } else {
                EmptyView()
            }
        }
        .padding(20)
    }

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thanks for your feedback")
                .font(.title2)
                .bold()
            Button(action: onClose) {
                Text("Close")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .userGistProminentButton()
        }
    }

    @ViewBuilder
    private func questionView(_ q: SurveyQuestion) -> some View {
        Text(q.title)
            .font(.headline)
        if let helper = q.subtitle {
            Text(helper)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        questionInput(q)
    }

    @ViewBuilder
    private func questionInput(_ q: SurveyQuestion) -> some View {
        switch q.type {
        case .rating:
            SurveyRatingInput(
                question: q,
                selected: selectedInt(q.id),
                theme: .fallback,
                onSelect: {
                    viewModel.recordRatingSelection(.int($0), questionId: q.id)
                },
                onAutoAdvance: {
                    viewModel.advanceRatingSelection(questionId: q.id)
                }
            )
            .frame(height: SurveyRatingInput.preferredHeight(for: q))
        case .nps:
            HStack {
                ForEach(0...10, id: \.self) { v in
                    Button(action: {
                        viewModel.recordAnswer(.int(v))
                    }) {
                        Text("\(v)")
                            .frame(minWidth: 36, minHeight: 36)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }
        case .shortText, .longText:
            VStack(alignment: .leading) {
                SurveyTextInput(
                    initial: textAnswer,
                    accessibilityLabel: q.title,
                    placeholder: q.placeholder ?? "",
                    longForm: q.type == .longText,
                    maxLength: q.maxLength,
                    theme: .fallback
                ) { textAnswer = $0 }
                .id(q.id)
                Button(action: {
                    viewModel.recordAnswer(.string(textAnswer))
                    textAnswer = ""
                }) {
                    Text("Next").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .userGistProminentButton()
                .disabled(textAnswer.isEmpty && (q.required ?? true))
            }
        case .singleChoice:
            VStack(spacing: 8) {
                ForEach(q.options ?? [], id: \.id) { choice in
                    Button(action: {
                        viewModel.recordAnswer(.string(choice.id))
                    }) {
                        Text(choice.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .foregroundColor(.primary)
                }
            }
        case .multiChoice:
            multiChoiceInput(q)
        case .likert:
            VStack(spacing: 8) {
                ForEach(Array((q.labels ?? [
                    "Strongly disagree", "Disagree", "Neutral", "Agree", "Strongly agree"
                ]).enumerated()), id: \.offset) { index, label in
                    Button(action: { viewModel.recordAnswer(.int(index + 1)) }) {
                        Text(label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .foregroundColor(.primary)
                }
            }
        case .ranking:
            RankingList(items: q.items ?? []) { ids in
                viewModel.recordAnswer(.stringArray(ids))
            }
        case .singleDate:
            DateAnswer(onSubmit: { date in
                viewModel.recordAnswer(.string(date))
            })
        case .infoScreen:
            if let body = q.body {
                Text(body).foregroundColor(.secondary)
            }
            Button(action: { viewModel.recordAnswer(.string("")) }) {
                Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .userGistProminentButton()
        }
    }

    @ViewBuilder
    private func multiChoiceInput(_ q: SurveyQuestion) -> some View {
        MultiChoiceList(
            choices: q.options ?? [],
            minimum: q.minSelections ?? 0,
            maximum: q.maxSelections,
            onSubmit: { selected in
                viewModel.recordAnswer(.stringArray(selected))
            }
        )
    }

    private func selectedInt(_ id: String) -> Int? {
        if case .int(let value) = viewModel.answers[id] { return value }
        return nil
    }
}

@available(iOS 14.0, *)
private struct MultiChoiceList: View {
    let choices: [SurveyChoice]
    let minimum: Int
    let maximum: Int?
    let onSubmit: ([String]) -> Void
    @State private var selected = Set<String>()

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices, id: \.id) { c in
                Button(action: {
                    if selected.contains(c.id) {
                        selected.remove(c.id)
                    } else if maximum == nil || selected.count < maximum! {
                        selected.insert(c.id)
                    }
                }) {
                    HStack {
                        Image(systemName: selected.contains(c.id) ? "checkmark.square.fill" : "square")
                        Text(c.label)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .foregroundColor(.primary)
            }
            Button(action: { onSubmit(Array(selected)) }) {
                Text("Next").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .userGistProminentButton()
            .disabled(selected.count < minimum)
        }
    }
}

@available(iOS 14.0, *)
private struct RankingList: View {
    @State private var ordered: [SurveyChoice]
    let onSubmit: ([String]) -> Void

    init(items: [SurveyChoice], onSubmit: @escaping ([String]) -> Void) {
        _ordered = State(initialValue: items)
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text("\(index + 1). \(item.label)")
                    Spacer()
                    Button(action: { move(index, -1) }) { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                    Button(action: { move(index, 1) }) { Image(systemName: "chevron.down") }
                        .disabled(index == ordered.count - 1)
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            Button(action: { onSubmit(ordered.map(\.id)) }) {
                Text("Next").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .userGistProminentButton()
        }
    }

    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard ordered.indices.contains(index), ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
    }
}

@available(iOS 14.0, *)
private struct DateAnswer: View {
    let onSubmit: (String) -> Void
    @State private var selected = Date()

    var body: some View {
        VStack(spacing: 12) {
            DatePicker("Date", selection: $selected, displayedComponents: .date)
            Button(action: {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                onSubmit(formatter.string(from: selected))
            }) {
                Text("Next").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .userGistProminentButton()
        }
    }
}

@available(iOS 14.0, *)
private extension View {
    /// iOS 14-compatible equivalent of the iOS 15 bordered-prominent style.
    func userGistProminentButton() -> some View {
        self
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.white)
            .background(Color.accentColor)
            .cornerRadius(8)
    }
}
