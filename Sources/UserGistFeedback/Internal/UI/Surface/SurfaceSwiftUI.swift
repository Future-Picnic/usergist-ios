import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/SurfaceControls.tsx +
// SurfacePrimitives.tsx — SwiftUI twins of the UIKit controls, used by the
// survey and requests surfaces. iOS 14 compatible.

@available(iOS 14.0, *)
struct SurfacePressStyle: ButtonStyle {
    var pressedOpacity: Double = 0.82
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? pressedOpacity : 1)
    }
}

@available(iOS 14.0, *)
struct SurfaceIconView: View {
    enum Glyph { case close, back }
    let glyph: Glyph
    let color: UIColor
    var label: String?
    let action: () -> Void

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(color.withAlphaComponent(0.08)))
                    .frame(width: SurfaceMetrics.iconFace, height: SurfaceMetrics.iconFace)
                if glyph == .close {
                    CrossShape().stroke(Color(color), style: stroke).frame(width: 9.2, height: 9.2)
                } else {
                    ChevronShape(direction: .left).stroke(Color(color), style: stroke)
                        .frame(width: 4.5, height: 9).offset(x: -0.5)
                }
            }
            .frame(width: SurfaceMetrics.iconHit, height: SurfaceMetrics.iconHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(pressedOpacity: 0.6))
        .accessibilityLabel(Text(label ?? (glyph == .close ? "Close" : "Back")))
    }
}

@available(iOS 14.0, *)
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

@available(iOS 14.0, *)
struct ChevronShape: Shape {
    enum Direction { case left, up, down }
    let direction: Direction
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .up:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .down:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}

@available(iOS 14.0, *)
struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Solid primary action: wraps long labels, neutral when disabled, spinner when loading.
@available(iOS 14.0, *)
struct SurfacePrimaryButtonView: View {
    let title: String
    let theme: ResolvedTheme
    var disabled = false
    var loading = false
    var compact = false
    var fillWidth = true
    let action: () -> Void

    var body: some View {
        let inactive = disabled && !loading
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(Font(theme.surfaceFont(compact ? 15 : 16, .bold)))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(Color(inactive ? theme.disabledLabel : theme.onPrimary))
                    .opacity(loading ? 0 : 1)
                if loading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color(theme.onPrimary)))
                }
            }
            .padding(.horizontal, compact ? 18 : 24)
            .padding(.vertical, compact ? 10 : 12)
            .frame(minWidth: compact ? SurfaceMetrics.compactMinWidth : nil,
                   maxWidth: fillWidth ? .infinity : nil,
                   minHeight: compact ? SurfaceMetrics.compactMinHeight : SurfaceMetrics.primaryMinHeight)
            .background(Color(inactive ? theme.fill : theme.primary))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 22 : 25, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle())
        .disabled(disabled || loading)
        .accessibilityLabel(Text(title))
        .accessibility(value: Text(loading ? "In progress" : ""))
    }
}

/// Secondary action: text colour on a neutral outline.
@available(iOS 14.0, *)
struct SurfaceSecondaryButtonView: View {
    let title: String
    let theme: ResolvedTheme
    var compact = false
    var fillWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font(theme.surfaceFont(compact ? 15 : 16, .bold)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(Color(theme.text))
                .padding(.horizontal, compact ? 18 : 24)
                .padding(.vertical, compact ? 10 : 12)
                .frame(maxWidth: fillWidth ? .infinity : nil,
                       minHeight: compact ? SurfaceMetrics.compactMinHeight : SurfaceMetrics.primaryMinHeight)
                .overlay(RoundedRectangle(cornerRadius: compact ? 22 : 25, style: .continuous)
                    .stroke(Color(theme.quietOutline), lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(pressedOpacity: 0.6))
    }
}

/// Selectable row: tint + primary border + radio/checkbox indicator.
@available(iOS 14.0, *)
struct SurfaceChoiceRowView: View {
    enum Kind { case radio, checkbox }
    let label: String
    var detail: String?
    let selected: Bool
    let kind: Kind
    let theme: ResolvedTheme
    let action: () -> Void

    var body: some View {
        let accent = Color(theme.primary)
        let radius = theme.cappedRadius(16)
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Font(theme.surfaceFont(16, .medium)))
                        .foregroundColor(Color(theme.text))
                    if let detail, !detail.isEmpty {
                        Text(detail).font(Font(theme.surfaceFont(13))).foregroundColor(Color(theme.subtext))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                indicator(accent: accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: radius).fill(selected ? Color(theme.tint) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(selected ? accent : Color(theme.border), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(pressedOpacity: 0.7))
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func indicator(accent: Color) -> some View {
        let ring = selected ? accent : Color(theme.text.withAlphaComponent(0.25))
        if kind == .radio {
            ZStack {
                Circle().stroke(ring, lineWidth: 1.75)
                if selected { Circle().fill(accent).frame(width: 10, height: 10) }
            }
            .frame(width: 22, height: 22)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(selected ? accent : Color.clear)
                RoundedRectangle(cornerRadius: 7).stroke(ring, lineWidth: 1.75)
                if selected {
                    TickShape()
                        .stroke(Color(theme.onPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 7)
                }
            }
            .frame(width: 22, height: 22)
        }
    }
}

/// Title (20/26 bold) and subtitle (15/21) with an optional 16:9 image.
@available(iOS 14.0, *)
struct SurfaceQuestionHeaderView: View {
    let title: String
    var subtitle: String?
    var imageURL: URL?
    let theme: ResolvedTheme
    var centered = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 0) {
            if let imageURL {
                SurfaceRemoteImage(url: imageURL, theme: theme, radius: max(8, theme.radius - 6))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .padding(.bottom, 16)
            }
            Text(title)
                .font(Font(theme.surfaceFont(20, .bold)))
                .lineSpacing(4)
                .foregroundColor(Color(theme.text))
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Font(theme.surfaceFont(15)))
                    .lineSpacing(3)
                    .foregroundColor(Color(theme.subtext))
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.bottom, 16)
    }
}

/// Soft multiline field: neutral fill, primary border on focus, placeholder,
/// optional counter. Backed by UITextView for reliable editing on iOS 14.
@available(iOS 14.0, *)
struct SurfaceMultilineField: View {
    @Binding var text: String
    let placeholder: String
    var maxLength: Int?
    var minHeight: CGFloat = 112
    let accessibilityLabel: String
    let theme: ResolvedTheme
    var autoFocus = false
    var editable = true
    /// Lets a host scroll the field into view when it gains focus.
    var onFocusChange: ((Bool) -> Void)?
    @State private var focused = false

    var body: some View {
        content.onChange(of: focused) { onFocusChange?($0) }
    }

    private var content: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                SurfaceUIKitTextView(text: $text, focused: $focused, accessibilityLabel: accessibilityLabel,
                                     theme: theme, autoFocus: autoFocus, editable: editable)
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(Font(theme.surfaceFont(16)))
                        .foregroundColor(Color(theme.subtext.withAlphaComponent(0.8)))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Fixed height; longer answers scroll inside the field.
            .frame(height: minHeight)
            .background(RoundedRectangle(cornerRadius: theme.cappedRadius(14)).fill(Color(theme.fill)))
            .overlay(RoundedRectangle(cornerRadius: theme.cappedRadius(14))
                .stroke(focused ? Color(theme.primary) : Color.clear, lineWidth: 1.5))
            if let maxLength {
                Text(verbatim: "\(text.count)/\(maxLength)")
                    .font(Font(theme.surfaceFont(12)))
                    .foregroundColor(Color(Double(text.count) >= Double(maxLength) * 0.9 ? theme.text : theme.subtext))
                    .accessibilityIdentifier("survey-text-counter")
            }
        }
    }
}

/// Single-line soft field (titles, search).
@available(iOS 14.0, *)
struct SurfaceLineField: View {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String
    let theme: ResolvedTheme
    var onFocusChange: ((Bool) -> Void)?
    @State private var focused = false

    var body: some View {
        content.onChange(of: focused) { onFocusChange?($0) }
    }

    private var content: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Font(theme.surfaceFont(16)))
                    .foregroundColor(Color(theme.subtext.withAlphaComponent(0.8)))
                    .accessibilityHidden(true)
            }
            TextField("", text: $text, onEditingChanged: { focused = $0 })
                .font(Font(theme.surfaceFont(16)))
                .foregroundColor(Color(theme.text))
                .accentColor(Color(theme.primary))
                .accessibilityLabel(Text(accessibilityLabel))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: theme.cappedRadius(14)).fill(Color(theme.fill)))
        .overlay(RoundedRectangle(cornerRadius: theme.cappedRadius(14))
            .stroke(focused ? Color(theme.primary) : Color.clear, lineWidth: 1.5))
    }
}

@available(iOS 14.0, *)
struct SurfaceUIKitTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let accessibilityLabel: String
    let theme: ResolvedTheme
    var autoFocus = false
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, focused: $focused) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 9, bottom: 12, right: 9)
        view.textContainer.lineFragmentPadding = 5
        view.isScrollEnabled = true
        view.adjustsFontForContentSizeCategory = true
        if autoFocus { DispatchQueue.main.async { view.becomeFirstResponder() } }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        view.backgroundColor = .clear
        view.font = theme.surfaceFont(16)
        view.textColor = theme.text
        view.tintColor = theme.primary
        view.isEditable = editable
        view.accessibilityLabel = accessibilityLabel
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var focused: Bool

        init(text: Binding<String>, focused: Binding<Bool>) {
            _text = text
            _focused = focused
        }

        func textViewDidChange(_ textView: UITextView) { text = textView.text }
        func textViewDidBeginEditing(_ textView: UITextView) { focused = true }
        func textViewDidEndEditing(_ textView: UITextView) { focused = false }
    }
}

@available(iOS 14.0, *)
final class SurfaceImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var task: URLSessionDataTask?

    func load(_ url: URL) {
        guard image == nil, task == nil else { return }
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

/// Remote image with a themed placeholder (never dropped while loading).
@available(iOS 14.0, *)
struct SurfaceRemoteImage: View {
    let url: URL
    let theme: ResolvedTheme
    let radius: CGFloat
    @StateObject private var loader = SurfaceImageLoader()

    var body: some View {
        Color(theme.fill)
            .overlay(Group {
                if let image = loader.image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            })
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
            .onAppear { loader.load(url) }
    }
}

/// Three-slot header (Close/Back leading, centre, trailing action).
@available(iOS 14.0, *)
struct SurfaceHeaderBar<Leading: View, Center: View, Trailing: View>: View {
    let leading: Leading
    let center: Center
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder center: () -> Center,
         @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) { leading }
                .frame(minWidth: SurfaceMetrics.iconHit, alignment: .leading)
                .layoutPriority(2)
            // Color.clear keeps the centre slot flexible even when it is empty,
            // so Close stays leading and actions stay trailing.
            ZStack { Color.clear.frame(height: 1); center }.frame(maxWidth: .infinity)
            // Ideal width clamped to 320pt: short actions hug their label,
            // long labels wrap inside the cap. The centre gives up width first.
            HStack(spacing: 4) { trailing }
                .frame(minWidth: SurfaceMetrics.iconHit, maxWidth: SurfaceMetrics.trailingMaxWidth,
                       alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(minHeight: SurfaceMetrics.headerMinHeight)
    }
}
