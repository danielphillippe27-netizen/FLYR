import SwiftUI

struct FarmDetailView: View {
    @EnvironmentObject private var uiState: AppUIState
    @StateObject private var viewModel: FarmDetailViewModel
    @State private var showAnalytics = false
    @State private var showTouchPlanner = false
    @State private var showCycleMap = false
    @State private var isPreparingCycleMap = false
    @State private var selectedCycleForMap: FarmCycle?
    @State private var selectedCycleExecutionContext: FarmExecutionContext?
    @State private var cycleMapPreparationError: String?
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
        _viewModel = StateObject(wrappedValue: FarmDetailViewModel(farmId: farmId))
    }

    private var sortedCycles: [FarmCycle] {
        viewModel.cycles.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.cycleNumber < rhs.cycleNumber
            }
            return lhs.startDate < rhs.startDate
        }
    }

    private var currentCycle: FarmCycle? {
        let now = Date()
        if let activeIndex = sortedCycles.lastIndex(where: { $0.startDate <= now }) {
            return sortedCycles[activeIndex]
        }
        if let next = sortedCycles.first(where: { $0.startDate > now }) {
            return next
        }
        return sortedCycles.last
    }

    private var futureCycles: [FarmCycle] {
        let now = Date()
        return sortedCycles.filter { cycle in
            guard let currentCycle else {
                return cycle.startDate > now
            }
            return cycle.id != currentCycle.id && cycle.startDate > now
        }
    }

    private var primaryCampaignIdForMap: UUID? {
        let addressCampaignIds = viewModel.addresses.compactMap(\.campaignId)
        let addressCounts = Dictionary(grouping: addressCampaignIds, by: { $0 })
            .mapValues(\.count)

        if let mostCommonAddressCampaignId = addressCounts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.uuidString.localizedStandardCompare(rhs.key.uuidString) == .orderedAscending
            }
            return lhs.value < rhs.value
        })?.key {
            return mostCommonAddressCampaignId
        }

        let touchCampaignIds = viewModel.touches.compactMap(\.campaignId)
        let touchCounts = Dictionary(grouping: touchCampaignIds, by: { $0 })
            .mapValues(\.count)
        return touchCounts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.uuidString.localizedStandardCompare(rhs.key.uuidString) == .orderedAscending
            }
            return lhs.value < rhs.value
        })?.key
    }

    private func campaignId(for cycle: FarmCycle) -> UUID? {
        viewModel.preferredCampaignId(for: cycle, fallback: primaryCampaignIdForMap)
    }

    private func openCycleMap(for cycle: FarmCycle) {
        guard let campaignId = campaignId(for: cycle) else { return }
        isPreparingCycleMap = true
        cycleMapPreparationError = nil

        Task {
            let context = await viewModel.ensureExecutionContext(for: cycle, campaignId: campaignId)
            await MainActor.run {
                isPreparingCycleMap = false
                guard let context else {
                    cycleMapPreparationError = viewModel.errorMessage ?? "Couldn't prepare this cycle map."
                    return
                }
                selectedCycleForMap = cycle
                selectedCycleExecutionContext = context
                showCycleMap = true
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let farm = viewModel.farm {
                    FarmSummaryCard(farm: farm)
                        .padding(.horizontal, 16)

                    SectionHeader(title: "Current Cycle", icon: "repeat")
                        .padding(.horizontal, 16)

                    if let currentCycle {
                        CycleCard(
                            cycle: currentCycle,
                            canOpenMap: campaignId(for: currentCycle) != nil,
                            onOpenMap: {
                                openCycleMap(for: currentCycle)
                            }
                        )
                            .padding(.horizontal, 16)
                    } else {
                        EmptyCycleCard(
                            title: "No cycle running",
                            detail: futureCycles.isEmpty
                                ? "Open the planner to build the next cycle."
                                : "Your next cycle is queued below."
                        )
                        .padding(.horizontal, 16)
                    }

                    SectionHeader(title: "Future Cycles", icon: "calendar")
                        .padding(.horizontal, 16)

                    if futureCycles.isEmpty {
                        EmptyCycleCard(
                            title: "No future cycles yet",
                            detail: "Use the planner to line up the next rounds."
                        )
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(futureCycles) { cycle in
                            CycleCard(
                                cycle: cycle,
                                canOpenMap: campaignId(for: cycle) != nil,
                                onOpenMap: {
                                    openCycleMap(for: cycle)
                                }
                            )
                                .padding(.horizontal, 16)
                        }
                    }

                    PlanActionCard(
                        plannedCount: viewModel.touches.count,
                        completedCount: viewModel.touches.filter(\.completed).count,
                        cycleCount: viewModel.cycles.count,
                        onOpenPlanner: {
                            showTouchPlanner = true
                        }
                    )
                    .padding(.horizontal, 16)
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.farm?.name ?? "Farm")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAnalytics = true
                } label: {
                    Image(systemName: "chart.bar")
                }
            }
        }
        .sheet(isPresented: $showAnalytics) {
            if let farm = viewModel.farm {
                FarmAnalyticsView(farmId: farm.id)
            }
        }
        .sheet(isPresented: $showCycleMap, onDismiss: {
            selectedCycleForMap = nil
            selectedCycleExecutionContext = nil
        }) {
            if let cycle = selectedCycleForMap,
               let context = selectedCycleExecutionContext {
                NavigationStack {
                    CampaignMapView(
                        campaignId: context.campaignId.uuidString,
                        farmCycleNumber: cycle.cycleNumber,
                        farmCycleName: cycle.cycleName,
                        farmExecutionContext: context,
                        onDismissFromMap: {
                            showCycleMap = false
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showTouchPlanner, onDismiss: {
            Task {
                await viewModel.refreshAnalytics()
            }
        }) {
            NavigationStack {
                FarmTouchPlannerView(
                    farmId: farmId,
                    onStartSession: { context in
                        showTouchPlanner = false
                        uiState.beginPlannedFarmExecution(context)
                        uiState.selectedTabIndex = 1
                    }
                )
            }
        }
        .task {
            await viewModel.loadFarmData()
        }
        .refreshable {
            await viewModel.loadFarmData()
        }
        .overlay {
            if isPreparingCycleMap {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Opening cycle map...")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("Couldn't Open Cycle Map", isPresented: .init(
            get: { cycleMapPreparationError != nil },
            set: { if !$0 { cycleMapPreparationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cycleMapPreparationError ?? "Couldn't prepare this cycle map.")
        }
    }
}

struct PlanActionCard: View {
    let plannedCount: Int
    let completedCount: Int
    let cycleCount: Int
    let onOpenPlanner: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan")
                .font(.flyrHeadline)

            HStack(spacing: 12) {
                PlanMetricPill(title: "Touches", value: "\(plannedCount)")
                PlanMetricPill(title: "Done", value: "\(completedCount)")
                PlanMetricPill(title: "Cycles", value: "\(cycleCount)")
            }

            Button(action: onOpenPlanner) {
                HStack {
                    Text("Open Planner")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.flyrSubheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct PlanMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.flyrHeadline)
            Text(title)
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
        )
    }
}

// MARK: - Farm Summary Card

struct FarmSummaryCard: View {
    let farm: Farm
    
    private var cadenceLabel: String {
        let interval = (farm.touchesInterval?.lowercased() == "year") ? "year" : "month"
        let sessionCount = max(1, farm.touchesPerInterval ?? farm.frequency)
        let sessionLabel = sessionCount == 1 ? "session" : "sessions"
        return "\(sessionCount) \(sessionLabel)/\(interval)"
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(farm.name)
                    .font(.flyrTitle2Bold)
                
                Spacer()
                
                Badge(text: farm.isActive ? "Active" : "Completed")
            }
            
            Text("\(farm.startDate, formatter: dateFormatter) - \(farm.endDate, formatter: dateFormatter)")
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Label(cadenceLabel, systemImage: "calendar")
                Spacer()
                Label("\(Int(farm.progress * 100))% complete", systemImage: "chart.pie")
            }
            .font(.flyrSubheadline)
            .foregroundStyle(.secondary)
            
            ProgressView(value: farm.progress)
                .tint(.red)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(title)
                .font(.flyrHeadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Touch Row View

struct TouchRowView: View {
    let touch: FarmTouch
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: touch.type.iconName)
                .foregroundColor(colorForTouchType(touch.type))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(touch.title)
                    .font(.flyrSubheadline)
                
                Text(touch.date, formatter: dateFormatter)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if touch.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private func colorForTouchType(_ type: FarmTouchType) -> Color {
        switch type {
        case .flyer: return .blue
        case .doorKnock: return .green
        case .event: return .flyrPrimary
        case .newsletter: return .purple
        case .ad: return .yellow
        case .custom: return .gray
        }
    }
}

struct CycleCard: View {
    let cycle: FarmCycle
    let canOpenMap: Bool
    let onOpenMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(cycle.cycleName)
                    .font(.flyrHeadline)

                Spacer()

                Text("\(cycle.executedSessionCount)/\(cycle.plannedSessionCount)")
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(cycle.startDate, style: .date) - \(cycle.endDate, style: .date)")
                .font(.flyrCaption)
                .foregroundStyle(.secondary)

            ProgressView(value: cycle.plannedSessionCount > 0 ? Double(cycle.executedSessionCount) / Double(cycle.plannedSessionCount) : 0)
                .tint(.red)

            HStack(spacing: 12) {
                PlanMetricPill(title: "Sessions", value: "\(cycle.plannedSessionCount)")
                PlanMetricPill(title: "Doors hit", value: "\(cycle.doorsHitCount)")
            }

            if canOpenMap {
                Button(action: onOpenMap) {
                    HStack(spacing: 8) {
                        Image(systemName: "map")
                        Text("Open Cycle Map")
                    }
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct EmptyCycleCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.flyrHeadline)

            Text(detail)
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    NavigationStack {
        FarmDetailView(farmId: UUID())
    }
}
