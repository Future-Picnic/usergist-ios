import Foundation
import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/requests/{RequestsHost,shared}.ts(x)
//
// Hosts and models for the suggestions board. Views live in
// RequestsBoardViews.swift and RequestDetailViews.swift. Every surface uses
// the app's SDK theme with the requests branding accent as primary.

@available(iOS 14.0, *)
enum RequestsBoardHost {
    private static let hosts = NSHashTable<UIViewController>.weakObjects()

    static func reset() {
        DispatchQueue.main.async {
            for host in hosts.allObjects { host.dismiss(animated: false) }
            hosts.removeAllObjects()
        }
    }

    static func present(runtime: Runtime, logger: UserGistLogger) {
        guard let top = TopViewControllerLocator.topMost() else {
            logger.warn("RequestsBoardHost: no presentable view controller")
            return
        }
        let themeModel = RequestsThemeModel(runtime: runtime)
        let model = RequestsBoardModel(runtime: runtime)
        let view = RequestsBoardView(model: model, themeModel: themeModel, runtime: runtime, onDismiss: { [weak top] in
            top?.presentedViewController?.dismiss(animated: true)
        })
        show(UIHostingController(rootView: view), themeModel: themeModel, over: top)
        model.loadFirstPage()
    }

    static func presentDetail(runtime: Runtime, requestId: String) {
        guard let top = TopViewControllerLocator.topMost() else { return }
        let themeModel = RequestsThemeModel(runtime: runtime)
        let view = RequestDetailContainer(runtime: runtime, requestId: requestId, themeModel: themeModel,
                                          onDismiss: { [weak top] in
            top?.presentedViewController?.dismiss(animated: true)
        })
        show(UIHostingController(rootView: view), themeModel: themeModel, over: top)
    }

    private static func show(_ host: UIViewController, themeModel: RequestsThemeModel, over top: UIViewController) {
        host.modalPresentationStyle = .pageSheet
        let apply: (ResolvedTheme) -> Void = { [weak host] theme in
            host?.view.backgroundColor = theme.background
            host?.overrideUserInterfaceStyle = theme.interfaceStyle
        }
        apply(themeModel.theme)
        themeModel.onChange = apply
        hosts.add(host)
        top.present(host, animated: true)
    }
}

// MARK: - Theme

/// App SDK theme + requests branding accent (RN `useRequestsTheme`).
@available(iOS 14.0, *)
final class RequestsThemeModel: ObservableObject {
    static let fallbackAccent = "#5B4BFF"
    static let fallbackTitle = "Suggestions"
    /// Branding rarely changes; reuse it across presentations (main thread only).
    private static var cachedBranding: RequestBranding?

    @Published private(set) var theme: ResolvedTheme
    @Published private(set) var title: String
    var onChange: ((ResolvedTheme) -> Void)?
    private var overrides: PromptTheme?

    init(runtime: Runtime) {
        let branding = Self.cachedBranding
        theme = Self.resolve(overrides: nil, accent: branding?.accentColor)
        title = Self.title(for: branding)
        runtime.readThemeOverrides { [weak self] overrides in
            self?.overrides = overrides
            self?.apply()
        }
        guard branding == nil else { return }
        runtime.getRequestBranding { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let value) = result else { return }
                Self.cachedBranding = value
                self?.apply()
            }
        }
    }

    private func apply() {
        theme = Self.resolve(overrides: overrides, accent: Self.cachedBranding?.accentColor)
        title = Self.title(for: Self.cachedBranding)
        onChange?(theme)
    }

    static func resolve(overrides: PromptTheme?, accent: String?) -> ResolvedTheme {
        let primary = accent.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackAccent
        return ThemeResolver.resolve(server: PromptTheme(colors: .init(primary: primary)), override: overrides)
    }

    private static func title(for branding: RequestBranding?) -> String {
        guard let label = branding?.entryLabel, !label.isEmpty else { return fallbackTitle }
        return label
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
    @Published private(set) var loadFailed = false
    @Published var notice: String?
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
        loadFailed = false
        runtime.listRequests(options: GetRequestsOptions(sort: sort)) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                switch result {
                case .success(let page):
                    self.items = page.items
                    self.nextCursor = page.nextCursor
                case .failure:
                    self.loadFailed = self.items.isEmpty
                }
            }
        }
    }

    func toggleVote(_ requestId: String) {
        guard !voteInFlight.contains(requestId),
              let row = items.first(where: { $0.id == requestId })
        else { return }
        voteInFlight.insert(requestId)
        notice = nil
        runtime.voteOnRequest(requestId: requestId, vote: !row.viewerHasUpvoted) {
            [weak self] result in
            DispatchQueue.main.async {
                self?.voteInFlight.remove(requestId)
                if case .failure = result { self?.notice = "Your vote wasn't saved. Check your connection and try again." }
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

// MARK: - Detail

@available(iOS 14.0, *)
final class RequestDetailModel: ObservableObject {
    static let commentMax = 1000

    @Published var request: FeatureRequest?
    @Published private(set) var loadFailed = false
    @Published var comments: [RequestComment] = []
    @Published private(set) var commentsLoading = true
    @Published var newCommentBody: String = ""
    @Published var postingComment = false
    @Published var commentError: String?
    @Published var actionError: String?
    @Published var editingCommentId: String?
    @Published private(set) var savingEdit = false
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
        loadFailed = false
        runtime.getRequest(requestId: requestId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let req): self.request = req
                case .failure: self.loadFailed = self.request == nil
                }
            }
        }
        commentsLoading = true
        runtime.getComments(requestId: requestId) { [weak self] result in
            DispatchQueue.main.async {
                self?.commentsLoading = false
                if case .success(let items) = result { self?.comments = items }
            }
        }
    }

    func toggleVote() {
        guard !requestMutationInFlight, let r = request else { return }
        requestMutationInFlight = true
        actionError = nil
        runtime.voteOnRequest(requestId: r.id, vote: !r.viewerHasUpvoted) {
            [weak self] result in
            DispatchQueue.main.async {
                self?.requestMutationInFlight = false
                if case .failure = result { self?.actionError = "Your vote wasn't saved. Try again." }
            }
        }
    }

    func toggleFollow() {
        guard !requestMutationInFlight, let r = request else { return }
        requestMutationInFlight = true
        actionError = nil
        runtime.followRequest(requestId: r.id, follow: !r.viewerIsFollowing) {
            [weak self] result in
            DispatchQueue.main.async {
                self?.requestMutationInFlight = false
                if case .failure = result { self?.actionError = "Follow wasn't updated. Try again." }
            }
        }
    }

    func postComment() {
        let body = newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !postingComment, !body.isEmpty, body.count <= Self.commentMax else { return }
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
                    self.commentError = "Your comment wasn't posted. \(error.localizedDescription)"
                }
            }
        }
    }

    /// Optimistic edit; restores the previous text if the server rejects it.
    func saveEdit(commentId: String, body: String) {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !savingEdit, !clean.isEmpty, clean.count <= Self.commentMax,
              let index = comments.firstIndex(where: { $0.id == commentId }) else { return }
        let before = comments
        let original = comments[index]
        comments[index] = original.replacingBody(clean)
        savingEdit = true
        commentError = nil
        runtime.editComment(requestId: requestId, commentId: commentId, body: clean) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.savingEdit = false
                switch result {
                case .success(let updated):
                    self.comments = self.comments.map { $0.id == commentId ? updated : $0 }
                    self.editingCommentId = nil
                case .failure(let error):
                    self.comments = before
                    self.commentError = "Your edit wasn't saved. \(error.localizedDescription)"
                }
            }
        }
    }

    /// Optimistic delete; puts the comment back if the server rejects it.
    func deleteComment(commentId: String) {
        let before = comments
        comments = comments.filter { $0.id != commentId }
        commentError = nil
        runtime.deleteComment(requestId: requestId, commentId: commentId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .failure(let error) = result else { return }
                self.comments = before
                self.commentError = "The comment wasn't deleted. \(error.localizedDescription)"
            }
        }
    }
}

private extension RequestComment {
    init(copying source: RequestComment, body: String, updatedAt: String) {
        id = source.id
        requestId = source.requestId
        self.body = body
        authorAnonymousId = source.authorAnonymousId
        authorExternalId = source.authorExternalId
        viewerIsAuthor = source.viewerIsAuthor
        createdAt = source.createdAt
        self.updatedAt = updatedAt
    }

    func replacingBody(_ body: String) -> RequestComment {
        RequestComment(copying: self, body: body, updatedAt: ISO8601DateFormatter().string(from: Date()))
    }
}

@available(iOS 14.0, *)
struct RequestDetailContainer: View {
    @StateObject private var model: RequestDetailModel
    @ObservedObject var themeModel: RequestsThemeModel
    let onDismiss: () -> Void

    init(runtime: Runtime, requestId: String, themeModel: RequestsThemeModel, onDismiss: @escaping () -> Void) {
        _model = StateObject(wrappedValue: RequestDetailModel(runtime: runtime, requestId: requestId))
        self.themeModel = themeModel
        self.onDismiss = onDismiss
    }

    var body: some View {
        RequestDetailView(model: model, theme: themeModel.theme, onDismiss: onDismiss)
            .onAppear { model.load() }
    }
}
