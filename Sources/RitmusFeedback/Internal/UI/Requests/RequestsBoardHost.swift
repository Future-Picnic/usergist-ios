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

    static func present(runtime: Runtime, logger: RitmusLogger) {
        guard let top = TopViewControllerLocator.topMost() else {
            logger.warn("RequestsBoardHost: no presentable view controller")
            return
        }
        let model = RequestsBoardModel(runtime: runtime)
        let view = RequestsBoardView(model: model, onDismiss: { [weak top] in
            top?.presentedViewController?.dismiss(animated: true)
        })
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
        model.loadFirstPage()
    }

    static func presentDetail(runtime: Runtime, requestId: String) {
        guard let top = TopViewControllerLocator.topMost() else { return }
        let model = RequestDetailModel(runtime: runtime, requestId: requestId)
        let view = RequestDetailView(model: model, onDismiss: { [weak top] in
            top?.presentedViewController?.dismiss(animated: true)
        })
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
        model.load()
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
        guard let row = items.first(where: { $0.id == requestId }) else { return }
        runtime.voteOnRequest(requestId: requestId, vote: !row.viewerHasUpvoted) { _ in }
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
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Feature requests")
                    .font(.headline)
                Spacer()
                Button("Close", action: onDismiss)
            }
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
            if model.loading && model.items.isEmpty {
                ProgressView().padding(.top, 40)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.items, id: \.id) { row in
                        RequestRow(row: row, onVote: { model.toggleVote(row.id) })
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
    let onVote: () -> Void

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
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.body).bold()
                Text(row.description).font(.caption).foregroundColor(.secondary).lineLimit(2)
                Text(row.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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

    private let runtime: Runtime
    let requestId: String

    init(runtime: Runtime, requestId: String) {
        self.runtime = runtime
        self.requestId = requestId
    }

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
        guard let r = request else { return }
        runtime.voteOnRequest(requestId: r.id, vote: !r.viewerHasUpvoted) { [weak self] _ in
            self?.load()
        }
    }

    func toggleFollow() {
        guard let r = request else { return }
        runtime.followRequest(requestId: r.id, follow: !r.viewerIsFollowing) { [weak self] _ in
            self?.load()
        }
    }

    func postComment() {
        let body = newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        runtime.postComment(requestId: requestId, body: body) { [weak self] _ in
            DispatchQueue.main.async {
                self?.newCommentBody = ""
                self?.load()
            }
        }
    }
}

@available(iOS 14.0, *)
struct RequestDetailView: View {
    @ObservedObject var model: RequestDetailModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Request")
                    .font(.headline)
                Spacer()
                Button("Close", action: onDismiss)
            }
            if let r = model.request {
                Text(r.title).font(.title3).bold()
                Text(r.description).font(.body)
                HStack(spacing: 12) {
                    Button(action: model.toggleVote) {
                        Label("\(r.upvoteCount)", systemImage: r.viewerHasUpvoted ? "chevron.up.circle.fill" : "chevron.up.circle")
                    }
                    Button(action: model.toggleFollow) {
                        Label("\(r.followerCount)", systemImage: r.viewerIsFollowing ? "bell.fill" : "bell")
                    }
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
                            Text(c.isFromTeam ? "Team" : "Anonymous")
                                .font(.caption).foregroundColor(.secondary)
                            Text(c.body).font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            HStack {
                TextField("Add a comment", text: $model.newCommentBody)
                    .textFieldStyle(.roundedBorder)
                Button("Send", action: model.postComment)
            }
        }
        .padding(16)
    }
}
