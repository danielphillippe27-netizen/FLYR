import SwiftUI

struct SessionStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementsService: EntitlementsService

    /// When false, Cancel button is hidden (e.g. when used as Record tab root).
    var showCancelButton: Bool = true

    /// When set (e.g. from campaigns list play button), open this campaign map on appear.
    var preselectedCampaign: CampaignV2?

    // Data loading
    @State private var campaigns: [CampaignV2] = []
    @State private var isLoadingData: Bool = false
    @State private var isFetchingData: Bool = false
    @State private var lastFetchTime: Date?

    /// Show at most this many items before "More" menu
    private let maxVisibleItems = 3

    /// Campaign chosen to open directly in map.
    @State private var mapCampaign: CampaignV2?
    @State private var showCampaignMap: Bool = false
    @State private var showQuickCampaign: Bool = false
    @State private var showPaywall: Bool = false

    var body: some View {
        NavigationStack {
            sessionStartContent
        }
    }

    private var sessionStartContent: some View {
        scrollContent
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { sessionToolbar }
            .task(id: "sessionStartData") {
                await loadData()
                if let pre = preselectedCampaign {
                    let campaign = campaigns.first { $0.id == pre.id } ?? pre
                    openCampaign(campaign)
                }
            }
            .navigationDestination(isPresented: $showCampaignMap) {
                campaignMapDestination
            }
            .navigationDestination(isPresented: $showQuickCampaign) {
                QuickStartMapView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                quickCampaignButton
                campaignList
                Spacer()
            }
            .padding(.vertical)
        }
    }

    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        if showCancelButton {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    HapticManager.light()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var campaignMapDestination: some View {
        if let campaign = mapCampaign {
            CampaignMapView(campaignId: campaign.id.uuidString)
        }
    }

    // MARK: - Campaign List

    private var quickCampaignButton: some View {
        Button {
            HapticManager.light()
            if entitlementsService.canUsePro {
                showQuickCampaign = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.flyrHeadline)
                    .foregroundColor(.black)
                Text("Quick Campaign")
                    .font(.flyrHeadline)
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.flyrCaption)
                    .foregroundColor(.black.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.yellow)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var campaignList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAMPAIGNS")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)

            if isLoadingData {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if campaigns.isEmpty {
                Text("No campaigns available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let visible = Array(campaigns.prefix(maxVisibleItems))
                let remaining = Array(campaigns.dropFirst(maxVisibleItems))

                ForEach(visible) { campaign in
                    Button {
                        openCampaign(campaign)
                    } label: {
                        campaignRow(campaign)
                    }
                    .buttonStyle(.plain)
                }

                if !remaining.isEmpty {
                    Menu {
                        ForEach(remaining) { campaign in
                            Button(campaign.name) {
                                openCampaign(campaign)
                            }
                        }
                    } label: {
                        HStack {
                            Text("More (\(remaining.count) more)")
                                .font(.flyrHeadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.flyrCaption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private func campaignRow(_ campaign: CampaignV2) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(campaign.name)
                    .font(.flyrHeadline)

                HStack(spacing: 12) {
                    Label("\(campaign.totalFlyers)", systemImage: "house.fill")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)

                    if campaign.status != .draft {
                        Text(campaign.status.rawValue.capitalized)
                            .font(.flyrCaption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor(campaign.status).opacity(0.2))
                            .foregroundColor(statusColor(campaign.status))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.flyrCaption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Helpers

    private func openCampaign(_ campaign: CampaignV2) {
        HapticManager.light()
        mapCampaign = campaign
        showCampaignMap = true
    }

    private func statusColor(_ status: CampaignStatus) -> Color {
        switch status {
        case .draft: return .blue
        case .active: return .green
        case .completed: return .gray
        case .paused: return .flyrPrimary
        case .archived: return .gray
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard !isFetchingData else { return }
        if let last = lastFetchTime, Date().timeIntervalSince(last) < 3 { return }
        isFetchingData = true
        lastFetchTime = Date()
        isLoadingData = true
        defer {
            isFetchingData = false
            isLoadingData = false
        }

        await loadCampaigns()
    }

    private func loadCampaigns() async {
        do {
            campaigns = try await CampaignsAPI.shared.fetchCampaignsV2(workspaceId: WorkspaceContext.shared.workspaceId)
            print("✅ Loaded \(campaigns.count) campaigns")
        } catch {
            // CRITICAL: Don't treat cancellation as failure - prevents infinite retry loop
            if (error as NSError).code == NSURLErrorCancelled {
                print("Fetch cancelled (view disposed) - not retrying")
                return
            }
            print("❌ Failed to load campaigns: \(error)")
            campaigns = []
        }
    }

}
