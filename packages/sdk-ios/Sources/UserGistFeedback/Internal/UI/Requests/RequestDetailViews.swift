import Foundation
import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/requests/
//   {DetailView,DetailContent,CommentsView,SubmitView}.tsx

@available(iOS 14.0, *)
private struct RequestHeaderDivider: View {
    let theme: ResolvedTheme
    var body: some View {
        Rectangle().fill(Color(theme.border)).frame(height: 1 / UIScreen.main.scale)
    }
}

/// Watches the software keyboard so the detail action bar can step aside
/// while the user writes, and so forms can re-reveal the focused field once
/// the keyboard has settled (shown, rotated, or resized by a QuickType bar).
@available(iOS 14.0, *)
final class KeyboardVisibility: ObservableObject {
    @Published private(set) var visible = false
    /// Bumps after every settled keyboard frame.
    @Published private(set) var settledFrames = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) {
                [weak self] _ in self?.visible = true
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) {
                [weak self] _ in self?.visible = false
            },
            center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) {
                [weak self] _ in self?.settledFrames += 1
            },
            center.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main) {
                [weak self] _ in self?.settledFrames += 1
            }
        ]
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// Scrolls a focused form block so its label and the field's first line sit
/// at the top of the visible area. UIKit's own caret scroll aligns the caret
/// to the bottom edge, which in landscape hides the field's first line.
@available(iOS 14.0, *)
enum FocusedFieldReveal {
    static func reveal<ID: Hashable>(_ id: ID?, in proxy: ScrollViewProxy, reduceMotion: Bool) {
        guard let id else { return }
        // Next runloop: after SwiftUI applies the keyboard safe-area inset.
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(id, anchor: .top)
            } else {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
}

// MARK: - Detail

@available(iOS 14.0, *)
struct RequestDetailView: View {
    @ObservedObject var model: RequestDetailModel
    let theme: ResolvedTheme
    let onDismiss: () -> Void
    @StateObject private var keyboard = KeyboardVisibility()
    /// Scroll id of the comment field that has focus (new comment or an edit).
    @State private var focusedComposer: String?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            SurfaceHeaderBar(
                leading: {
                    SurfaceIconView(glyph: .back, color: theme.text, label: "Back to requests", action: onDismiss)
                },
                center: {
                    Text("Suggestion")
                        .font(Font(theme.surfaceFont(17, .bold)))
                        .foregroundColor(Color(theme.text))
                        .lineLimit(1)
                },
                trailing: { EmptyView() }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            RequestHeaderDivider(theme: theme)
            if let request = model.request {
                ScrollViewReader { proxy in
                    ScrollView {
                        detailBody(request)
                            .frame(maxWidth: SurfaceMetrics.contentMaxWidth, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 32)
                            .frame(maxWidth: .infinity)
                    }
                    // Reveal the focused comment field's first line, not just its caret.
                    .onChange(of: focusedComposer) { FocusedFieldReveal.reveal($0, in: proxy, reduceMotion: reduceMotion) }
                    .onChange(of: keyboard.settledFrames) { _ in
                        FocusedFieldReveal.reveal(focusedComposer, in: proxy, reduceMotion: reduceMotion)
                    }
                }
                if !keyboard.visible { actionBar(request) }
            } else if model.loadFailed {
                RequestEmptyState(title: "This suggestion couldn't load",
                                  message: "Check your connection, then go back and open it again.",
                                  actionTitle: "Try again", theme: theme, action: model.load)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(theme.primary)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(theme.background).ignoresSafeArea())
    }

    private func detailBody(_ r: FeatureRequest) -> some View {
        let radius = theme.cappedRadius(16)
        return VStack(alignment: .leading, spacing: 0) {
            RequestStatusPill(status: r.status)
            Text(r.title)
                .font(Font(theme.surfaceFont(24, .bold)))
                .foregroundColor(Color(theme.text))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
            HStack(spacing: 16) {
                stat(r.upvoteCount, one: "upvote", many: "upvotes")
                stat(r.followerCount, one: "follower", many: "followers")
            }
            .padding(.top, 10)
            Text(r.description)
                .font(Font(theme.surfaceFont(16)))
                .lineSpacing(6)
                .foregroundColor(Color(theme.text))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            responseBox(r, radius: radius).padding(.top, 24)
            RequestCommentsSection(model: model, theme: theme, onFocus: { id, focused in
                if focused { focusedComposer = id } else if focusedComposer == id { focusedComposer = nil }
            })
            .padding(.top, 32)
        }
    }

    private func stat(_ value: Int, one: String, many: String) -> some View {
        (Text(verbatim: String(value)).fontWeight(.bold).foregroundColor(Color(theme.text))
            + Text(" \(value == 1 ? one : many)").foregroundColor(Color(theme.subtext)))
            .font(Font(theme.surfaceFont(15)))
            .accessibilityLabel(Text("\(value) \(value == 1 ? one : many)"))
    }

    @ViewBuilder private func responseBox(_ r: FeatureRequest, radius: CGFloat) -> some View {
        let response = r.devResponse.flatMap { $0.isEmpty ? nil : $0 }
        VStack(alignment: .leading, spacing: 6) {
            Text(response == nil ? "No update yet" : "Update from the team")
                .font(Font(theme.surfaceFont(15, .bold)))
                .foregroundColor(Color(response == nil ? theme.text : theme.primary))
            Text(response ?? "Follow this suggestion to hear when the team posts an update.")
                .font(Font(theme.surfaceFont(15)))
                .lineSpacing(5)
                .foregroundColor(Color(response == nil ? theme.subtext : theme.text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: radius).fill(Color(response == nil ? theme.fill : theme.tint)))
    }

    private func actionBar(_ r: FeatureRequest) -> some View {
        let voted = r.viewerHasUpvoted
        let following = r.viewerIsFollowing
        let busy = model.requestMutationInFlight
        return VStack(spacing: 8) {
            if let error = model.actionError { RequestNotice(text: error, theme: theme) }
            HStack(spacing: 10) {
                Button(action: model.toggleVote) {
                    HStack(spacing: 8) {
                        ChevronShape(direction: .up)
                            .stroke(Color(voted ? theme.onPrimary : theme.primary),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 5)
                        Text(voted ? "Upvoted, \(r.upvoteCount)" : "Upvote, \(r.upvoteCount)")
                            .font(Font(theme.surfaceFont(16, .bold)))
                            .foregroundColor(Color(voted ? theme.onPrimary : theme.primary))
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(Color(voted ? theme.primary : theme.tint)))
                    .contentShape(Capsule())
                }
                .buttonStyle(SurfacePressStyle())
                .disabled(busy)
                .accessibilityLabel(Text(busy ? "Updating request vote" :
                    (voted ? "Remove request vote" : "Upvote request")))
                .accessibilityAddTraits(voted ? .isSelected : [])
                Button(action: model.toggleFollow) {
                    Text(following ? "Following" : "Follow")
                        .font(Font(theme.surfaceFont(16, .bold)))
                        .foregroundColor(Color(theme.text))
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(following ? Color(theme.fill) : Color.clear))
                        .overlay(Capsule().stroke(Color(following ? theme.quietOutline : theme.border), lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(SurfacePressStyle(pressedOpacity: 0.7))
                .disabled(busy)
                .accessibilityLabel(Text(busy ? "Updating request follow" :
                    (following ? "Unfollow request" : "Follow request")))
                .accessibilityAddTraits(following ? .isSelected : [])
            }
        }
        .frame(maxWidth: SurfaceMetrics.contentMaxWidth)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(theme.background).ignoresSafeArea(edges: .bottom))
        .overlay(RequestHeaderDivider(theme: theme), alignment: .top)
    }
}

// MARK: - Comments

@available(iOS 14.0, *)
private struct RequestCommentsSection: View {
    @ObservedObject var model: RequestDetailModel
    let theme: ResolvedTheme
    /// (scroll id, focused) for the new-comment field and inline edit fields.
    let onFocus: (String, Bool) -> Void
    @State private var actionsFor: RequestComment?
    @State private var confirmDelete: RequestComment?

    static let composerId = "comment-composer"

    var body: some View {
        let trimmed = model.newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let canPost = !trimmed.isEmpty && trimmed.count <= RequestDetailModel.commentMax && !model.postingComment
        VStack(alignment: .leading, spacing: 0) {
            Text(model.comments.isEmpty ? "Comments" : "Comments (\(model.comments.count))")
                .font(Font(theme.surfaceFont(17, .bold)))
                .foregroundColor(Color(theme.text))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 0) {
                SurfaceMultilineField(
                    text: Binding(get: { model.newCommentBody },
                                  set: { model.newCommentBody = String($0.prefix(RequestDetailModel.commentMax)) }),
                    placeholder: "Add a comment",
                    maxLength: RequestDetailModel.commentMax,
                    minHeight: 72,
                    accessibilityLabel: "Request comment",
                    theme: theme,
                    editable: !model.postingComment,
                    onFocusChange: { onFocus(Self.composerId, $0) }
                )
                HStack {
                    Spacer()
                    SurfacePrimaryButtonView(title: "Post comment", theme: theme, disabled: !canPost,
                                             loading: model.postingComment, compact: true, fillWidth: false,
                                             action: model.postComment)
                        .accessibilityLabel(Text(model.postingComment ? "Posting request comment" : "Post request comment"))
                }
                .padding(.top, 4)
            }
            .id(Self.composerId)
            if let error = model.commentError {
                RequestNotice(text: error, theme: theme).padding(.top, 8)
            }
            if model.commentsLoading && model.comments.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(theme.primary)))
                    .padding(.top, 16)
            } else if model.comments.isEmpty {
                Text("No comments yet. Start the conversation.")
                    .font(Font(theme.surfaceFont(15)))
                    .foregroundColor(Color(theme.subtext))
                    .padding(.top, 16)
            } else {
                ForEach(model.comments) { comment in
                    // The row itself is the scroll target, so author, field
                    // and Save sit together when an edit field takes focus.
                    RequestCommentRow(comment: comment, theme: theme, model: model,
                                      onActions: { actionsFor = comment },
                                      onFocus: { onFocus("comment-edit-\(comment.id)", $0) })
                        .id("comment-edit-\(comment.id)")
                }
            }
        }
        .actionSheet(item: $actionsFor) { comment in
            ActionSheet(title: Text("Comment"), buttons: [
                .default(Text("Edit")) { model.editingCommentId = comment.id },
                .destructive(Text("Delete")) { confirmDelete = comment },
                .cancel()
            ])
        }
        .alert(item: $confirmDelete) { comment in
            Alert(title: Text("Delete comment?"), message: Text("This cannot be undone."),
                  primaryButton: .destructive(Text("Delete")) { model.deleteComment(commentId: comment.id) },
                  secondaryButton: .cancel())
        }
    }
}

@available(iOS 14.0, *)
private struct RequestCommentRow: View {
    let comment: RequestComment
    let theme: ResolvedTheme
    @ObservedObject var model: RequestDetailModel
    let onActions: () -> Void
    let onFocus: (Bool) -> Void
    @State private var draft = ""

    private var isEditing: Bool { model.editingCommentId == comment.id }

    var body: some View {
        let mine = comment.viewerIsAuthor
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(mine ? "You" : "Anonymous")
                    .font(Font(theme.surfaceFont(13, .bold)))
                    .foregroundColor(Color(mine ? theme.primary : theme.text))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(mine ? theme.tint : theme.fill)))
                Text(RequestRelativeTime.describe(comment.createdAt)
                     + (comment.updatedAt != comment.createdAt ? ", edited" : ""))
                    .font(Font(theme.surfaceFont(13)))
                    .foregroundColor(Color(theme.subtext))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if mine && !isEditing {
                    Button(action: onActions) {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle().fill(Color(theme.subtext)).frame(width: 4, height: 4)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SurfacePressStyle(pressedOpacity: 0.5))
                    .padding(.vertical, -12)
                    .accessibilityLabel(Text("Comment actions"))
                }
            }
            if isEditing {
                SurfaceMultilineField(text: $draft, placeholder: "", maxLength: RequestDetailModel.commentMax,
                                      minHeight: 72, accessibilityLabel: "Edit comment", theme: theme, autoFocus: true,
                                      onFocusChange: { onFocus($0) })
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: { model.editingCommentId = nil }) {
                        Text("Cancel")
                            .font(Font(theme.surfaceFont(15, .semibold)))
                            .foregroundColor(Color(theme.text))
                            .frame(minWidth: 64, minHeight: 44)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(SurfacePressStyle(pressedOpacity: 0.5))
                    let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    SurfacePrimaryButtonView(title: "Save", theme: theme,
                                             disabled: clean.isEmpty || clean.count > RequestDetailModel.commentMax,
                                             loading: model.savingEdit, compact: true, fillWidth: false) {
                        model.saveEdit(commentId: comment.id, body: draft)
                    }
                }
            } else {
                Text(comment.body)
                    .font(Font(theme.surfaceFont(15)))
                    .lineSpacing(5)
                    .foregroundColor(Color(theme.text))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Request comment body: \(comment.body)"))
            }
        }
        .padding(.vertical, 14)
        .overlay(RequestHeaderDivider(theme: theme), alignment: .top)
        .padding(.top, 4)
        .onAppear { draft = comment.body }
        .onChange(of: isEditing) { editing in if editing { draft = comment.body } }
    }
}

enum RequestRelativeTime {
    static func describe(_ iso: String, now: Date = Date()) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - Submit

@available(iOS 14.0, *)
struct SubmitRequestView: View {
    static let titleMax = 120
    static let descriptionMax = 1500

    let runtime: Runtime
    let theme: ResolvedTheme
    let onCancel: () -> Void
    let onPosted: (String) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    enum Field: Hashable { case title, description }
    @State private var focusedField: Field?
    @StateObject private var keyboard = KeyboardVisibility()
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSubmit: Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !submitting && !cleanTitle.isEmpty && cleanTitle.count <= Self.titleMax &&
            !cleanDescription.isEmpty && cleanDescription.count <= Self.descriptionMax
    }

    var body: some View {
        VStack(spacing: 0) {
            SurfaceHeaderBar(
                leading: {
                    SurfaceIconView(glyph: .close, color: theme.text, label: "Cancel new suggestion", action: onCancel)
                },
                center: {
                    Text("New suggestion")
                        .font(Font(theme.surfaceFont(17, .bold)))
                        .foregroundColor(Color(theme.text))
                        .lineLimit(1)
                },
                trailing: {
                    SurfacePrimaryButtonView(title: "Post", theme: theme, disabled: !canSubmit,
                                             loading: submitting, compact: true, fillWidth: false, action: submit)
                        .accessibilityLabel(Text("Post"))
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            RequestHeaderDivider(theme: theme)
            // Post stays in the header; the focused field's label and first
            // line are revealed at the top once focus or the keyboard settles.
            ScrollViewReader { proxy in
                ScrollView {
                    form
                        .frame(maxWidth: SurfaceMetrics.contentMaxWidth, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                }
                .onChange(of: focusedField) { FocusedFieldReveal.reveal($0, in: proxy, reduceMotion: reduceMotion) }
                .onChange(of: keyboard.settledFrames) { _ in
                    FocusedFieldReveal.reveal(focusedField, in: proxy, reduceMotion: reduceMotion)
                }
            }
        }
        .background(Color(theme.background).ignoresSafeArea())
    }

    private func trackFocus(_ field: Field) -> (Bool) -> Void {
        { focused in
            if focused { focusedField = field } else if focusedField == field { focusedField = nil }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Share an idea. Others can upvote it, and the team posts updates as work moves forward.")
                .font(Font(theme.surfaceFont(15)))
                .lineSpacing(5)
                .foregroundColor(Color(theme.subtext))
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                RequestNotice(text: errorMessage, theme: theme)
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Title")
                SurfaceLineField(
                    text: Binding(get: { title }, set: { title = String($0.prefix(Self.titleMax)) }),
                    placeholder: "A short, clear title",
                    accessibilityLabel: "Suggestion title",
                    theme: theme,
                    onFocusChange: trackFocus(.title)
                )
                HStack {
                    Spacer()
                    Text(verbatim: "\(title.count)/\(Self.titleMax)")
                        .font(Font(theme.surfaceFont(12)))
                        .foregroundColor(Color(theme.subtext))
                }
            }
            .id(Field.title)
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Description")
                SurfaceMultilineField(
                    text: Binding(get: { description },
                                  set: { description = String($0.prefix(Self.descriptionMax)) }),
                    placeholder: "What should it do, who is it for, and why does it matter?",
                    maxLength: Self.descriptionMax,
                    minHeight: 140,
                    accessibilityLabel: "Suggestion description",
                    theme: theme,
                    onFocusChange: trackFocus(.description)
                )
            }
            .id(Field.description)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Font(theme.surfaceFont(15, .semibold)))
            .foregroundColor(Color(theme.text))
    }

    private func submit() {
        guard canSubmit else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        submitting = true
        errorMessage = nil
        runtime.submitRequest(title: cleanTitle, description: cleanDescription) { result in
            DispatchQueue.main.async {
                submitting = false
                switch result {
                case .success(let request):
                    onPosted(request.id)
                case .failure(let error):
                    errorMessage = "Your suggestion wasn't posted. \(error.localizedDescription)"
                }
            }
        }
    }
}
