import SwiftUI
/// Leads tab root: Field Leads inbox with search, sync status in header, and compact list.
/// No FUB promotional banner; sync status (Synced ✓ / Sync ✗ / Syncing...) in header row.
struct ContactsHubView: View {
    @StateObject private var leadsViewModel = LeadsViewModel()
    @StateObject private var auth = AuthManager.shared
    @State private var showSyncSettings = false
    @State private var showSessionStart = false
    @State private var integrations: [UserIntegration] = []
    @State private var isSyncing = false

    private var hasConnectedCRM: Bool {
        integrations.contains { $0.isConnected }
    }

    private var connectedIntegration: UserIntegration? {
        integrations.first { $0.isConnected }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBarSection
                    contentSection
                }
            }
            .navigationTitle("Leads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sync Settings") {
                            HapticManager.light()
                            showSyncSettings = true
                        }
                        if hasConnectedCRM, let integration = connectedIntegration {
                            Button("Disconnect", role: .destructive) {
                                Task { await disconnect(provider: integration.provider) }
                            }
                        }
                        Button("Sync Now") {
                            Task {
                                isSyncing = true
                                await loadIntegrations()
                                await leadsViewModel.loadLeads()
                                isSyncing = false
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
            .task {
                await leadsViewModel.loadLeads()
                await loadIntegrations()
            }
            .refreshable {
                await leadsViewModel.loadLeads()
                await loadIntegrations()
                HapticManager.rigid()
            }
            .sheet(isPresented: $showSyncSettings) {
                SyncSettingsView()
            }
            .sheet(isPresented: $showSessionStart) {
                SessionStartView(showCancelButton: true)
            }
            .navigationDestination(item: $leadsViewModel.selectedLead) { lead in
                LeadDetailView(
                    lead: lead,
                    onConnectCRM: { showSyncSettings = true }
                )
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
                        FieldLeadRowView(lead: lead) {
                            leadsViewModel.selectedLead = lead
                        }
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
            Text("No field leads yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            Text("Start a session and tap doors to capture leads automatically")
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 32)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadIntegrations() async {
        guard let userId = auth.user?.id else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            integrations = try await CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
        } catch {}
    }

    private func disconnect(provider: IntegrationProvider) async {
        guard let userId = auth.user?.id else { return }
        do {
            try await CRMIntegrationManager.shared.disconnect(userId: userId, provider: provider)
            await loadIntegrations()
        } catch {}
    }
}

// MARK: - Preview

#Preview {
    ContactsHubView()
}
