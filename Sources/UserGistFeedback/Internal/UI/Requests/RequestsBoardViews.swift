import Foundation
import SwiftUI
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/requests/{BoardView,StatusPill}.tsx

@available(iOS 14.0, *)
enum RequestStatusStyle {
    /// Semantic status colours shared with the RN board and dashboard.
    static func color(_ status: RequestStatus) -> UIColor {
        let hex: String
        switch status {
        case .underReview: hex = "#9CA3AF"
        case .planned: hex = "#3B82F6"
        case .inProgress: hex = "#F59E0B"
        case .shipped: hex = "#22C55E"
        case .declined: hex = "#EF4444"
        }
        return SurfaceColor.parse(hex) ?? .gray
    }

    static func label(_ status: RequestStatus) -> String {
        switch status {
        case .underReview: return "Under review"
        case .planned: return "Planned"
        case .inProgress: return "In progress"
        case .shipped: return "Shipped"
        case .declined: return "Declined"
        }
    }
}

@available(iOS 14.0, *)
struct RequestStatusPill: View {
    let status: RequestStatus

    var body: some View {
        let color = RequestStatusStyle.color(status)
        HStack(spacing: 5) {
            Circle().fill(Color(color)).frame(width: 5, height: 5)
            Text(RequestStatusStyle.label(status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(color))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(color.withAlphaComponent(0.094))))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(color.withAlphaComponent(0.333)), lineWidth: 1))
    }
}

/// Board, detail and new-suggestion surfaces switch inside one sheet.
@available(iOS 14.0, *)
struct RequestsBoardView: View {
    @ObservedObject var model: RequestsBoardModel
    @ObservedObject var themeModel: RequestsThemeModel
    let runtime: Runtime
    let onDismiss: () -> Void
    @State private var selectedRequestId: String?
    @State private var showingSubmit = false

    var body: some View {
        Group {
            if let requestId = selectedRequestId {
                RequestDetailContainer(runtime: runtime, requestId: requestId, themeModel: themeModel,
                                       onDismiss: { selectedRequestId = nil })
            } else if showingSubmit {
                SubmitRequestView(
                    runtime: runtime,
                    theme: themeModel.theme,
                    onCancel: { showingSubmit = false },
                    onPosted: { requestId in
                        showingSubmit = false
                        model.loadFirstPage()
                        selectedRequestId = requestId
                    }
                )
            } else {
                RequestsBoardContent(model: model, theme: themeModel.theme, title: themeModel.title,
                                     onClose: onDismiss,
                                     onOpenDetail: { selectedRequestId = $0 },
                                     onOpenSubmit: { showingSubmit = true })
            }
        }
    }
}

@available(iOS 14.0, *)
private struct RequestsBoardContent: View {
    @ObservedObject var model: RequestsBoardModel
    let theme: ResolvedTheme
    let title: String
    let onClose: () -> Void
    let onOpenDetail: (String) -> Void
    let onOpenSubmit: () -> Void
    @State private var statusFilter: RequestStatus?

    private var filtered: [RequestSummary] {
        guard let statusFilter else { return model.items }
        return model.items.filter { $0.status == statusFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color(theme.border)).frame(height: 1 / UIScreen.main.scale)
            SurfaceLineField(text: $model.query, placeholder: "Search suggestions",
                             accessibilityLabel: "Search", theme: theme)
                .frame(maxWidth: SurfaceMetrics.contentMaxWidth)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            filters
            if let notice = model.notice {
                RequestNotice(text: notice, theme: theme).padding(.horizontal, 16).padding(.bottom, 8)
            }
            content
        }
        .background(Color(theme.background).ignoresSafeArea())
    }

    private var header: some View {
        SurfaceHeaderBar(
            leading: {
                SurfaceIconView(glyph: .close, color: theme.text, label: "Close requests board", action: onClose)
            },
            center: {
                VStack(spacing: 1) {
                    Text(title)
                        .font(Font(theme.surfaceFont(17, .bold)))
                        .foregroundColor(Color(theme.text))
                        .lineLimit(1)
                    Text("\(model.items.count) \(model.items.count == 1 ? "idea" : "ideas")")
                        .font(Font(theme.surfaceFont(13)).monospacedDigit())
                        .foregroundColor(Color(theme.subtext))
                }
            },
            trailing: {
                SurfacePrimaryButtonView(title: "New idea", theme: theme, compact: true, fillWidth: false,
                                         action: onOpenSubmit)
                    .accessibilityLabel(Text("Create new request"))
            }
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "All", count: model.items.count)
                ForEach(RequestStatus.allCases, id: \.self) { status in
                    let count = model.items.filter { $0.status == status }.count
                    if count > 0 { chip(status, label: RequestStatusStyle.label(status), count: count) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func chip(_ status: RequestStatus?, label: String, count: Int) -> some View {
        let active = statusFilter == status
        return Button(action: { statusFilter = status }) {
            HStack(spacing: 6) {
                if let status {
                    Circle().fill(Color(RequestStatusStyle.color(status))).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(Font(theme.surfaceFont(14, .semibold)))
                    .foregroundColor(Color(active ? theme.primary : theme.text))
                Text(verbatim: String(count))
                    .font(Font(theme.surfaceFont(13, .semibold)).monospacedDigit())
                    .foregroundColor(Color(active ? theme.primary : theme.subtext))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(active ? Color(theme.tint) : Color.clear))
            .overlay(Capsule().stroke(Color(active ? theme.primary : theme.border), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(SurfacePressStyle(pressedOpacity: 0.7))
        .accessibilityLabel(Text("\(label), \(count)"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        if model.loading && model.items.isEmpty {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(theme.primary)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.loadFailed {
            RequestEmptyState(title: "Suggestions couldn't load",
                              message: "Check your connection, then try again.",
                              actionTitle: "Try again", theme: theme, action: model.loadFirstPage)
        } else if filtered.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered, id: \.id) { row in
                        RequestCard(row: row, theme: theme, voteInFlight: model.voteInFlight.contains(row.id),
                                    onVote: { model.toggleVote(row.id) }, onOpen: { onOpenDetail(row.id) })
                    }
                }
                .frame(maxWidth: SurfaceMetrics.contentMaxWidth + 32)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            RequestEmptyState(title: "No matching suggestions", message: "Try different words or clear the search.",
                              actionTitle: nil, theme: theme, action: {})
        } else if !model.items.isEmpty {
            RequestEmptyState(title: "Nothing with this status", message: "Choose All to see every suggestion.",
                              actionTitle: nil, theme: theme, action: {})
        } else {
            RequestEmptyState(title: "No suggestions yet",
                              message: "Share the first idea for making this app better.",
                              actionTitle: "Share an idea", theme: theme, action: onOpenSubmit)
        }
    }
}

@available(iOS 14.0, *)
private struct RequestCard: View {
    let row: RequestSummary
    let theme: ResolvedTheme
    let voteInFlight: Bool
    let onVote: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let voted = row.viewerHasUpvoted
        HStack(alignment: .top, spacing: 14) {
            Button(action: onVote) {
                VStack(spacing: 4) {
                    ChevronShape(direction: .up)
                        .stroke(Color(voted ? theme.onPrimary : theme.primary),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 11, height: 6)
                    Text(verbatim: String(row.upvoteCount))
                        .font(Font(theme.surfaceFont(15, .bold)).monospacedDigit())
                        .foregroundColor(Color(voted ? theme.onPrimary : theme.primary))
                }
                .frame(width: 52)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: theme.cappedRadius(12))
                    .fill(Color(voted ? theme.primary : theme.tint)))
                .contentShape(Rectangle())
            }
            .buttonStyle(SurfacePressStyle())
            .disabled(voteInFlight)
            .accessibilityLabel(Text(
                voteInFlight ? "Updating vote for \(row.title)" :
                    (voted ? "Remove vote from \(row.title)" : "Upvote \(row.title)")
            ))
            .accessibilityAddTraits(voted ? .isSelected : [])
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title)
                        .font(Font(theme.surfaceFont(16, .semibold)))
                        .foregroundColor(Color(theme.text))
                        .lineLimit(2)
                    Text(row.description)
                        .font(Font(theme.surfaceFont(14)))
                        .foregroundColor(Color(theme.subtext))
                        .lineLimit(2)
                        .padding(.top, 4)
                    HStack(spacing: 10) {
                        RequestStatusPill(status: row.status)
                        Text(row.viewerIsFollowing ? "Following"
                             : "\(row.followerCount) \(row.followerCount == 1 ? "follower" : "followers")")
                            .font(Font(theme.surfaceFont(13)))
                            .foregroundColor(Color(theme.subtext))
                    }
                    .padding(.top, 10)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(SurfacePressStyle(pressedOpacity: 0.7))
            .accessibilityLabel(Text("Open request \(row.title)"))
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: theme.cappedRadius(18)).stroke(Color(theme.border), lineWidth: 1))
    }
}

@available(iOS 14.0, *)
struct RequestEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String?
    let theme: ResolvedTheme
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Font(theme.surfaceFont(18, .bold)))
                .foregroundColor(Color(theme.text))
                .multilineTextAlignment(.center)
            Text(message)
                .font(Font(theme.surfaceFont(15)))
                .lineSpacing(5)
                .foregroundColor(Color(theme.subtext))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 8)
            if let actionTitle {
                SurfacePrimaryButtonView(title: actionTitle, theme: theme, action: action)
                    .frame(minWidth: 200)
                    .fixedSize()
                    .padding(.top, 20)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline, non-blocking explanation of a failed action.
@available(iOS 14.0, *)
struct RequestNotice: View {
    let text: String
    let theme: ResolvedTheme

    var body: some View {
        Text(text)
            .font(Font(theme.surfaceFont(14)))
            .foregroundColor(Color(theme.text))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: theme.cappedRadius(14)).fill(Color(theme.fill)))
            .accessibilityAddTraits(.isStaticText)
    }
}
