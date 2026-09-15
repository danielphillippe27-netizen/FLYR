import SwiftUI

struct WolfyHomeView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared

    var body: some View {
        Group {
            if let user = auth.user?.id, let workspaceID = workspace.workspaceId {
                WolfyHomeContent(userID: user, workspaceID: workspaceID)
                    .id("\(user):\(workspaceID)")
            } else {
                ContentUnavailableView("Your Home", systemImage: "house", description: Text("Sign in and select a workspace to see your activity."))
            }
        }
    }
}

private struct WolfyHomeContent: View {
    let userID: UUID
    let workspaceID: UUID
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WolfyHomeModel()
    @StateObject private var coach = WolfyCoachStore()
    @ObservedObject private var session = SessionManager.shared
    @State private var editingGoals = false

    private var currentCampaign: Campaign? {
        model.summary.campaigns?.first { $0.id == session.campaignId || $0.id == uiState.selectedMapCampaignId }
    }

    private var overdueFollowUp: ActivityFeedItem? {
        model.summary.followUps?.first { ($0.dueDate ?? .distantFuture) <= Date() }
    }

    private var recommendation: String {
        if let first = overdueFollowUp {
            return "Follow up with \(first.title). Review their next step before starting another block."
        }
        if let first = model.summary.appointments?.first {
            return "Your next appointment is \(first.title). Review the details and prepare."
        }
        if let target = model.summary.goals?.weekly_door_goal, let metrics = model.summary.metrics {
            let pace = WolfyHomePolicy.pace(target: target, completed: metrics.weekly_doors, days: WolfyHomePolicy.remainingDays(now: Date()))
            return pace == 0 ? "You've reached your weekly door goal. Review your follow-ups for the next opportunity." : "\(max(0, target - metrics.weekly_doors)) doors remain this week. Aim for \(pace) per day, including today."
        }
        return "Choose a campaign and set your door goal for today."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    card {
                        WolfyHomeCompanion(user:userID,workspace:workspaceID,summary:model.summary,active:session.isActive,insight:recommendation,coach:coach) {
                            uiState.selectedTabIndex = 1
                        }
                        Text(model.isLoading && model.updatedAt == nil ? "Loading your activity…" : recommendation)
                            .font(.headline)
                        Text("Suggested next step • Fixed rules")
                            .font(.caption).foregroundStyle(.secondary)
                        if overdueFollowUp != nil {
                            NavigationLink("Review follow-ups") { activity(.followUp, "Follow Up") }.buttonStyle(.borderedProminent)
                        } else if model.summary.appointments?.isEmpty == false {
                            NavigationLink("Review appointments") { activity(.appointments, "Appointments") }.buttonStyle(.borderedProminent)
                        }
                        if let brief = coach.brief, brief.source == "ai" {
                            Divider()
                            Label("Wolfy's tip · AI coach", systemImage: "sparkles").font(.caption.bold())
                            Text(brief.message).font(.subheadline)
                        } else {
                            Text(coach.loading ? "Getting Wolfy's tip…" : "Rule-based coaching · AI unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                        if let stats = model.summary.stats {
                            Text("\(stats.day_streak)-day activity streak")
                                .font(.subheadline.weight(.semibold))
                            Text("Personal all-time progress").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let sales = model.summary.sales { FieldSalesHomeCard(data: sales) }
                    if !model.summary.unavailable.isEmpty {
                        card {
                            Label("Some data is unavailable", systemImage: "wifi.exclamationmark").font(.headline)
                            Text(model.summary.unavailable.joined(separator: ", ")).font(.caption)
                            Button("Retry") { Task { await refresh() } }.disabled(model.isLoading)
                        }
                    }
                    card {
                        Text("Today").font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                            metric("Doors", model.summary.metrics?.doors)
                            metric("Conversations", model.summary.metrics?.conversations)
                            metric("Leads created", model.summary.metrics?.leads)
                            metric("Appointments set", model.summary.metrics?.appointments)
                        }
                        Text("Synced activity in this workspace").font(.caption).foregroundStyle(.secondary)
                    }
                    card {
                        HStack {
                            Text("Door goals").font(.title3.bold())
                            Spacer()
                            Button("Edit") { editingGoals = true }.disabled(model.summary.goals == nil)
                        }
                        if let goals = model.summary.goals {
                            goal("Today", target: goals.daily_door_goal, completed: model.summary.metrics?.doors)
                            goal("This week", target: goals.weekly_door_goal, completed: model.summary.metrics?.weekly_doors)
                            if let target = goals.weekly_door_goal, let count = model.summary.metrics?.weekly_doors {
                                Text("\(WolfyHomePolicy.pace(target: target, completed: count, days: WolfyHomePolicy.remainingDays(now: Date()))) doors/day needed through Sunday")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("Goals unavailable").foregroundStyle(.secondary) }
                    }
                    card {
                        Text(currentCampaign?.title ?? "Your next campaign").font(.title3.bold())
                        if currentCampaign == nil {
                            Text("Choose a territory to get started.").foregroundStyle(.secondary)
                        }
                        Button(session.sessionId != nil || currentCampaign != nil ? "Continue Campaign" : "Start Knocking") {
                            uiState.selectedTabIndex = 1
                        }.buttonStyle(.borderedProminent)
                        NavigationLink("Browse campaigns") { CampaignsView() }
                    }
                    card {
                        Text("Follow-ups due").font(.title3.bold())
                        feed(model.summary.followUps, empty: "No follow-ups due today.")
                        NavigationLink("View follow-ups") { activity(.followUp, "Follow Up") }
                    }
                    card {
                        Text("Upcoming appointments").font(.title3.bold())
                        feed(model.summary.appointments, empty: "No upcoming appointments.")
                        NavigationLink("View appointments") { activity(.appointments, "Appointments") }
                    }
                    card {
                        NavigationLink {
                            LeaderboardTabView()
                        } label: {
                            Label(model.summary.rank.map { "Weekly doors · #\($0)" } ?? "View leaderboard", systemImage: "trophy")
                        }
                    }
                    if let date = model.updatedAt {
                        Text("Last checked \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { uiState.selectedTabIndex = 4 } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Settings")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await refresh() } }
            .onChange(of: editingGoals) { _, editing in
                if !editing { Task { await coach.refresh(user: userID, workspace: workspaceID) } }
            }
            .refreshable { await refresh() }
            .overlay { if model.isLoading && model.updatedAt == nil { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
            .sheet(isPresented: $editingGoals) {
                WolfyGoalEditor(model: model)
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }

    }

    private func refresh() async {
        await model.load(userID: userID, workspaceID: workspaceID)
        await coach.refresh(user: userID, workspace: workspaceID)
    }
    private func activity(_ filter: ActivityFeedFilter, _ title: String) -> some View {
        ActivityView(initialFilter: filter, filters: [filter], navigationTitle: title)
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private func metric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.map(String.init) ?? "—").font(.title.bold()).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private func goal(_ title: String, target: Int?, completed: Int?) -> some View {
        if let target {
            Text("\(title): \(completed.map(String.init) ?? "—") / \(target)")
            if let completed { ProgressView(value: Double(min(completed, target)), total: Double(max(1, target))) }
        } else { Text("\(title): No goal set").foregroundStyle(.secondary) }
    }
    @ViewBuilder private func feed(_ items: [ActivityFeedItem]?, empty: String) -> some View {
        if let items {
            if items.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(Array(items.prefix(3))) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline)
                    if let due = item.dueDate { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
            }
        } else { Text("Unavailable. Pull to refresh.").foregroundStyle(.secondary) }
    }
}

private struct WolfyGoalEditor: View {
    @ObservedObject var model: WolfyHomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var daily = ""
    @State private var weekly = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal door targets") {
                    TextField("Daily target", text: $daily).keyboardType(.numberPad)
                    TextField("Weekly target", text: $weekly).keyboardType(.numberPad)
                    Text("Leave a target blank to clear it. The week runs Monday through Sunday.").font(.caption)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Door goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
        }.onAppear {
            daily = model.summary.goals?.daily_door_goal.map(String.init) ?? ""
            weekly = model.summary.goals?.weekly_door_goal.map(String.init) ?? ""
        }
    }
    private func save() {
        let d = daily.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = weekly.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (d.isEmpty || (Int(d).map { $0 > 0 } ?? false)), (w.isEmpty || (Int(w).map { $0 > 0 } ?? false)) else {
            error = "Use positive whole numbers, or leave a target blank."
            return
        }
        saving = true
        error = nil
        Task {
            do { try await model.saveGoals(daily: Int(d), weekly: Int(w)); dismiss() }
            catch { self.error = "Could not save goals. \(error.localizedDescription)" }
            saving = false
        }
    }
}
