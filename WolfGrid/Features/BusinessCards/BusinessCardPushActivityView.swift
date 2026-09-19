import SwiftUI

struct BusinessCardPushRoute: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let workspaceId: UUID
    let label: String
    init?(userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "business_card_activity",
              let share = userInfo["share_id"] as? String, let id = UUID(uuidString: share),
              let user = userInfo["user_id"] as? String, let userId = UUID(uuidString: user),
              let workspace = userInfo["workspace_id"] as? String, let workspaceId = UUID(uuidString: workspace) else { return nil }
        self.id = id; self.userId = userId; self.workspaceId = workspaceId
        label = userInfo["activity_label"] as? String ?? "Business card"
    }
}

struct BusinessCardPushActivityView: View {
    let route: BusinessCardPushRoute
    @Environment(\.dismiss) private var dismiss
    @State private var shares: [BusinessCardActivityResponse.Share] = []
    @State private var message = "Loading activity…"
    var body: some View {
        NavigationStack {
            List {
                Text(route.label).font(.headline)
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                ForEach(shares) { share in
                    ForEach(share.card_events.sorted { $0.created_at > $1.created_at }) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.event_type == "qualified_open" ? "Card opened" : event.event_type.replacingOccurrences(of: "_", with: " ").capitalized)
                            if let detail = event.detail, !detail.isEmpty { Text(detail) }
                            Text(event.created_at.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Business Card Activity")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }
    private func refresh() async {
        do {
            let result: BusinessCardActivityResponse = try await BusinessCardAPI.request("activity?shareId=\(route.id.uuidString)", workspaceID: route.workspaceId, expectedUserID: route.userId)
            shares = result.shares; message = shares.isEmpty ? "No activity available." : ""
        } catch { message = error.localizedDescription }
    }
}
