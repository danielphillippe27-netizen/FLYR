import SwiftUI
import CoreLocation

struct FarmDetailView: View {
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var campaignDownloadService: CampaignDownloadService
    @StateObject private var viewModel: FarmDetailViewModel
    @State private var showAnalytics = false
    @State private var showTouchPlanner = false
    @State private var isStartingTouch = false
    @State private var touchPreparationError: String?
    @State private var selectedSessionType: FarmTouchType = .doorKnock
    @State private var selectedPlanTouchId: UUID?
    @State private var isLeadsExpanded = false
    @State private var isAddressesExpanded = false
    @State private var showAllAddresses = false
    @State private var showAllLeads = false

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

    private var nextTouch: FarmTouch? {
        let incomplete = viewModel.touches.filter {
            !$0.completed && $0.isFarmFieldTouch
        }
        let now = Date()
        if let upcoming = incomplete
            .filter({ $0.date >= now })
            .sorted(by: touchSort)
            .first {
            return upcoming
        }
        return incomplete.sorted(by: touchSort).first
    }

    private var planTouches: [FarmTouch] {
        viewModel.touches
            .sorted(by: touchSort)
    }

    private var startablePlanTouches: [FarmTouch] {
        viewModel.touches
            .filter { !$0.completed }
            .sorted(by: touchSort)
    }

    private var primaryCampaignIdForMap: UUID? {
        if let linkedCampaignId = viewModel.linkedCampaignId { return linkedCampaignId }

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

    private var farmMapCenter: CLLocationCoordinate2D? {
        if let polygonCenter = averageCoordinate(viewModel.farm?.polygonCoordinates ?? []) {
            return polygonCenter
        }
        return nil
    }

    private func touchSort(_ lhs: FarmTouch, _ rhs: FarmTouch) -> Bool {
        if lhs.date == rhs.date {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.date < rhs.date
    }

    private func campaignId(for cycle: FarmCycle) -> UUID? {
        viewModel.preferredCampaignId(for: cycle, fallback: primaryCampaignIdForMap)
    }

    private func startSession() {
        isStartingTouch = true
        touchPreparationError = nil

        let linkedTouch = selectedPlanTouchId.flatMap { id in
            viewModel.touches.first { $0.id == id }
        }
        let sessionType = selectedSessionType
        let fallbackCampaignId = primaryCampaignIdForMap

        Task {
            let context: FarmExecutionContext?
            if let touch = linkedTouch {
                context = await MainActor.run {
                    viewModel.executionContext(for: touch, fallbackCampaignId: fallbackCampaignId)
                }
            } else {
                context = await viewModel.ensureSessionExecutionContext(type: sessionType, campaignId: fallbackCampaignId)
            }

            await MainActor.run {
                isStartingTouch = false
                guard let context else {
                    touchPreparationError = viewModel.errorMessage ?? "This farm needs a linked campaign before you can start a session."
                    return
                }
                uiState.beginPlannedFarmExecution(context)
                uiState.selectedTabIndex = 1
            }
        }
    }

    private func makeMapSessionContext(for type: FarmTouchType) async -> FarmExecutionContext? {
        await viewModel.ensureSessionExecutionContext(type: type, campaignId: primaryCampaignIdForMap)
    }

    private func offlineCard(campaignId: UUID) -> some View {
        let id = campaignId.uuidString
        let state = campaignDownloadService.state(for: id)
        let ready = state?.isAvailableOffline == true && campaignDownloadService.readiness(for: id)?.isVerified == true
        let downloading = state?.status == "downloading"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(ready ? Color.success : Color.primary)
                Text(ready ? "Downloaded" : "Not downloaded")
                    .font(.subheading)
                Spacer()
                Button(ready ? "Update" : "Download") {
                    Task {
                        await campaignDownloadService.makeAvailableOffline(campaignId: id)
                        await campaignDownloadService.refreshState(campaignId: id)
                    }
                }
                .font(.label).padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.bgTertiary).clipShape(Capsule()).buttonStyle(.plain)
                .disabled(downloading)
            }
            Text(ready ? "Homes, parcels, and map data are saved on this device." : "Download the map and homes before working without service.")
                .font(.caption).foregroundColor(.muted)
        }
        .padding(16).background(Color.bgSecondary).cornerRadius(12)
        .task(id: id) { await campaignDownloadService.refreshState(campaignId: id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let farm = viewModel.farm {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(farm.name).font(.heading).foregroundColor(.text)
                            Spacer()
                            Badge(text: farm.isActive ? "Active" : "Completed")
                        }
                        Text("Created \(farm.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.flyrCaption).foregroundColor(.muted)
                    }
                    FarmProgressCard(planned: farm.addressCount ?? 0, completed: viewModel.visitedHomeCount ?? 0, visits: viewModel.homeVisitCount ?? 0, visitsAreMinimum: viewModel.homeVisitCountIsMinimum,
                                     isLoading: viewModel.isLoading, loadFailed: viewModel.visitedHomeCount == nil || farm.addressCount == nil)

                    FarmDetailSectionHeader(title: "Farm Area")
                    FarmAreaCard(
                        campaignId: primaryCampaignIdForMap,
                        mapCenter: farmMapCenter,
                        polygon: farm.polygonCoordinates,
                        isLoading: viewModel.isLoading,
                        selectedType: $selectedSessionType,
                        makeExecutionContext: makeMapSessionContext
                    )

                    if let campaignId = primaryCampaignIdForMap {
                        FarmDetailSectionHeader(title: "Offline")
                        offlineCard(campaignId: campaignId)
                    }

                    FarmDetailSectionHeader(title: "Analytics")
                    HStack(spacing: 10) {
                        FarmHeroStatPill(value: farm.addressCount.map(String.init) ?? "—", label: "Homes")
                        FarmHeroStatPill(value: viewModel.leadsLoadFailed || viewModel.isLoading ? "—" : "\(viewModel.leads.count)", label: "Farm leads")
                        FarmHeroStatPill(value: viewModel.isLoading ? "—" : viewModel.visitedHomeCount.map(String.init) ?? "—", label: "Homes visited")
                    }

                    FarmExpandableSection(title: "Leads", icon: "tray.full.fill", count: viewModel.leadsLoadFailed || viewModel.isLoading ? nil : viewModel.leads.count, expanded: $isLeadsExpanded) {
                        if viewModel.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        } else if viewModel.leadsLoadFailed {
                            Text("Farm leads could not be loaded. Pull down to retry.").foregroundColor(.muted)
                        } else if viewModel.leads.isEmpty {
                            Text("No farm leads yet").foregroundColor(.muted)
                        } else {
                            ForEach(Array(viewModel.leads.sorted { $0.createdAt > $1.createdAt }.prefix(5))) { lead in
                                RecentLeadRow(lead: lead)
                            }
                            if viewModel.leads.count > 5 {
                                Button("See all \(viewModel.leads.count) leads") { showAllLeads = true }.foregroundColor(.accent)
                            }
                        }
                    }
                    FarmExpandableSection(title: "Addresses", icon: "house.fill", count: farm.addressCount, expanded: $isAddressesExpanded) {
                        if viewModel.isLoadingAddresses && viewModel.addresses.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        } else if viewModel.addressesLoadFailed && viewModel.addresses.isEmpty {
                            Button("Could not load addresses. Tap to retry.") { Task { await viewModel.loadAddresses(reset: true) } }.foregroundColor(.accent)
                        } else if viewModel.addresses.isEmpty {
                            Text("No addresses available").foregroundColor(.muted)
                        } else {
                            ForEach(Array(viewModel.addresses.prefix(5))) { address in
                                Text(address.formatted).foregroundColor(.text)
                            }
                            if viewModel.addresses.count > 5 || viewModel.addressesHaveMore {
                                Button("View addresses") { showAllAddresses = true }.foregroundColor(.accent)
                            }
                        }
                    }

                    FarmDetailSectionHeader(title: "Start Session")
                    StartSessionCard(
                        selectedType: $selectedSessionType,
                        selectedPlanTouchId: $selectedPlanTouchId,
                        planTouches: startablePlanTouches,
                        onStart: startSession,
                        onManagePlans: { showTouchPlanner = true }
                    )
                    .disabled(viewModel.isLoading)

                    FarmDetailSectionHeader(title: "Farm Plan")
                    FarmPlanCard(touches: planTouches)
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text(error).foregroundColor(.muted).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await viewModel.loadFarmData() } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Farm Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAnalytics = true
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Farm analytics")
            }
        }
        .onChange(of: isAddressesExpanded) { _, expanded in
            if expanded { Task { await viewModel.loadAddresses() } }
        }
        .sheet(isPresented: $showAllAddresses) {
            NavigationStack {
                List {
                    ForEach(viewModel.addresses) { address in Text(address.formatted) }
                    if viewModel.isLoadingAddresses {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if viewModel.addressesLoadFailed {
                        Button("Retry loading addresses") { Task { await viewModel.loadAddresses() } }
                    } else if viewModel.addressesHaveMore {
                        Button("Load more addresses") { Task { await viewModel.loadAddresses() } }
                    }
                }
                .navigationTitle("Addresses")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAllAddresses = false } } }
            }
        }
        .sheet(isPresented: $showAllLeads) {
            NavigationStack {
                List(viewModel.leads.sorted { $0.createdAt > $1.createdAt }) { lead in RecentLeadRow(lead: lead) }
                    .navigationTitle("Farm Leads")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAllLeads = false } } }
            }
        }
        .sheet(isPresented: $showAnalytics) {
            if let farm = viewModel.farm {
                FarmAnalyticsView(farmId: farm.id)
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
            if isAddressesExpanded { await viewModel.loadAddresses(reset: true) }
        }
        .overlay {
            if isStartingTouch {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Starting session...")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("Couldn't Start Session", isPresented: .init(
            get: { touchPreparationError != nil },
            set: { if !$0 { touchPreparationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(touchPreparationError ?? "Couldn't prepare this session.")
        }
    }
}

private struct FarmProgressCard: View {
    let planned: Int
    let completed: Int
    let visits: Int
    let visitsAreMinimum: Bool
    let isLoading: Bool
    let loadFailed: Bool

    private var progress: Double { planned > 0 ? min(Double(completed) / Double(planned), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress").font(.subheading).foregroundColor(.text)
                Spacer()
                if !isLoading && !loadFailed {
                    Text("\(Int((progress * 100).rounded()))% of homes visited")
                        .font(.label).foregroundColor(.text)
                }
            }
            if isLoading {
                ProgressView()
            } else if loadFailed {
                Text("Home visit progress unavailable. Pull down to retry.").font(.flyrCaption).foregroundColor(.muted)
            } else {
                ProgressBar(value: progress)
                Text("\(completed) of \(planned) homes visited")
                    .font(.flyrCaption).foregroundColor(.muted)
            }
        }
        .padding(16).background(Color.bgSecondary).cornerRadius(12)
    }
}

private struct FarmExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int?
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.light()
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: icon).foregroundColor(.accent)
                    Text(title).font(.subheading).foregroundColor(.text)
                    Spacer()
                    if let count { Text("\(count) total").font(.label).foregroundColor(.muted) }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.medium)).foregroundColor(.muted)
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.bgTertiary).cornerRadius(8)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }.background(Color.bgSecondary).cornerRadius(12)
    }
}

private struct FarmHeroStatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.flyrHeadline)
                .foregroundStyle(Color.text)
            Text(label)
                .font(.flyrCaption)
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FarmDetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheading)
            .foregroundStyle(Color.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StartSessionCard: View {
    @Binding var selectedType: FarmTouchType
    @Binding var selectedPlanTouchId: UUID?

    let planTouches: [FarmTouch]
    let onStart: () -> Void
    let onManagePlans: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 124), spacing: 8)
    ]
    private let sessionTypes: [FarmTouchType] = [
        .flyer,
        .doorKnock,
        .event,
        .custom
    ]

    private var selectedPlan: FarmTouch? {
        selectedPlanTouchId.flatMap { id in
            planTouches.first { $0.id == id }
        }
    }

    private var planTitle: String {
        selectedPlan.map { planLabel(for: $0) } ?? "No plan"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Type")
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(Color.muted)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(sessionTypes) { type in
                        Button {
                            selectedType = type
                            selectedPlanTouchId = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: type.iconName)
                                    .font(.flyrCaption.weight(.semibold))
                                Text(type.farmDetailActionName)
                                    .font(.flyrCaption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                            .foregroundStyle(selectedType == type ? .white : Color.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(selectedType == type ? Color.accent : Color.bgTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Plan")
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(Color.muted)

                Menu {
                    Button("No plan") {
                        selectedPlanTouchId = nil
                    }

	                    ForEach(planTouches) { touch in
	                        Button {
	                            selectedPlanTouchId = touch.id
	                            selectedType = touch.type
	                        } label: {
	                            Text(planLabel(for: touch))
	                        }
	                    }
	                } label: {
	                    HStack(spacing: 10) {
	                        Image(systemName: selectedPlan?.effectiveIconName ?? "link")
                            .font(.flyrCaption.weight(.semibold))
                            .foregroundStyle(Color.accent)
                            .frame(width: 30, height: 30)
                            .background(Color.accent.opacity(0.14))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(planTitle)
                                .font(.flyrSubheadline.weight(.semibold))
                                .foregroundStyle(Color.text)
                                .lineLimit(1)
                            Text(selectedPlan == nil ? "Optional" : "Connected to this session")
                                .font(.flyrCaption)
                                .foregroundStyle(Color.muted)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.flyrCaption.weight(.semibold))
                            .foregroundStyle(Color.muted)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 56)
                    .background(Color.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Button(action: onStart) {
                Text("Start Session")
                    .font(.label)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func planLabel(for touch: FarmTouch) -> String {
        "\(touch.displayTitleForFarm) · \(touch.date.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct FarmAreaCard: View {
    let campaignId: UUID?
    let mapCenter: CLLocationCoordinate2D?
    let polygon: [CLLocationCoordinate2D]?
    let isLoading: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedType: FarmTouchType
    let makeExecutionContext: (FarmTouchType) async -> FarmExecutionContext?

    @State private var isMapFullscreen = false
    @Namespace private var mapNamespace

    var body: some View {
        Group {
            if let campaignId {
                ZStack(alignment: .bottomTrailing) {
                    TerritoryPreviewMapView(
                        center: mapCenter,
                        polygon: polygon,
                        useDarkStyle: colorScheme == .dark,
                        height: 260,
                        showsCenterMarker: false
                    )
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .matchedGeometryEffect(id: "map", in: mapNamespace, isSource: !isMapFullscreen)

                    Button {
                        HapticManager.medium()
                        MapOpenTrace.begin(campaign: campaignId.uuidString)
                        isMapFullscreen = true
                    } label: {
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open farm area map")
                    .zIndex(1)

                    Button {
                        HapticManager.medium()
                        MapOpenTrace.begin(campaign: campaignId.uuidString)
                        isMapFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.flyrCaption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Expand farm area map")
                    .zIndex(2)
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .fullScreenCover(isPresented: $isMapFullscreen) {
                    FullscreenMapView(
                        campaignID: campaignId,
                        namespace: mapNamespace,
                        isSource: true,
                        initialCenter: mapCenter,
                        initialFarmSessionType: selectedType,
                        farmSessionStartContextProvider: { type in
                            await makeExecutionContext(type)
                        },
                        onClose: { isMapFullscreen = false }
                    )
                }
            } else if isLoading {
                ProgressView("Loading farm area...")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                FarmAreaUnavailableCard()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FarmAreaUnavailableCard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)

            VStack(spacing: 10) {
                Image(systemName: "map")
                    .font(.flyrTitle2)
                    .foregroundStyle(Color.muted)

                Text("Farm area unavailable")
                    .font(.flyrHeadline)
                    .foregroundStyle(.white)

                Text("Link a campaign to preview the selected area and building footprints.")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FarmPlanCard: View {
    let touches: [FarmTouch]

    var body: some View {
        LazyVStack(spacing: 10) {
            if touches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No saved plan yet")
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)
                    Text("Create touches in the planner or WolfGrid Web and they will appear here from Supabase.")
                        .font(.flyrCaption)
                        .foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            } else {
                ForEach(Array(touches.enumerated()), id: \.element.id) { index, touch in
                    FarmPlanRow(touch: touch, sequenceNumber: index + 1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FarmPlanRow: View {
    let touch: FarmTouch
    let sequenceNumber: Int

    private var timing: String {
        if let cycleNumber = touch.cycleNumber {
            return "Cycle \(cycleNumber)"
        }
        return touch.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var subtitle: String {
        touch.date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timing)
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.muted.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: 84, alignment: .leading)

            Group {
                if touch.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.success)
                } else {
                    Text("\(sequenceNumber)")
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.text)
                }
            }
            .frame(width: 30, height: 30)
            .background(Color.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Image(systemName: touch.effectiveIconName)
                .font(.flyrSubheadline)
                .foregroundStyle(tintColor(for: touch))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(touch.displayTitleForFarm)
                    .font(.flyrSubheadline)
                    .foregroundStyle(Color.text)
                    .lineLimit(2)
                Text(touch.effectiveModeDisplayName)
                    .font(.caption2)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.bgTertiary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tintColor(for touch: FarmTouch) -> Color {
        switch touch.effectiveColorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .gray
        }
    }
}

private struct RecentFarmActivityCard: View {
    let touches: [FarmTouch]
    let leads: [FarmLead]
    let doorsHit: Int

    private var completedTouches: [FarmTouch] {
        touches
            .filter(\.completed)
            .sorted {
                let lhsDate = $0.completedAt ?? $0.date
                let rhsDate = $1.completedAt ?? $1.date
                return lhsDate > rhsDate
            }
    }

    private var recentLeads: [FarmLead] {
        leads.sorted { $0.createdAt > $1.createdAt }
    }

    private var isEmpty: Bool {
        completedTouches.isEmpty && recentLeads.isEmpty && doorsHit == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No activity yet")
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)
                    Text("Start your first touch to begin tracking this farm.")
                        .font(.flyrSubheadline)
                        .foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 10) {
                    FarmHeroStatPill(value: "\(completedTouches.count)", label: "Done")
                    FarmHeroStatPill(value: "\(doorsHit)", label: "Doors hit")
                    FarmHeroStatPill(value: "\(leads.count)", label: "Leads")
                }

                ForEach(completedTouches.prefix(3)) { touch in
                    RecentTouchRow(touch: touch)
                }

                ForEach(recentLeads.prefix(2)) { lead in
                    RecentLeadRow(lead: lead)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct RecentTouchRow: View {
    let touch: FarmTouch

    private var completedDate: Date {
        touch.completedAt ?? touch.date
    }

    private var title: String {
        touch.displayTitleForFarm
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.flyrSubheadline)
                .foregroundStyle(Color.success)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.flyrSubheadline.weight(.semibold))
                    .foregroundStyle(Color.text)
                Text("Completed \(completedDate, style: .date)")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)

                if let notes = touch.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(notes)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RecentLeadRow: View {
    let lead: FarmLead

    private var title: String {
        guard let name = lead.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "New lead"
        }
        return name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.flyrSubheadline)
                .foregroundStyle(Color.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.flyrSubheadline.weight(.semibold))
                    .foregroundStyle(Color.text)
                Text("\(lead.leadSource.displayName) · \(lead.createdAt, style: .date)")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)

                if let phone = lead.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(phone).font(.flyrCaption).foregroundStyle(Color.muted)
                }
                if let email = lead.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(email).font(.flyrCaption).foregroundStyle(Color.muted)
                }
                if let address = lead.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(address)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct TouchRowView: View {
    let touch: FarmTouch

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }

    var body: some View {
        HStack {
            Image(systemName: touch.effectiveIconName)
                .foregroundColor(colorForTouch(touch))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(touch.displayTitleForFarm)
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

    private func colorForTouch(_ touch: FarmTouch) -> Color {
        switch touch.effectiveColorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .flyrPrimary
        case "purple": return .purple
        case "yellow": return .yellow
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .gray
        }
    }
}

private extension FarmTouchType {
    var farmDetailActionName: String {
        switch self {
        case .flyer:
            return "Flyer Run"
        case .doorKnock:
            return "Door Knock"
        case .event:
            return "Community Event"
        case .newsletter:
            return "Homeowner Check-In"
        case .ad:
            return "Social Ad Campaign"
        case .custom:
            return "Pop-By"
        }
    }
}

private extension FarmTouch {
    var isFarmFieldTouch: Bool {
        switch effectiveModeRawValue {
        case "flyer", "door_knock", "door_knocking", "pop_by", "popby":
            return true
        case "event", "community_event":
            return titleContainsPopBy
        case "newsletter", "ad", "social_ad", "phone_call", "call", "survey":
            return false
        default:
            return type == .flyer || type == .doorKnock || type == .custom
        }
    }

    private var titleContainsPopBy: Bool {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("pop by")
            || normalized.contains("pop-by")
            || normalized.contains("popby")
    }

    var displayTitleForFarm: String {
        if effectiveModeRawValue == "pop_by" || effectiveModeRawValue == "popby" || titleContainsPopBy {
            return "Pop-By"
        }
        return effectiveDisplayTitle
    }
}

private func averageCoordinate(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
    let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
    guard !valid.isEmpty else { return nil }
    let latitude = valid.map(\.latitude).reduce(0, +) / Double(valid.count)
    let longitude = valid.map(\.longitude).reduce(0, +) / Double(valid.count)
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

#Preview {
    NavigationStack {
        FarmDetailView(farmId: UUID())
    }
}
