import SwiftUI

struct CampaignsListView: View {
    @StateObject private var storeV2 = CampaignV2Store.shared
    @StateObject private var hooksV2 = UseCampaignsV2()
    @State private var recentlyCreatedCampaignID: UUID?
    @State private var campaignFilter: CampaignFilter = .active
    @State private var showSessionStartSheet = false
    @State private var sessionStartCampaign: CampaignV2?
    @State private var searchText = ""
    @State private var campaignActionErrorMessage: String?
    @State private var showCampaignActionError = false
    @State private var isBulkSelecting = false
    @State private var selectedCampaignIDs: Set<UUID> = []
    @State private var showBulkArchiveConfirmation = false
    @State private var showBulkDeleteConfirmation = false
    @State private var pendingDeleteCampaign: CampaignV2?
    var externalFilter: Binding<CampaignFilter>? = nil
    /// When set, empty state and "+ New Campaign" button set this to true (same as toolbar + button).
    var showCreateCampaign: Binding<Bool>? = nil
    var onCreateCampaignTapped: (() -> Void)?
    var onCampaignTapped: ((UUID) -> Void)?

    private var effectiveFilter: CampaignFilter {
        externalFilter?.wrappedValue ?? campaignFilter
    }

    private var allVisibleCampaignIDsSelected: Bool {
        let visibleCampaignIDs = Set(visibleCampaigns.map(\.id))
        return !visibleCampaignIDs.isEmpty && visibleCampaignIDs.isSubset(of: selectedCampaignIDs)
    }

    private var selectedCampaigns: [CampaignV2] {
        storeV2.campaigns.filter { selectedCampaignIDs.contains($0.id) }
    }

    private var selectedArchivableCampaignIDs: Set<UUID> {
        Set(selectedCampaigns.lazy.filter { $0.status != .archived }.map(\.id))
    }

    private var visibleCampaigns: [CampaignV2] {
        let filteredCampaigns: [CampaignV2]
        switch effectiveFilter {
        case .active:
            filteredCampaigns = storeV2.campaigns.filter { $0.status != .completed && $0.status != .archived }
        case .completed:
            filteredCampaigns = storeV2.campaigns.filter { $0.status == .completed }
        case .archived:
            filteredCampaigns = storeV2.campaigns.filter { $0.status == .archived }
        case .all:
            filteredCampaigns = storeV2.campaigns
        }

        let sortedCampaigns = filteredCampaigns.sorted { a, b in
            let aActive = a.status != .completed
            let bActive = b.status != .completed
            if aActive != bActive { return aActive }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        guard !searchText.isEmpty else { return sortedCampaigns }
        let q = searchText.lowercased()
        return sortedCampaigns.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.seedQuery?.localizedCaseInsensitiveContains(q) == true) ||
            $0.addresses.contains { $0.address.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if externalFilter == nil {
                    HStack {
                        Menu {
                            ForEach(CampaignFilter.allCases) { filterOption in
                                Button(filterOption.rawValue) {
                                    HapticManager.light()
                                    campaignFilter = filterOption
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(campaignFilter.rawValue)
                                Image(systemName: "chevron.down")
                                    .font(.flyrCaption)
                            }
                            .font(.flyrSubheadline)
                            .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                }

                if storeV2.campaigns.isEmpty {
                    if hooksV2.isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading campaigns...")
                                .bodyText()
                                .foregroundColor(.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                    } else {
                        CampaignListEmptyView(showCreateCampaign: showCreateCampaign, onCreateTapped: onCreateCampaignTapped)
                    }
                } else {
                    List {
                        V2CampaignsListSection(
                            store: storeV2,
                            recentlyCreatedCampaignID: recentlyCreatedCampaignID,
                            filter: effectiveFilter,
                            searchText: searchText,
                            isSelectionMode: isBulkSelecting,
                            selectedCampaignIDs: selectedCampaignIDs,
                            onCampaignTapped: onCampaignTapped,
                            onCampaignSelected: { campaign in
                                handleCampaignTap(campaign)
                            },
                            onStartSelection: { campaign in
                                startBulkSelection(with: campaign)
                            },
                            onPlayTapped: { campaign in
                                HapticManager.light()
                                sessionStartCampaign = campaign
                                showSessionStartSheet = true
                            },
                            onDeleteRequested: { campaign in
                                pendingDeleteCampaign = campaign
                            },
                            onArchiveFailed: { message in
                                campaignActionErrorMessage = message
                                showCampaignActionError = true
                            },
                            onArchiveSucceeded: {
                                if externalFilter != nil {
                                    externalFilter?.wrappedValue = .archived
                                } else {
                                    campaignFilter = .archived
                                }
                            }
                        )
                        CampaignListEmptyFilteredSection(
                            store: storeV2,
                            filter: effectiveFilter,
                            searchText: searchText
                        )
                        if showCreateCampaign != nil || onCreateCampaignTapped != nil {
                            Section {
                                Button(action: {
                                    HapticManager.light()
                                    if let onCreateCampaignTapped {
                                        onCreateCampaignTapped()
                                    } else if let showCreateCampaign = showCreateCampaign {
                                        showCreateCampaign.wrappedValue = true
                                    }
                                }) {
                                    HStack {
                                        Spacer()
                                        Text("+ New Campaign")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundColor(.red)
                                        Spacer()
                                    }
                                    .padding(.vertical, 14)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.bgSecondary)
                    .searchable(text: $searchText, prompt: "Search campaigns")
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: effectiveFilter)
            .navigationTitle(isBulkSelecting ? "\(selectedCampaignIDs.count) Selected" : "Campaigns")
            .toolbar {
                if isBulkSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            exitBulkSelection()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allVisibleCampaignIDsSelected ? "Deselect All" : "Select All") {
                            toggleSelectAllVisible()
                        }
                        .disabled(visibleCampaigns.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showBulkArchiveConfirmation = true
                        } label: {
                            Image(systemName: "archivebox")
                        }
                        .disabled(selectedArchivableCampaignIDs.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showBulkDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedCampaignIDs.isEmpty)
                    }
                }
            }
            .onChange(of: storeV2.campaigns.count) { oldCount, newCount in
                if newCount > oldCount, let newCampaign = storeV2.campaigns.last {
                    recentlyCreatedCampaignID = newCampaign.id
                }
            }
            .onChange(of: recentlyCreatedCampaignID) { oldID, newID in
                if let newID = newID {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            recentlyCreatedCampaignID = nil
                        }
                    }
                }
            }
            .task(id: "campaigns") {
                hooksV2.load(store: storeV2)
            }
            .refreshable {
                hooksV2.load(store: storeV2)
                HapticManager.rigid()
            }
            .sheet(isPresented: $showSessionStartSheet) {
                SessionStartView(preselectedCampaign: sessionStartCampaign)
            }
            .alert("Campaign action failed", isPresented: $showCampaignActionError) {
                Button("OK") {
                    showCampaignActionError = false
                    campaignActionErrorMessage = nil
                }
            } message: {
                if let message = campaignActionErrorMessage {
                    Text(message)
                }
            }
            .alert("Delete campaign?", isPresented: Binding(
                get: { pendingDeleteCampaign != nil },
                set: { if !$0 { pendingDeleteCampaign = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    guard let campaign = pendingDeleteCampaign else { return }
                    Task {
                        await deleteCampaign(campaign)
                        pendingDeleteCampaign = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteCampaign = nil
                }
            } message: {
                Text("This will permanently delete \(pendingDeleteCampaign?.name ?? "this campaign").")
            }
            .alert("Archive selected campaigns?", isPresented: $showBulkArchiveConfirmation) {
                Button("Archive") {
                    Task { await archiveSelectedCampaigns() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will move \(selectedArchivableCampaignIDs.count) campaign\(selectedArchivableCampaignIDs.count == 1 ? "" : "s") to archived.")
            }
            .alert("Delete selected campaigns?", isPresented: $showBulkDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task { await deleteSelectedCampaigns() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \(selectedCampaignIDs.count) campaign\(selectedCampaignIDs.count == 1 ? "" : "s").")
            }
        }
    }

    private func handleCampaignTap(_ campaign: CampaignV2) {
        if isBulkSelecting {
            toggleCampaignSelection(campaign)
        } else {
            HapticManager.light()
            onCampaignTapped?(campaign.id)
        }
    }

    private func startBulkSelection(with campaign: CampaignV2) {
        isBulkSelecting = true
        selectedCampaignIDs.insert(campaign.id)
        HapticManager.light()
    }

    private func exitBulkSelection() {
        isBulkSelecting = false
        selectedCampaignIDs.removeAll()
    }

    private func toggleCampaignSelection(_ campaign: CampaignV2) {
        if selectedCampaignIDs.contains(campaign.id) {
            selectedCampaignIDs.remove(campaign.id)
            if selectedCampaignIDs.isEmpty {
                isBulkSelecting = false
            }
        } else {
            selectedCampaignIDs.insert(campaign.id)
        }
    }

    private func toggleSelectAllVisible() {
        let visibleCampaignIDs = Set(visibleCampaigns.map(\.id))
        guard !visibleCampaignIDs.isEmpty else { return }

        if visibleCampaignIDs.isSubset(of: selectedCampaignIDs) {
            selectedCampaignIDs.subtract(visibleCampaignIDs)
            if selectedCampaignIDs.isEmpty {
                isBulkSelecting = false
            }
        } else {
            isBulkSelecting = true
            selectedCampaignIDs.formUnion(visibleCampaignIDs)
        }
    }

    private func deleteCampaign(_ campaign: CampaignV2) async {
        do {
            try await CampaignsAPI.shared.deleteCampaign(campaignId: campaign.id)
            storeV2.remove(id: campaign.id)
        } catch {
            await MainActor.run {
                campaignActionErrorMessage = error.localizedDescription
                showCampaignActionError = true
            }
        }
    }

    private func archiveSelectedCampaigns() async {
        let idsToArchive = selectedArchivableCampaignIDs
        guard !idsToArchive.isEmpty else { return }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for campaignID in idsToArchive {
                    group.addTask {
                        try await CampaignsAPI.shared.updateCampaignStatus(campaignId: campaignID, status: .archived)
                    }
                }
                try await group.waitForAll()
            }
            await MainActor.run {
                storeV2.setStatus(ids: idsToArchive, status: .archived)
                exitBulkSelection()
                if externalFilter != nil {
                    externalFilter?.wrappedValue = .archived
                } else {
                    campaignFilter = .archived
                }
            }
        } catch {
            await MainActor.run {
                campaignActionErrorMessage = error.localizedDescription
                showCampaignActionError = true
            }
        }
    }

    private func deleteSelectedCampaigns() async {
        let idsToDelete = selectedCampaignIDs
        guard !idsToDelete.isEmpty else { return }

        do {
            try await CampaignsAPI.shared.deleteCampaigns(campaignIDs: Array(idsToDelete))
            storeV2.remove(ids: idsToDelete)
            exitBulkSelection()
        } catch {
            await MainActor.run {
                campaignActionErrorMessage = error.localizedDescription
                showCampaignActionError = true
            }
        }
    }
}

// MARK: - V1 Campaigns List Section

struct V1CampaignsListSection: View {
    let hooks: CampaignsHooks
    var searchText: String = ""

    private var filteredLegacy: [Campaign] {
        guard !searchText.isEmpty else { return hooks.campaigns }
        let q = searchText.lowercased()
        return hooks.campaigns.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            ($0.region?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    var body: some View {
        if !hooks.campaigns.isEmpty && !filteredLegacy.isEmpty {
            Section {
                ForEach(filteredLegacy, id: \.id) { campaign in
                    NavigationLink(destination: OldCampaignDetailView(campaign: campaign)) {
                        LegacyCampaignRow(campaign: campaign)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .simultaneousGesture(TapGesture().onEnded { HapticManager.light() })
                }
            }
        }
    }
}

// MARK: - Campaign Filter

enum CampaignFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case archived = "Archived"

    var id: String { rawValue }
}

// MARK: - V2 Campaigns List Section

struct V2CampaignsListSection: View {
    let store: CampaignV2Store
    let recentlyCreatedCampaignID: UUID?
    let filter: CampaignFilter
    var searchText: String = ""
    var isSelectionMode = false
    var selectedCampaignIDs: Set<UUID> = []
    var onCampaignTapped: ((UUID) -> Void)?
    var onCampaignSelected: ((CampaignV2) -> Void)?
    var onStartSelection: ((CampaignV2) -> Void)?
    var onPlayTapped: ((CampaignV2) -> Void)?
    var onDeleteRequested: ((CampaignV2) -> Void)?
    var onArchiveFailed: ((String) -> Void)?
    var onArchiveSucceeded: (() -> Void)?

    private var filteredCampaigns: [CampaignV2] {
        switch filter {
        case .active:
            return store.campaigns.filter { $0.status != .completed && $0.status != .archived }
        case .completed:
            return store.campaigns.filter { $0.status == .completed }
        case .archived:
            return store.campaigns.filter { $0.status == .archived }
        case .all:
            return store.campaigns
        }
    }

    private var sortedCampaigns: [CampaignV2] {
        filteredCampaigns.sorted { a, b in
            let aActive = a.status != .completed
            let bActive = b.status != .completed
            if aActive != bActive { return aActive }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var searchFilteredCampaigns: [CampaignV2] {
        guard !searchText.isEmpty else { return sortedCampaigns }
        let q = searchText.lowercased()
        return sortedCampaigns.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.seedQuery?.localizedCaseInsensitiveContains(q) == true) ||
            $0.addresses.contains { $0.address.localizedCaseInsensitiveContains(q) }
        }
    }

    private func displayName(for campaign: CampaignV2) -> String? {
        let sameName = filteredCampaigns.filter { $0.name == campaign.name }
        if sameName.count <= 1 { return nil }
        let loc = campaign.seedQuery ?? campaign.addresses.first?.address ?? ""
        if loc.isEmpty { return nil }
        return "\(campaign.name) - \(loc)"
    }

    private func archiveCampaign(_ campaign: CampaignV2) {
        guard campaign.status != .archived else { return }
        HapticManager.light()
        Task {
            do {
                try await CampaignsAPI.shared.updateCampaignStatus(campaignId: campaign.id, status: .archived)
                await MainActor.run {
                    store.setStatus(id: campaign.id, status: .archived)
                    onArchiveSucceeded?()
                }
            } catch {
                await MainActor.run {
                    print("❌ [Campaigns] Archive failed: \(error)")
                    onArchiveFailed?(error.localizedDescription)
                }
            }
        }
    }

    var body: some View {
        if !store.campaigns.isEmpty && !searchFilteredCampaigns.isEmpty {
            Section {
                ForEach(searchFilteredCampaigns, id: \.id) { campaign in
                    Button {
                        onCampaignSelected?(campaign)
                    } label: {
                        HStack(spacing: 0) {
                            CampaignRowView(
                                campaign: campaign,
                                displayName: displayName(for: campaign),
                                onPlayTapped: !isSelectionMode && campaign.status != .completed ? { onPlayTapped?(campaign) } : nil,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedCampaignIDs.contains(campaign.id)
                            )
                            if !isSelectionMode {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                        }
                        .background(
                            campaign.id == recentlyCreatedCampaignID
                                ? Color.red.opacity(0.15)
                                : Color.clear
                        )
                        .animation(.easeInOut(duration: 0.3), value: recentlyCreatedCampaignID)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isSelectionMode {
                            Button(role: .destructive) {
                                onDeleteRequested?(campaign)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                archiveCampaign(campaign)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(Color(.systemGray))
                        }
                    }
                    .contextMenu {
                        if !isSelectionMode {
                            Button {
                                onStartSelection?(campaign)
                            } label: {
                                Label("Select Multiple", systemImage: "checklist")
                            }
                        }
                        Button {
                            archiveCampaign(campaign)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Divider()
                        Button(role: .destructive) {
                            onDeleteRequested?(campaign)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .id(campaign.id)
                }
            }
        }
    }
}

// MARK: - Empty filtered section (when filter or search yields no campaigns)

struct CampaignListEmptyFilteredSection: View {
    let store: CampaignV2Store
    let filter: CampaignFilter
    var searchText: String = ""

    private var filteredCampaigns: [CampaignV2] {
        switch filter {
        case .active: return store.campaigns.filter { $0.status != .completed && $0.status != .archived }
        case .completed: return store.campaigns.filter { $0.status == .completed }
        case .archived: return store.campaigns.filter { $0.status == .archived }
        case .all: return store.campaigns
        }
    }

    private var afterSearchCount: Int {
        guard !searchText.isEmpty else { return filteredCampaigns.count }
        let q = searchText.lowercased()
        return filteredCampaigns.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.seedQuery?.localizedCaseInsensitiveContains(q) == true) ||
            $0.addresses.contains { $0.address.localizedCaseInsensitiveContains(q) }
        }.count
    }

    var body: some View {
        if !store.campaigns.isEmpty && afterSearchCount == 0 {
            Section {
                Text(searchText.isEmpty
                    ? "No \(filter.rawValue.lowercased()) campaigns"
                    : "No results for \"\(searchText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 40)
            }
        }
    }
}

// MARK: - Campaign List Empty View (no campaigns at all)

struct CampaignListEmptyView: View {
    @StateObject private var storeV2 = CampaignV2Store.shared
    @State private var showLocalCreateCampaign = false
    var showCreateCampaign: Binding<Bool>? = nil
    var onCreateTapped: (() -> Void)?

    private var canCreate: Bool { true }

    private func triggerCreateCampaign() {
        HapticManager.light()
        if let onCreateTapped {
            onCreateTapped()
        } else if let showCreateCampaign = showCreateCampaign {
            showCreateCampaign.wrappedValue = true
        } else {
            // Fallback path so empty-state create always works even if parent forgot to pass bindings.
            showLocalCreateCampaign = true
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.secondary)
                .opacity(0.6)
            VStack(spacing: 12) {
                Text("No campaigns yet")
                    .font(.flyrHeadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text("Create your first campaign to start tracking doors")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if canCreate {
                Button(action: triggerCreateCampaign) {
                    Text("+ Create Campaign")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $showLocalCreateCampaign) {
            NavigationStack {
                NewCampaignScreen(store: storeV2)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showLocalCreateCampaign = false
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Legacy Campaign Row (grey box, matches Start Session / CampaignRowView)

struct LegacyCampaignRow: View {
    let campaign: Campaign

    private var titleText: String {
        if let region = campaign.region, !region.isEmpty {
            return "\(campaign.title) - \(region)"
        }
        return campaign.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.flyrHeadline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Label("\(campaign.totalFlyers)", systemImage: "house.fill")
                .font(.flyrCaption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        CampaignsListView()
    }
}
