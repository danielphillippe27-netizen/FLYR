import SwiftUI

struct ActivityView: View {
    @StateObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var selectedFilter: ActivityFeedFilter = .activity
    @State private var items: [ActivityFeedItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSummaryItem: EndSessionSummaryItem?
    @State private var loadingSessionItemId: String?
    @State private var showSummaryError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            filterTabs
            Group {
                if isLoading {
                    loadingView
                } else if let message = errorMessage {
                    errorView(message: message)
                } else if items.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadItems()
        }
        .task {
            await loadItems()
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadItems() }
        }
        .alert("Couldn’t load session summary.", isPresented: $showSummaryError) {
            Button("OK", role: .cancel) {}
        }
        .fullScreenCover(item: $selectedSummaryItem) { item in
            ShareActivityGateView(
                data: item.data,
                sessionID: item.sessionID,
                campaignMapSnapshot: item.campaignMapSnapshot
            ) {
                selectedSummaryItem = nil
            }
        }
    }

    private var filterTabs: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(ActivityFeedFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedFilter == filter ? .text : .muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selectedFilter == filter ? Color.white.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(selectedFilter.rawValue.lowercased())...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName(for: selectedFilter))
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(emptyMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    activityRow(item)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func activityRow(_ item: ActivityFeedItem) -> some View {
        let rowContent = activityRowContent(item)
        if item.kind == .session {
            return AnyView(
                Button {
                    openSessionShareCard(for: item)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(loadingSessionItemId != nil)
            )
        } else {
            return AnyView(rowContent)
        }
    }

    private func activityRowContent(_ item: ActivityFeedItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tintColor(for: item.kind).opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: symbolName(for: item.kind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tintColor(for: item.kind))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if loadingSessionItemId == item.id {
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.muted)
                    .frame(minWidth: 48, alignment: .trailing)
            } else {
                if item.kind == .session {
                    Text(trailingLabel(for: item))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(item.timestamp, style: .relative)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary.opacity(0.75))
        )
    }

    private func trailingLabel(for item: ActivityFeedItem) -> String {
        let durationText = formatSessionDuration(item.sessionDurationSeconds)
        let dateText = sessionDateFormatter.string(from: item.timestamp)
        if dateText.isEmpty {
            return durationText
        }
        return "\(dateText) • \(durationText)"
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .activity:
            return "No activity yet"
        case .appointments:
            return "No appointments found"
        case .followUp:
            return "No follow-ups pending"
        }
    }

    private func iconName(for filter: ActivityFeedFilter) -> String {
        switch filter {
        case .activity:
            return "figure.walk"
        case .appointments:
            return "calendar"
        case .followUp:
            return "arrow.uturn.left.circle"
        }
    }

    private func symbolName(for kind: ActivityFeedKind) -> String {
        switch kind {
        case .session:
            return "figure.walk"
        case .appointment:
            return "calendar.badge.clock"
        case .followUp:
            return "arrow.uturn.left.circle.fill"
        }
    }

    private func tintColor(for kind: ActivityFeedKind) -> Color {
        switch kind {
        case .session:
            return .flyrPrimary
        case .appointment:
            return .purple
        case .followUp:
            return .orange
        }
    }

    private func formatSessionDuration(_ seconds: TimeInterval?) -> String {
        let totalSeconds = Int((seconds ?? 0).rounded())
        guard totalSeconds > 0 else { return "0 min" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(max(1, minutes)) min"
    }

    private func openSessionShareCard(for item: ActivityFeedItem) {
        guard item.kind == .session, let sessionId = item.sessionId else {
            showSummaryError = true
            return
        }
        loadingSessionItemId = item.id
        Task {
            do {
                let session = try await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionId)
                await MainActor.run {
                    loadingSessionItemId = nil
                    guard let session else {
                        showSummaryError = true
                        return
                    }
                    let summary = session.toSummaryData()
                    let hasAnyStats = summary.doorsCount > 0 || summary.conversations > 0 || summary.distance > 0 || summary.time > 0
                    guard hasAnyStats else {
                        showSummaryError = true
                        return
                    }
                    selectedSummaryItem = EndSessionSummaryItem(data: summary, sessionID: sessionId)
                }
            } catch {
                await MainActor.run {
                    loadingSessionItemId = nil
                    showSummaryError = true
                }
            }
        }
    }

    private func loadItems() async {
        guard let userId = auth.user?.id else {
            errorMessage = "Please sign in to view activity"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            items = try await ActivityFeedService.shared.fetchItems(
                userId: userId,
                workspaceId: workspace.workspaceId,
                includeMembers: false,
                filter: selectedFilter,
                limit: 150
            )
        } catch {
            errorMessage = "Failed to load \(selectedFilter.rawValue.lowercased())"
        }
        isLoading = false
    }

    private var sessionDateFormatter: DateFormatter {
        Self._sessionDateFormatter
    }

    private static let _sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
