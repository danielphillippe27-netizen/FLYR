import SwiftUI

struct WolfyHomeView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    var body: some View {
        Group {
            if let user = auth.user?.id, let workspaceID = workspace.workspaceId {
                WolfyHomeContent(userID: user, workspaceID: workspaceID).id("\(user):\(workspaceID)")
            } else {
                ContentUnavailableView("Your Home", systemImage: "house", description: Text("Sign in and select a workspace to see your activity."))
            }
        }
    }
}

private struct WolfyHomeContent: View {
    let userID: UUID
    let workspaceID: UUID
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = WolfyHomeModel()
    @StateObject private var coach = WolfyCoachStore()
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @AppStorage private var salesHome: Bool
    @State private var editingGoals = false
    @AppStorage("wolfy.haptics") private var haptics = true

    private var isFounderDemo: Bool {
        AuthManager.shared.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "daniel.phillippe27@gmail.com"
    }

    init(userID: UUID, workspaceID: UUID) {
        self.userID = userID
        self.workspaceID = workspaceID
        _salesHome = AppStorage(wrappedValue: false, "wolfy.home.sales.\(userID.uuidString)")
    }

    private var weeklyDoors: Int? {
        weekFact("doors").flatMap { $0.value }.flatMap(Int.init) ?? model.summary.metrics?.weekly_doors
    }
    private var weeklyGoal: Int? { isFounderDemo ? 300 : model.summary.goals?.weekly_door_goal }
    private func weekFact(_ key: String) -> WolfyKPIFact? {
        if isFounderDemo, let sample = demoWeekFacts[key] {
            return WolfyKPIFact(
                id: "scope.week.\(key)", label: sample.label, value: sample.value,
                display: sample.value, unit: "count", period: "week", group: "activity",
                source: "demo", note: nil
            )
        }
        if let metrics = model.summary.weeklyMetrics {
            let values: [String: Int] = [
                "doors": metrics.weekly_doors,
                "conversations": metrics.conversations,
                "leads": metrics.leads,
                "appointments": metrics.appointments
            ]
            let rates: [String: (Int, Int)] = [
                "conversation_rate": (metrics.conversations, metrics.weekly_doors),
                "lead_per_conversation": (metrics.leads, metrics.conversations),
                "appointment_per_lead": (metrics.appointments, metrics.leads)
            ]
            let value: String?
            if let count = values[key] { value = String(count) }
            else if let (numerator, denominator) = rates[key], denominator > 0 {
                value = String(Double(numerator) * 100 / Double(denominator))
            } else { value = nil }
            if let value {
                return WolfyKPIFact(
                    id: "scope.week.\(key)", label: key, value: value,
                    display: value, unit: rates[key] == nil ? "count" : "percent",
                    period: "week", group: "activity", source: "wolfy_home_metrics", note: nil
                )
            }
        }
        // Keep the verified report as a fallback when the direct weekly request is unavailable.
        return coach.homeReport?.facts.first { $0.id == "scope.week.\(key)" }
    }
    private var demoWeekFacts: [String: (label: String, value: String)] {
        ["doors": ("Doors", "186"), "conversations": ("Conversations", "31"),
         "leads": ("Leads", "8"), "appointments": ("Appointments", "3"),
         "conversation_rate": ("Answer rate", "17"), "lead_per_conversation": ("Lead rate", "26"),
         "appointment_per_lead": ("Appointment rate", "38")]
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = AuthManager.shared.user?.displayName?.split(separator: " ").first.map(String.init)
        return name.map { "\(hello), \($0)" } ?? hello
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if isFounderDemo {
                        Label("Demo data · Sample activity and scores", systemImage: "sparkles")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    if !network.isOnline {
                        Label("Offline · Showing last synced activity", systemImage: "wifi.slash")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 14) {
                        weeklyHeader
                        if salesHome {
                            FieldSalesCommissionHomeView(refreshToken: model.summary.sales?.as_of, showsHeader: false)
                        } else {
                            weeklyHero
                            funnel
                        }
                    }
                    if isFounderDemo { demoActivity }
                    VStack(spacing: 8) {
                        Divider()
                        wolfy
                    }
                    if !model.summary.unavailable.isEmpty {
                        HStack(alignment: .top) {
                            Label("Some data couldn't refresh. Check your connection.", systemImage: "wifi.exclamationmark")
                            Spacer()
                            Button("Retry") { Task { await refresh() } }.disabled(model.isLoading)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    campaignCTA
                }.padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refresh() }
            .sheet(isPresented: $editingGoals) { WolfyGoalEditor(model: model) }
            .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await refresh() } }
            .onChange(of: weeklyDoors) { old, new in
                guard haptics, let old, let new, let goal = weeklyGoal,
                      WolfyHomePolicy.crossedMilestone(from: old, to: new, target: goal) else { return }
                if new >= goal { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                else { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            }
        }
        .tint(Color.primary)
        .task {
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if scenePhase == .active && network.isOnline {
                    await model.loadAssignments(userID: userID, workspaceID: workspaceID)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting).font(.system(.title, design: .default, weight: .semibold))
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HomeAccountControls()
        }
    }
    private var weeklyHeader: some View {
        HStack {
            Text("THIS WEEK").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Menu {
                Picker("Primary home page", selection: $salesHome) {
                    Text("Doors").tag(false)
                    Text("Sales").tag(true)
                }
                if salesHome {
                    NavigationLink("Edit sales goals") { FieldSalesGoalsView() }
                } else {
                    Button("Edit door goals") { editingGoals = true }
                        .disabled(model.summary.goals == nil)
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Home settings")
            .accessibilityValue(salesHome ? "Sales" : "Doors")
        }
    }
    private var weeklyHero: some View {
        WolfyWeeklyRing(completed: weeklyDoors, target: weeklyGoal)
    }
    private var demoActivity: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT ACTIVITY").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                .padding(.bottom, 10)
            demoActivityRow("Morgan Bell", detail: "Appointment booked", time: "Today · 10:42 AM", icon: "calendar.badge.checkmark")
            Divider()
            demoActivityRow("Whitby North", detail: "12 conversations · 4 leads", time: "Today · 9:18 AM", icon: "bubble.left.and.bubble.right")
            Divider()
            demoActivityRow("Brooklin West", detail: "38 doors knocked", time: "Yesterday · 4:36 PM", icon: "door.left.hand.open")
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
    private func demoActivityRow(_ title: String, detail: String, time: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(time).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.padding(.vertical, 10)
    }
    private var funnel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) { funnelMetrics }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 24) { funnelMetrics }
        }.padding(.vertical, 8)
    }
    @ViewBuilder private var funnelMetrics: some View {
        funnelMetric("Doors", value: weeklyDoors.map(String.init), detail: "This week")
        funnelMetric("Talks", value: weekFact("conversations")?.value, detail: rate("conversation_rate", label: "answer rate"))
        funnelMetric("Leads", value: weekFact("leads")?.value, detail: rate("lead_per_conversation", label: "of talks"))
        funnelMetric("Appts", value: weekFact("appointments")?.value, detail: rate("appointment_per_lead", label: "of leads"))
    }
    private func rate(_ key: String, label: String) -> String {
        guard let value = weekFact(key)?.value.flatMap(Double.init) else { return "— \(label)" }
        return "\(Int(value.rounded()))% \(label)"
    }
    private func funnelMetric(_ label: String, value: String?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            Text(value ?? "—").font(.system(.title2, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 62, maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityHint("This week. Activity ratios compare counts, not matched lead conversion.")
    }
    private var wolfy: some View {
        WolfyHomeCompanion(user:userID,workspace:workspaceID,summary:model.summary,
                           active:session.isActive)
            .frame(maxWidth:.infinity,alignment:.center)
    }
    private var campaignCTA: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.assignments.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.assignments) { assignment in
                        NavigationLink {
                            NewCampaignDetailView(campaignID: assignment.campaignId, store: CampaignV2Store.shared)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map").font(.body).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(assignment.campaign?.name ?? "Assigned campaign")
                                        .font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                    Text(assignmentLabel(assignment)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if assignment.status.lowercased() == "assigned" {
                                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if assignment.id != model.assignments.last?.id { Divider() }
                    }
                }
            }
            if model.assignmentsUnavailable {
                HStack {
                    Text("Assignments couldn't refresh").foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await model.loadAssignments(userID: userID, workspaceID: workspaceID) } }
                }.font(.caption)
            }
            NavigationLink {
                CampaignsView(usesOwnNavigationStack: false)
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                HStack {
                    Spacer()
                    Text("Campaigns").font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain)
        }
    }
    private func assignmentLabel(_ assignment: CampaignAssignmentSummary) -> String {
        let label = assignment.assignedToUserId == nil ? "Team assignment" : assignment.status.lowercased() == "assigned" ? "New assignment" : "Assigned to you"
        return assignment.zoneIndex.map { "\(label) · Zone \($0)" } ?? label
    }
    private func refresh() async {
        async let home: () = model.loadPrimary(userID: userID, workspaceID: workspaceID)
        async let performance: () = coach.refreshHomeReport(user: userID, workspace: workspaceID)
        _ = await (home, performance)
        Task {
            async let supporting: () = model.loadSecondary(userID: userID, workspaceID: workspaceID)
            async let assignments: () = model.loadAssignments(userID: userID, workspaceID: workspaceID)
            _ = await (supporting, assignments)
        }
    }
}

struct WolfyWeeklyRing: View {
    let completed: Int?
    let target: Int?
    var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedProgress = 0.0
    private var fraction: Double { guard let completed, let target, target > 0 else { return 0 }; return min(1, max(0, Double(completed) / Double(target))) }
    private var done: Bool { guard let completed, let target else { return false }; return completed >= target }
    private var delta: Int { WolfyHomePolicy.weeklyPaceDelta(target: target ?? 0, completed: completed ?? 0, now: now) }
    private var ringColor: Color {
        if done || delta > 0 {
            return colorScheme == .dark
                ? Color(red: 0.48, green: 0.79, blue: 0.64)
                : Color(red: 0.16, green: 0.44, blue: 0.29)
        }
        if delta < 0 {
            return colorScheme == .dark
                ? Color(red: 0.87, green: 0.62, blue: 0.36)
                : Color(red: 0.58, green: 0.34, blue: 0.12)
        }
        return .primary
    }
    var body: some View {
        VStack(spacing: 24) {
            if typeSize.isAccessibilitySize {
                ring.frame(width: 220, height: 220)
                HStack { remaining; Spacer(); perDay }
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 8) {
                        remaining.frame(maxWidth: .infinity)
                        ring.frame(width: geometry.size.width * 0.59, height: geometry.size.width * 0.59)
                        perDay.frame(maxWidth: .infinity)
                    }.frame(height: geometry.size.height)
                }.frame(height: 226)
            }
            if let completed, let target, target > 0 {
                Text(done ? "WEEKLY GOAL COMPLETE" : "\(Int(Double(completed) / Double(target) * 100))% COMPLETE · \(delta > 0 ? "+\(delta) AHEAD OF PACE" : delta < 0 ? "\(-delta) BEHIND PACE" : "ON PACE")")
                    .font(.caption.weight(.medium)).tracking(0.5).foregroundStyle(ringColor)
                    .multilineTextAlignment(.center)
                    .accessibilityHint("Pace assumes an even target across seven calendar days")
            }
        }
        .onAppear { animateProgress() }
        .onChange(of: fraction) { _, _ in animateProgress() }
    }
    private var ring: some View {
        ZStack {
            Circle().stroke(Color(uiColor: .secondarySystemBackground), lineWidth: 10)
            Circle().trim(from: 0, to: displayedProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 8) {
                Text(completed.map(String.init) ?? "—").font(.system(size: 56, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(target.map { "/ \($0) DOORS" } ?? "DOORS THIS WEEK")
                    .font(.caption.weight(.medium)).tracking(1).foregroundStyle(.secondary)
                if done { Image(systemName: "checkmark").font(.headline).foregroundStyle(ringColor).transition(.scale.combined(with: .opacity)) }
            }.padding(20)
        }.padding(6).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(completed.map(String.init) ?? "Unavailable") of \(target.map(String.init) ?? "no target") doors this week")
    }
    private var remaining: some View {
        sideValue(completed.flatMap { count in target.map { String(max(0, $0 - count)) } }, label: "REMAINING")
    }
    private var perDay: some View {
        sideValue(completed.flatMap { count in target.map { String(WolfyHomePolicy.pace(target: $0, completed: count, days: WolfyHomePolicy.remainingDays(now: now))) } }, label: "PER DAY")
    }
    private func sideValue(_ value: String?, label: String) -> some View {
        VStack(spacing: 8) {
            Text(value ?? "—").font(.system(.title2, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func animateProgress() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { displayedProgress = fraction }
    }
}

#Preview("Weekly goal · active") {
    WolfyWeeklyRing(completed: 312, target: 500).padding(28).background(.black).preferredColorScheme(.dark)
}
#Preview("Weekly goal · complete") {
    WolfyWeeklyRing(completed: 500, target: 500).padding(28).background(.black).preferredColorScheme(.dark)
}
#Preview("Weekly goal · new user") {
    WolfyWeeklyRing(completed: 0, target: nil).padding(28).background(.black).preferredColorScheme(.dark)
}

#Preview("Weekly goal · light") {
    WolfyWeeklyRing(completed: 0, target: 1_000).padding(28)
        .background(Color(uiColor: .systemBackground)).preferredColorScheme(.light)
}
#Preview("Weekly goal · complete · light") {
    WolfyWeeklyRing(completed: 500, target: 500).padding(28)
        .background(Color(uiColor: .systemBackground)).preferredColorScheme(.light)
}

private struct WolfyGoalEditor: View {
    @ObservedObject var model: WolfyHomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var daily = ""
    @State private var weekly = ""
    @State private var days: Set<Int> = [1, 2, 3, 4, 5]
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
                Section {
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                if days.contains(day) { days.remove(day) } else { days.insert(day) }
                            } label: {
                                Text(["M", "T", "W", "T", "F", "S", "S"][day - 1])
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(days.contains(day) ? Color(uiColor: .systemBackground) : Color.primary)
                                    .background(days.contains(day) ? Color.primary : Color(uiColor: .tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day - 1])
                            .accessibilityAddTraits(days.contains(day) ? .isSelected : [])
                        }
                    }
                    Button("Monday–Friday") { days = [1, 2, 3, 4, 5] }
                } header: { Text("Goal days") } footer: {
                    Text("Tap the days you want a daily goal. Choose at least one day.")
                }
                .disabled(saving)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Door goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving || days.isEmpty) }
            }
            .interactiveDismissDisabled(saving)
        }.onAppear {
            daily = model.summary.goals?.daily_door_goal.map(String.init) ?? ""
            weekly = model.summary.goals?.weekly_door_goal.map(String.init) ?? ""
            days = Set(model.summary.goals?.scheduledDays ?? [1, 2, 3, 4, 5])
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
            do { try await model.saveGoals(daily: Int(d), weekly: Int(w), days: Array(days)); dismiss() }
            catch { self.error = "Could not save goals. \(error.localizedDescription)" }
            saving = false
        }
    }
}
