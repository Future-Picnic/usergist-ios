import Foundation
import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/RequestsBoard.tsx
//                                    /RequestDetailView.tsx
//                                    /SubmitRequestSheet.tsx
//
// SwiftUI shells for the Feature Requests pillar. Minimal — matches the
// RN surface (board / detail / submit) without the design polish, so the
// API parity check can flip the cells to `full` while UX iterations
// continue in follow-up work.

@available(iOS 14.0, *)
enum RequestsBoardHost {

    static func present(runtime: Runtime, logger: UserGistLogger) {
        guard let top = TopViewControllerLocator.topMost() else {
            logger.warn("RequestsBoardHost: no presentable view controller")
            return
        }
        let model = RequestsBoardModel(runtime: runtime)
        let view = RequestsBoardView(model: model, runtime: runtime, onDismiss: { [weak top] in
            top?.presentedViewController?.dismiss(animated: true)
        })
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
        model.loadFirstPage()
    }

    static func presentDetail(runtime: Runtime, requestId: String) {
        guard let top = TopViewControllerLocator.topMost() else { return }
        let view = RequestDetailContainer(runtime: runtime, requestId: requestId, onDismiss: { [weak top] in
            top?.presentedViewController?.dismiss(animated: true)
        })
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
    }

}

// MARK: - Board

@available(iOS 14.0, *)
final class RequestsBoardModel: ObservableObject {
    @Published var items: [RequestSummary] = []
    @Published var query: String = "" {
        didSet { debouncer.query(query) }
    }
    @Published var nextCursor: String? = nil
    @Published var loading: Bool = false
    @Published private(set) var voteInFlight: Set<String> = []

    private let runtime: Runtime
    private let debouncer: DebouncedSearch<GetRequestsResult>
    private var unsubscribeCache: (() -> Void)?
    private var sort: RequestSort = .top

    init(runtime: Runtime) {
        self.runtime = runtime
        let rt = runtime
        self.debouncer = DebouncedSearch<GetRequestsResult>(delayMs: 300) { q, completion in
            rt.listRequests(options: GetRequestsOptions(sort: .top, q: q)) { result in
                completion(result.mapError { $0 as Error })
            }
        }
        _ = self.debouncer.subscribe { [weak self] _, page in
            DispatchQueue.main.async {
                self?.items = page.items
                self?.nextCursor = page.nextCursor
            }
        }
        // Subscribe to optimistic-cache notifications so vote/follow taps
        // re-render this row instantly without a full page reload.
        self.unsubscribeCache = runtime.requestsCache.subscribe { [weak self] id, req in
            DispatchQueue.main.async { self?.patchRow(id: id, req: req) }
        }
    }

    deinit { unsubscribeCache?() }

    func loadFirstPage() {
        loading = true
        runtime.listRequests(options: GetRequestsOptions(sort: sort)) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                if case .success(let page) = result {
                    self.items = page.items
                    self.nextCursor = page.nextCursor
                }
            }
        }
    }

    func toggleVote(_ requestId: String) {
        guard !voteInFlight.contains(requestId),
              let row = items.first(where: { $0.id == requestId })
        else { return }
        voteInFlight.insert(requestId)
        runtime.voteOnRequest(requestId: requestId, vote: !row.viewerHasUpvoted) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.voteInFlight.remove(requestId)
            }
        }
    }

    private func patchRow(id: String, req: FeatureRequest) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let prior = items[idx]
        items[idx] = RequestSummary(
            id: prior.id,
            title: prior.title,
            description: prior.description,
            status: req.status,
            upvoteCount: req.upvoteCount,
            followerCount: req.followerCount,
            createdAt: prior.createdAt,
            statusChangedAt: prior.statusChangedAt,
            viewerHasUpvoted: req.viewerHasUpvoted,
            viewerIsFollowing: req.viewerIsFollowing
        )
    }
}

@available(iOS 14.0, *)
struct RequestsBoardView: View {
    @ObservedObject var model: RequestsBoardModel
    let runtime: Runtime
    let onDismiss: () -> Void
    @State private var selectedRequestId: String?
    @State private var showingSubmit = false

    var body: some View {
        Group {
            if let requestId = selectedRequestId {
                RequestDetailContainer(
                    runtime: runtime,
                    requestId: requestId,
                    onDismiss: { selectedRequestId = nil }
                )
            } else if showingSubmit {
                SubmitRequestView(
                    runtime: runtime,
                    onCancel: { showingSubmit = false },
                    onPosted: { requestId in
                        showingSubmit = false
                        model.loadFirstPage()
                        selectedRequestId = requestId
                    }
                )
            } else {
                board
            }
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Close", action: onDismiss)
                    .accessibilityLabel("Close requests board")
                Spacer()
                Text("Feature requests")
                    .font(.headline)
                Spacer()
                Button("+ New") { showingSubmit = true }
                    .accessibilityLabel("Create new request")
            }
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
            if model.loading && model.items.isEmpty {
                ProgressView().padding(.top, 40)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.items, id: \.id) { row in
                        RequestRow(
                            row: row,
                            voteInFlight: model.voteInFlight.contains(row.id),
                            onVote: { model.toggleVote(row.id) },
                            onOpen: { selectedRequestId = row.id }
                        )
                    }
                }
            }
        }
        .padding(16)
    }
}

@available(iOS 14.0, *)
private struct RequestRow: View {
    let row: RequestSummary
    let voteInFlight: Bool
    let onVote: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onVote) {
                VStack {
                    Image(systemName: row.viewerHasUpvoted ? "chevron.up.circle.fill" : "chevron.up.circle")
                        .font(.title3)
                    Text("\(row.upvoteCount)")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(voteInFlight)
            .accessibilityLabel(
                voteInFlight ? "Updating vote for \(row.title)" :
                    (row.viewerHasUpvoted ? "Remove vote from \(row.title)" : "Upvote \(row.title)")
            )
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.body).bold()
                    Text(row.description).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(row.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        Text("\(row.followerCount) followers")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open request \(row.title)")
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Detail

@available(iOS 14.0, *)
final class RequestDetailModel: ObservableObject {
    @Published var request: FeatureRequest?
    @Published var comments: [RequestComment] = []
    @Published var newCommentBody: String = ""
    @Published var postingComment = false
    @Published var commentError: String?
    @Published private(set) var requestMutationInFlight = false

    private let runtime: Runtime
    private var unsubscribeCache: (() -> Void)?
    let requestId: String

    init(runtime: Runtime, requestId: String) {
        self.runtime = runtime
        self.requestId = requestId
        self.unsubscribeCache = runtime.requestsCache.subscribe { [weak self] id, request in
            guard id == requestId else { return }
            DispatchQueue.main.async { self?.request = request }
        }
    }

    deinit { unsubscribeCache?() }

    func load() {
        runtime.getRequest(requestId: requestId) { [weak self] result in
            if case .success(let req) = result {
                DispatchQueue.main.async { self?.request = req }
            }
        }
        runtime.getComments(requestId: requestId) { [weak self] result in
            if case .success(let items) = result {
                DispatchQueue.main.async { self?.comments = items }
            }
        }
    }

    func toggleVote() {
        guard !requestMutationInFlight, let r = request else { return }
        requestMutationInFlight = true
        runtime.voteOnRequest(requestId: r.id, vote: !r.viewerHasUpvoted) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.requestMutationInFlight = false
            }
        }
    }

    func toggleFollow() {
        guard !requestMutationInFlight, let r = request else { return }
        requestMutationInFlight = true
        runtime.followRequest(requestId: r.id, follow: !r.viewerIsFollowing) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.requestMutationInFlight = false
            }
        }
    }

    func postComment() {
        let body = newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !postingComment, !body.isEmpty, body.count <= 1000 else { return }
        postingComment = true
        commentError = nil
        newCommentBody = ""
        runtime.postComment(requestId: requestId, body: body) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.postingComment = false
                switch result {
                case .success(let comment):
                    if !self.comments.contains(where: { $0.id == comment.id }) {
                        self.comments.append(comment)
                    }
                case .failure(let error):
                    if self.newCommentBody.isEmpty { self.newCommentBody = body }
                    self.commentError = error.localizedDescription
                }
            }
        }
    }
}

@available(iOS 14.0, *)
private struct RequestDetailContainer: View {
    @StateObject private var model: RequestDetailModel
    let onDismiss: () -> Void

    init(runtime: Runtime, requestId: String, onDismiss: @escaping () -> Void) {
        _model = StateObject(wrappedValue: RequestDetailModel(runtime: runtime, requestId: requestId))
        self.onDismiss = onDismiss
    }

    var body: some View {
        RequestDetailView(model: model, onDismiss: onDismiss)
            .onAppear { model.load() }
    }
}

@available(iOS 14.0, *)
struct RequestDetailView: View {
    @ObservedObject var model: RequestDetailModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("‹ Back", action: onDismiss)
                    .accessibilityLabel("Back to requests")
                Spacer()
                Text("SUGGESTION")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }
            if let r = model.request {
                Text(r.title).font(.title3).bold()
                Text(r.description).font(.body)
                HStack(spacing: 12) {
                    Button(action: model.toggleVote) {
                        Label("\(r.upvoteCount)", systemImage: r.viewerHasUpvoted ? "chevron.up.circle.fill" : "chevron.up.circle")
                    }
                    .disabled(model.requestMutationInFlight)
                    .accessibilityLabel(
                        model.requestMutationInFlight ? "Updating request vote" :
                            (r.viewerHasUpvoted ? "Remove request vote" : "Upvote request")
                    )
                    Button(action: model.toggleFollow) {
                        Label("\(r.followerCount)", systemImage: r.viewerIsFollowing ? "bell.fill" : "bell")
                    }
                    .disabled(model.requestMutationInFlight)
                    .accessibilityLabel(
                        model.requestMutationInFlight ? "Updating request follow" :
                            (r.viewerIsFollowing ? "Unfollow request" : "Follow request")
                    )
                }
                if let dev = r.devResponse, !dev.isEmpty {
                    Text(dev).font(.callout).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(6)
                }
            } else {
                ProgressView()
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.comments) { c in
                        VStack(alignment: .leading) {
                            Text(c.viewerIsAuthor ? "You" : "Anonymous")
                                .font(.caption).foregroundColor(.secondary)
                            Text(c.body).font(.body)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Request comment body: \(c.body)")
                    }
                }
            }
            HStack {
                TextField("Add a comment", text: $model.newCommentBody)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Request comment")
                    .disabled(model.postingComment)
                Button(model.postingComment ? "Posting…" : "Send", action: model.postComment)
                    .accessibilityLabel(
                        model.postingComment ? "Posting request comment" : "Post request comment"
                    )
                    .disabled(
                        model.postingComment ||
                            model.newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            if let commentError = model.commentError {
                Text(commentError).font(.caption).foregroundColor(.red)
            }
        }
        .padding(16)
    }
}

// MARK: - Submit

@available(iOS 14.0, *)
private struct SubmitRequestView: View {
    let runtime: Runtime
    let onCancel: () -> Void
    let onPosted: (String) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !submitting && !cleanTitle.isEmpty && cleanTitle.count <= 120 &&
            !cleanDescription.isEmpty && cleanDescription.count <= 1500
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Text("New suggestion").font(.headline)
                Spacer()
                Button(submitting ? "Posting…" : "Post", action: submit)
                    .disabled(!canSubmit)
                    .accessibilityLabel("Post")
            }

            Text("Tell us what you'd like to see. Other users can upvote your idea, and the team will respond as work progresses.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Title").font(.caption).bold()
            TextField("A short, clear title", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Suggestion title")

            HStack {
                Text("Description").font(.caption).bold()
                Spacer()
                Text("\(description.count)/1500").font(.caption2).foregroundColor(.secondary)
            }
            TextEditor(text: $description)
                .frame(minHeight: 140)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
                .accessibilityLabel("Suggestion description")

            if let errorMessage = errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }
            Spacer()
        }
        .padding(16)
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
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
