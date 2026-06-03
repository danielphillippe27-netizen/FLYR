import SwiftUI
/// Leads tab root: Field Leads inbox with search, sync status in header, and compact list.
/// No FUB promotional banner; sync status (Synced ✓ / Sync ✗ / Syncing...) in header row.
struct ContactsHubView: View {
    @StateObject private var leadsViewModel = LeadsViewModel()
    @StateObject private var campaignStore = CampaignV2Store.shared
    @StateObject private var auth = AuthManager.shared
    @EnvironmentObject var entitlementsService: EntitlementsService
    @State private var showSyncSettings = false
    @State private var showPaywall = false
    @State private var showSessionStart = false
    @State private var integrations: [UserIntegration] = []
    @State private var isSyncing = false
    @State private var isBulkSelecting = false
    @State private var selectedLeadIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirmation = false
    @State private var pendingDeleteLead: FieldLead?
    @State private var isLoadingCampaignFilters = false

    private var hasConnectedCRM: Bool {
        integrations.contains { $0.isConnected }
    }

    private var connectedIntegration: UserIntegration? {
        integrations.first { $0.isConnected }
    }

    private var allVisibleLeadIDsSelected: Bool {
        let visibleLeadIDs = Set(leadsViewModel.filteredLeads.map(\.id))
        return !visibleLeadIDs.isEmpty && visibleLeadIDs.isSubset(of: selectedLeadIDs)
    }

    private var campaignFilterOptions: [LeadCampaignFilterOption] {
        let counts = Dictionary(grouping: leadsViewModel.leads.compactMap(\.campaignId), by: { $0 })
            .mapValues(\.count)
        let campaignsById = Dictionary(uniqueKeysWithValues: campaignStore.campaigns.map { ($0.id, $0.name) })
        let ids = counts.isEmpty
            ? campaignStore.campaigns.map(\.id)
            : Array(counts.keys)

        return ids.map { id in
            LeadCampaignFilterOption(
                id: id,
                name: campaignsById[id] ?? "Campaign \(id.uuidString.prefix(8))",
                leadCount: counts[id]
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterSection
                    searchBarSection
                    if leadsViewModel.selectedFilter == .campaigns {
                        campaignFilterSection
                    }
                    contentSection
                }
            }
            .navigationTitle(isBulkSelecting ? "\(selectedLeadIDs.count) Selected" : "Leads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isBulkSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            exitBulkSelection()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allVisibleLeadIDsSelected ? "Deselect All" : "Select All") {
                            toggleSelectAllVisible()
                        }
                        .disabled(leadsViewModel.filteredLeads.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showBulkDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedLeadIDs.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Sync Settings") {
                                HapticManager.light()
                                if entitlementsService.canUsePro {
                                    showSyncSettings = true
                                } else {
                                    showPaywall = true
                                }
                            }
                            if hasConnectedCRM, let integration = connectedIntegration {
                                Button("Disconnect", role: .destructive) {
                                    Task { await disconnect(provider: integration.provider) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(syncStatusText)
                                    .font(.system(size: 17, weight: .regular))
                                syncStatusIcon
                            }
                            .foregroundColor(syncStatusColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .task {
                await leadsViewModel.loadLeads()
                await loadIntegrations()
                await loadCampaignFilters()
            }
            .refreshable {
                await leadsViewModel.loadLeads()
                await loadIntegrations()
                await loadCampaignFilters(force: true)
                HapticManager.rigid()
            }
            .onReceive(NotificationCenter.default.publisher(for: .leadSavedFromSession)) { _ in
                Task { await leadsViewModel.loadLeads() }
            }
            .sheet(isPresented: $showSyncSettings) {
                SyncSettingsView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showSessionStart) {
                SessionStartView(showCancelButton: true)
            }
            .navigationDestination(item: $leadsViewModel.selectedLead) { lead in
                LeadDetailView(
                    lead: lead,
                    onConnectCRM: {
                        if entitlementsService.canUsePro {
                            showSyncSettings = true
                        } else {
                            showPaywall = true
                        }
                    },
                    onLeadUpdated: { updated in
                        Task { await leadsViewModel.updateLead(updated) }
                    }
                )
            }
            .alert("Delete lead?", isPresented: Binding(
                get: { pendingDeleteLead != nil },
                set: { if !$0 { pendingDeleteLead = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    guard let lead = pendingDeleteLead else { return }
                    Task {
                        await leadsViewModel.deleteLead(lead)
                        pendingDeleteLead = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteLead = nil
                }
            } message: {
                Text("This will permanently delete \(pendingDeleteLead?.displayNameOrUnknown ?? "this lead").")
            }
            .alert("Delete selected leads?", isPresented: $showBulkDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task { await deleteSelectedLeads() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \(selectedLeadIDs.count) lead\(selectedLeadIDs.count == 1 ? "" : "s").")
            }
            .alert("Error", isPresented: Binding(
                get: { leadsViewModel.errorMessage != nil },
                set: { if !$0 { leadsViewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(leadsViewModel.errorMessage ?? "Something went wrong.")
            }
        }
    }

    private var syncStatusText: String {
        if isSyncing { return "Syncing..." }
        if hasConnectedCRM { return "Synced" }
        return "Sync"
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        if isSyncing {
            ProgressView()
                .scaleEffect(0.9)
        } else if hasConnectedCRM {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
        } else {
            Image(systemName: "xmark.circle")
                .font(.system(size: 17))
        }
    }

    private var syncStatusColor: Color {
        if isSyncing { return .gray }
        if hasConnectedCRM { return Color(red: 52/255, green: 199/255, blue: 89/255) } // #34C759
        return .red
    }

    private var searchBarSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.muted)
                .font(.system(size: 16))
            TextField("Search field leads...", text: $leadsViewModel.searchText)
                .font(.system(size: 15))
                .foregroundColor(.text)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LeadInboxFilter.allCases) { filter in
                    LeadFilterPill(
                        title: filter.title,
                        isSelected: leadsViewModel.selectedFilter == filter
                    ) {
                        if isBulkSelecting { exitBulkSelection() }
                        leadsViewModel.selectFilter(filter)
                        HapticManager.light()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var campaignFilterSection: some View {
        if campaignFilterOptions.isEmpty, isLoadingCampaignFilters {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading campaigns")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        } else if !campaignFilterOptions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(campaignFilterOptions) { campaign in
                        LeadFilterPill(
                            title: campaign.name,
                            count: campaign.leadCount,
                            isSelected: leadsViewModel.selectedCampaignId == campaign.id
                        ) {
                            if isBulkSelecting { exitBulkSelection() }
                            leadsViewModel.selectCampaign(campaign.id)
                            HapticManager.light()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if leadsViewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if leadsViewModel.filteredLeads.isEmpty {
            leadsEmptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(leadsViewModel.filteredLeads) { lead in
                        FieldLeadRowView(
                            lead: lead,
                            isSelectionMode: isBulkSelecting,
                            isSelected: selectedLeadIDs.contains(lead.id),
                            onTap: {
                                handleLeadTap(lead)
                            },
                            onEnterSelectionMode: {
                                startBulkSelection(with: lead)
                            },
                            onDelete: {
                                pendingDeleteLead = lead
                            }
                        )
                        Divider()
                            .padding(.leading, 56)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var leadsEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text(emptyStateTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            Text(emptyStateMessage)
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 32)
            if !isFilteringLeads {
                Button("Start Session →") {
                    showSessionStart = true
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: 280)
                .frame(height: 50)
                .background(Color.accent)
                .cornerRadius(12)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isFilteringLeads: Bool {
        leadsViewModel.selectedFilter != .all ||
            !leadsViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateTitle: String {
        if !leadsViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching leads"
        }

        switch leadsViewModel.selectedFilter {
        case .all:
            return "No field leads yet"
        case .campaigns:
            return leadsViewModel.selectedCampaignId == nil ? "No campaign leads yet" : "No leads in this campaign"
        }
    }

    private var emptyStateMessage: String {
        if !leadsViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different name, address, phone, or note."
        }

        switch leadsViewModel.selectedFilter {
        case .all:
            return "Start a session and tap doors to capture leads automatically"
        case .campaigns:
            return "Leads connected to campaigns will appear here."
        }
    }

    private func loadIntegrations() async {
        guard let userId = auth.user?.id else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            integrations = try await CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
        } catch {}
    }

    private func loadCampaignFilters(force: Bool = false) async {
        if !force, campaignStore.hasFreshData(maxAge: 60) { return }
        isLoadingCampaignFilters = true
        defer { isLoadingCampaignFilters = false }
        do {
            let campaigns = try await CampaignsAPI.shared.fetchCampaignsV2(workspaceId: WorkspaceContext.shared.workspaceId)
            campaignStore.set(campaigns)
        } catch {
            if (error as NSError).code != NSURLErrorCancelled {
                print("⚠️ [ContactsHubView] Failed to load campaign filters: \(error.localizedDescription)")
            }
        }
    }

    private func disconnect(provider: IntegrationProvider) async {
        guard let userId = auth.user?.id else { return }
        do {
            try await CRMIntegrationManager.shared.disconnect(userId: userId, provider: provider)
            await loadIntegrations()
        } catch {}
    }

    private func handleLeadTap(_ lead: FieldLead) {
        if isBulkSelecting {
            toggleLeadSelection(lead)
        } else {
            leadsViewModel.selectedLead = lead
        }
    }

    private func startBulkSelection(with lead: FieldLead) {
        isBulkSelecting = true
        selectedLeadIDs.insert(lead.id)
        HapticManager.light()
    }

    private func exitBulkSelection() {
        isBulkSelecting = false
        selectedLeadIDs.removeAll()
    }

    private func toggleLeadSelection(_ lead: FieldLead) {
        if selectedLeadIDs.contains(lead.id) {
            selectedLeadIDs.remove(lead.id)
            if selectedLeadIDs.isEmpty {
                isBulkSelecting = false
            }
        } else {
            selectedLeadIDs.insert(lead.id)
        }
    }

    private func toggleSelectAllVisible() {
        let visibleLeadIDs = Set(leadsViewModel.filteredLeads.map(\.id))
        guard !visibleLeadIDs.isEmpty else { return }

        if visibleLeadIDs.isSubset(of: selectedLeadIDs) {
            selectedLeadIDs.subtract(visibleLeadIDs)
            if selectedLeadIDs.isEmpty {
                isBulkSelecting = false
            }
        } else {
            isBulkSelecting = true
            selectedLeadIDs.formUnion(visibleLeadIDs)
        }
    }

    private func deleteSelectedLeads() async {
        let leadsToDelete = leadsViewModel.leads.filter { selectedLeadIDs.contains($0.id) }
        await leadsViewModel.deleteLeads(leadsToDelete)
        if leadsViewModel.errorMessage == nil {
            exitBulkSelection()
        }
    }
}

// MARK: - Preview

#Preview {
    ContactsHubView()
}

private struct LeadCampaignFilterOption: Identifiable {
    let id: UUID
    let name: String
    let leadCount: Int?
}

private struct LeadFilterPill: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.82) : .muted)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isSelected ? .white : .text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? Color.accent : Color.gray.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0) leads" } ?? title)
    }
}
