import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/survey-questions.tsx and
// ui/questions/NpsQuestion.tsx — survey widgets on the shared primitives so
// surveys and feedback share one visual language.

@available(iOS 14.0, *)
struct SurveyChoiceList: View {
    let choices: [SurveyChoice]
    let selected: [String]
    let multiple: Bool
    let maximum: Int?
    let theme: ResolvedTheme
    let onChange: ([String]) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices, id: \.id) { choice in
                SurfaceChoiceRowView(label: choice.label, selected: selected.contains(choice.id),
                                     kind: multiple ? .checkbox : .radio, theme: theme) {
                    toggle(choice.id)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        guard multiple else {
            onChange([id])
            return
        }
        if selected.contains(id) {
            onChange(selected.filter { $0 != id })
        } else if maximum.map({ selected.count < $0 }) ?? true {
            onChange(selected + [id])
        }
    }
}

/// NPS: 0–10 row on wide windows (each numeral centred in its cell), vertical
/// list with 10 at the top on narrow portrait.
@available(iOS 14.0, *)
struct SurveyNpsScale: View {
    let selected: Int?
    let lowLabel: String?
    let highLabel: String?
    let wide: Bool
    let theme: ResolvedTheme
    let onSelect: (Int) -> Void

    private var low: String { lowLabel ?? "Not at all likely" }
    private var high: String { highLabel ?? "Extremely likely" }

    var body: some View {
        if wide {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0...10, id: \.self) { cell($0, endpoint: nil).frame(maxWidth: .infinity) }
                }
                HStack(alignment: .top, spacing: 16) {
                    Text(low).frame(maxWidth: .infinity, alignment: .leading)
                    Text(high).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(Font(theme.surfaceFont(13)))
                .foregroundColor(Color(theme.subtext))
            }
        } else {
            VStack(spacing: 6) {
                ForEach(Array((0...10).reversed()), id: \.self) { value in
                    cell(value, endpoint: value == 10 ? high : value == 0 ? low : nil)
                }
            }
        }
    }

    private func cell(_ value: Int, endpoint: String?) -> some View {
        let chosen = selected == value
        let radius = theme.cappedRadius(12)
        return Button(action: { onSelect(value) }) {
            HStack(spacing: 10) {
                Text(verbatim: String(value))
                    .font(Font(theme.surfaceFont(16, .bold)).monospacedDigit())
                    .foregroundColor(Color(chosen ? theme.onPrimary : theme.text))
                    .frame(minWidth: wide ? 0 : 22, alignment: wide ? .center : .leading)
                if let endpoint {
                    Text(endpoint)
                        .font(Font(theme.surfaceFont(14)))
                        .foregroundColor(Color(chosen ? theme.onPrimary : theme.subtext))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !wide { Spacer(minLength: 0) }
            }
            .padding(.horizontal, wide ? 0 : 16)
            .padding(.vertical, wide ? 0 : 8)
            .frame(maxWidth: .infinity, minHeight: wide ? 48 : 44, maxHeight: wide ? 48 : nil)
            .background(RoundedRectangle(cornerRadius: radius).fill(chosen ? Color(theme.primary) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(Color(chosen ? theme.primary : theme.border), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(pressedOpacity: 0.7))
        .accessibilityLabel(Text("Score \(value)" + (value == 10 ? ", \(high)" : value == 0 ? ", \(low)" : "")))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

@available(iOS 14.0, *)
struct SurveyTextInput: View {
    @State private var value: String
    let accessibilityLabel: String
    let placeholder: String
    let longForm: Bool
    let maxLength: Int?
    let theme: ResolvedTheme
    let onFocusChange: ((Bool) -> Void)?
    let onChange: (String) -> Void

    init(
        initial: String,
        accessibilityLabel: String,
        placeholder: String,
        longForm: Bool,
        maxLength: Int?,
        theme: ResolvedTheme,
        onFocusChange: ((Bool) -> Void)? = nil,
        onChange: @escaping (String) -> Void
    ) {
        _value = State(initialValue: initial)
        self.accessibilityLabel = accessibilityLabel
        self.placeholder = placeholder
        self.longForm = longForm
        self.maxLength = maxLength.flatMap { $0 > 0 ? $0 : nil }
        self.theme = theme
        self.onFocusChange = onFocusChange
        self.onChange = onChange
    }

    var body: some View {
        SurfaceMultilineField(
            text: binding,
            placeholder: placeholder,
            maxLength: maxLength,
            minHeight: longForm ? 132 : 100,
            accessibilityLabel: accessibilityLabel,
            theme: theme,
            onFocusChange: onFocusChange
        )
    }

    private var binding: Binding<String> {
        Binding(
            get: { value },
            set: { next in
                let clipped = Self.limitedText(next, maxLength: maxLength)
                value = clipped
                onChange(clipped)
            }
        )
    }

    static func limitedText(_ text: String, maxLength: Int?) -> String {
        guard let maxLength, maxLength > 0 else { return text }
        return String(text.prefix(maxLength))
    }
}

/// Ranking with move buttons (accessible without drag gestures).
@available(iOS 14.0, *)
struct SurveyRankingInput: View {
    @State private var ordered: [SurveyChoice]
    let theme: ResolvedTheme
    let onChange: ([String]) -> Void

    init(
        items: [SurveyChoice],
        savedOrder: [String],
        theme: ResolvedTheme,
        onChange: @escaping ([String]) -> Void
    ) {
        _ordered = State(initialValue: Self.restoredItems(items, savedOrder: savedOrder))
        self.theme = theme
        self.onChange = onChange
    }

    static func restoredItems(_ items: [SurveyChoice], savedOrder: [String]) -> [SurveyChoice] {
        var seen = Set<String>()
        let unique = items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        let byId = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        seen.removeAll()
        let restored = savedOrder.compactMap { id -> SurveyChoice? in
            guard seen.insert(id).inserted else { return nil }
            return byId[id]
        }
        return restored + unique.filter { !seen.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Text(verbatim: String(index + 1))
                        .font(Font(theme.surfaceFont(14, .bold)).monospacedDigit())
                        .foregroundColor(Color(theme.primary))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(theme.tint)))
                    Text(item.label)
                        .font(Font(theme.surfaceFont(16, .medium)))
                        .foregroundColor(Color(theme.text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                    moveButton(.up, disabled: index == 0, label: "Move \(item.label) up") { move(index, -1) }
                    moveButton(.down, disabled: index == ordered.count - 1, label: "Move \(item.label) down") {
                        move(index, 1)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .frame(minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: theme.cappedRadius(16))
                    .stroke(Color(theme.border), lineWidth: 1.5))
            }
        }
        .onAppear { onChange(ordered.map(\.id)) }
    }

    private func moveButton(_ direction: ChevronShape.Direction, disabled: Bool, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChevronShape(direction: direction)
                .stroke(Color(disabled ? theme.text.withAlphaComponent(0.2) : theme.text),
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 6)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(pressedOpacity: 0.5))
        .disabled(disabled)
        .accessibilityLabel(Text(label))
    }

    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard ordered.indices.contains(index), ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        onChange(ordered.map(\.id))
    }
}

@available(iOS 14.0, *)
struct SurveyDateInput: View {
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
        let lower = minimum.flatMap(formatter.date) ?? Date(timeIntervalSince1970: -2208988800)
        let upper = maximum.flatMap(formatter.date) ?? Date(timeIntervalSince1970: 4133894400)
        // DatePicker requires an ordered closed range, including for malformed
        // server data or stale cached limits. Never construct a reversed range.
        let min = Swift.min(lower, upper)
        let max = Swift.max(lower, upper)
        let current = initial.isEmpty ? Date() : (formatter.date(from: initial) ?? Date())
        _selected = State(initialValue: Swift.max(min, Swift.min(current, max)))
        self.minimum = min
        self.maximum = max
        self.theme = theme
        self.onChange = onChange
    }

    var body: some View {
        HStack {
            Text("Date")
                .font(Font(theme.surfaceFont(16, .medium)))
                .foregroundColor(Color(theme.text))
            Spacer(minLength: 12)
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
            .labelsHidden()
            .accentColor(Color(theme.primary))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: theme.cappedRadius(14)).fill(Color(theme.fill)))
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

/// Completion state: tinted badge with a drawn tick, headline and body.
@available(iOS 14.0, *)
struct SurveyEndScreenView: View {
    let screen: SurveyEndScreen?
    let theme: ResolvedTheme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color(theme.tint)).frame(width: 72, height: 72)
                TickShape()
                    .stroke(Color(theme.primary), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 26, height: 18)
            }
            .accessibilityHidden(true)
            .padding(.bottom, 20)
            Text(screen?.headline ?? "Thanks!")
                .font(Font(theme.surfaceFont(24, .bold)))
                .foregroundColor(Color(theme.text))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let body = screen?.body, !body.isEmpty {
                Text(body)
                    .font(Font(theme.surfaceFont(16)))
                    .lineSpacing(6)
                    .foregroundColor(Color(theme.subtext))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
