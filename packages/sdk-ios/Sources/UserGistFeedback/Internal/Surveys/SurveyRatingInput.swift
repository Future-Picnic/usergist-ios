import SwiftUI

/// SwiftUI bridge that keeps survey ratings on the prompt SDK's star-first control.
@available(iOS 14.0, *)
struct SurveyRatingInput: UIViewRepresentable {
    let question: SurveyQuestion
    let selected: Int?
    let theme: ResolvedTheme
    let onSelect: (Int) -> Void
    let onAutoAdvance: () -> Void

    static func promptQuestion(for question: SurveyQuestion) -> Question.Rating {
        Question.Rating(
            id: question.id,
            title: question.title,
            subtitle: question.subtitle,
            imageUrl: question.imageUrl,
            scale: question.scale == 10 ? 10 : 5,
            display: .stars,
            lowLabel: question.lowLabel,
            highLabel: question.highLabel
        )
    }

    static func preferredHeight(for question: SurveyQuestion) -> CGFloat {
        let count = max(2, question.scale ?? 5)
        let rowSize = min(count, 5)
        let rowCount = Int(ceil(Double(count) / Double(rowSize)))
        let rowsHeight = CGFloat(rowCount * 36 + max(0, rowCount - 1) * 8)
        let labelsHeight: CGFloat = (question.lowLabel != nil || question.highLabel != nil) ? 23 : 0
        return rowsHeight + labelsHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onAutoAdvance: onAutoAdvance)
    }

    func makeUIView(context: Context) -> RatingQuestionView {
        let view = RatingQuestionView(
            question: Self.promptQuestion(for: question),
            theme: theme,
            initialValue: selected
        )
        view.onValueChange = { value in
            guard case .number(let score) = value else { return }
            context.coordinator.didSelect(Int(score))
        }
        return view
    }

    func updateUIView(_ uiView: RatingQuestionView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onAutoAdvance = onAutoAdvance
        uiView.setSelectedValue(selected)
    }

    final class Coordinator {
        var onSelect: (Int) -> Void
        var onAutoAdvance: () -> Void

        init(
            onSelect: @escaping (Int) -> Void,
            onAutoAdvance: @escaping () -> Void
        ) {
            self.onSelect = onSelect
            self.onAutoAdvance = onAutoAdvance
        }

        func didSelect(_ value: Int) {
            let advance = onAutoAdvance
            onSelect(value)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(220)) { [weak self] in
                guard self != nil else { return }
                advance()
            }
        }
    }
}
