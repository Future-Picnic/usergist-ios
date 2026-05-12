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

    init(
        flow: SurveyFlow,
        surveyId: String,
        attemptId: String,
        store: SurveyStore,
        resume: SurveyAttempt?
    ) {
        self.flow = flow
        self.surveyId = surveyId
        self.attemptId = attemptId
        self.store = store
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
        if next == nil { isComplete = true }
    }
}

@available(iOS 14.0, *)
struct SurveyView: View {
    @ObservedObject var viewModel: SurveyViewModel
    let onDismiss: () -> Void
    @State private var textAnswer: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            Button(action: onDismiss) {
                Text("Close")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func questionView(_ q: SurveyQuestion) -> some View {
        Text(q.text)
            .font(.headline)
        if let helper = q.helperText {
            Text(helper)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        questionInput(q)
    }

    @ViewBuilder
    private func questionInput(_ q: SurveyQuestion) -> some View {
        switch q.kind {
        case .rating, .nps:
            let min = q.minRating ?? (q.kind == .nps ? 0 : 1)
            let max = q.maxRating ?? (q.kind == .nps ? 10 : 5)
            HStack {
                ForEach(min...max, id: \.self) { v in
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
                TextField(q.placeholder ?? "", text: $textAnswer)
                    .textFieldStyle(.roundedBorder)
                Button(action: {
                    viewModel.recordAnswer(.string(textAnswer))
                    textAnswer = ""
                }) {
                    Text("Next").frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(textAnswer.isEmpty && (q.required ?? true))
            }
        case .singleChoice:
            VStack(spacing: 8) {
                ForEach(q.choices ?? [], id: \.id) { choice in
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
        default:
            // info / likert / ranking / date — minimal "next" fallback so
            // the survey advances rather than blocking the user.
            Button(action: { viewModel.recordAnswer(.string("")) }) {
                Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func multiChoiceInput(_ q: SurveyQuestion) -> some View {
        MultiChoiceList(
            choices: q.choices ?? [],
            onSubmit: { selected in
                viewModel.recordAnswer(.stringArray(selected))
            }
        )
    }
}

@available(iOS 14.0, *)
private struct MultiChoiceList: View {
    let choices: [SurveyChoice]
    let onSubmit: ([String]) -> Void
    @State private var selected = Set<String>()

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices, id: \.id) { c in
                Button(action: {
                    if selected.contains(c.id) {
                        selected.remove(c.id)
                    } else {
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
            .buttonStyle(.borderedProminent)
        }
    }
}
