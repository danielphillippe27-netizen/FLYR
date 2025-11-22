import SwiftUI

struct CampaignsListView: View {
    @StateObject private var hooks = CampaignsHooks()
    @StateObject private var storeV2 = CampaignV2Store.shared
    @StateObject private var hooksV2 = UseCampaignsV2()
    @State private var recentlyCreatedCampaignID: UUID?
    @State private var campaignFilter: CampaignFilter = .active

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Segmented control - full width
                    Picker("Filter", selection: $campaignFilter) {
                        ForEach(CampaignFilter.allCases) { filterOption in
                            Text(filterOption.rawValue).tag(filterOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    V1CampaignsSection(hooks: hooks)
                    V2CampaignsSection(
                        store: storeV2,
                        recentlyCreatedCampaignID: recentlyCreatedCampaignID,
                        filter: campaignFilter
                    )
                    CampaignEmptyStateSection(hooks: hooks, store: storeV2, filter: campaignFilter)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.bgSecondary)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: campaignFilter)
            .onChange(of: storeV2.campaigns.count) { oldCount, newCount in
                // Detect new campaign added
                if newCount > oldCount, let newCampaign = storeV2.campaigns.last {
                    recentlyCreatedCampaignID = newCampaign.id
                }
            }
            .onChange(of: recentlyCreatedCampaignID) { oldID, newID in
                if let newID = newID {
                    // Scroll to the newly created campaign
                    withAnimation(.easeInOut(duration: 0.6)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    
                    // Clear highlight after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await MainActor.run {
                            recentlyCreatedCampaignID = nil
                        }
                    }
                }
            }
            .task { 
                await hooks.loadCampaigns()
                hooksV2.load(store: storeV2)
            }
        }
    }
}

// MARK: - V1 Campaigns Section

struct V1CampaignsSection: View {
    let hooks: CampaignsHooks
    
    var body: some View {
        if !hooks.campaigns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Legacy Campaigns")
                    .font(.subheading)
                    .foregroundColor(.text)
                
                ForEach(Array(hooks.campaigns.enumerated()), id: \.element.id) { index, campaign in
                    NavigationLink(destination: OldCampaignDetailView(campaign: campaign)) {
                        CampaignCard(campaign: campaign)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .staggeredAnimation(delay: Double(index) * Animation.staggerDelay)
                }
            }
        }
    }
}

// MARK: - Campaign Filter

enum CampaignFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case completed = "Completed"
    
    var id: String { rawValue }
}

// MARK: - V2 Campaigns Section

struct V2CampaignsSection: View {
    let store: CampaignV2Store
    let recentlyCreatedCampaignID: UUID?
    let filter: CampaignFilter
    
    var filteredCampaigns: [CampaignV2] {
        switch filter {
        case .active:
            // Active = campaigns in progress (not completed)
            return store.campaigns.filter { $0.status != .completed }
        case .completed:
            // Completed = campaigns with completed status
            return store.campaigns.filter { $0.status == .completed }
        }
    }
    
    var body: some View {
        if !store.campaigns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !filteredCampaigns.isEmpty {
                    ForEach(Array(filteredCampaigns.enumerated()), id: \.element.id) { index, campaign in
                        NavigationLink(destination: NewCampaignDetailView(campaignID: campaign.id, store: store)) {
                            CampaignRowView(campaign: campaign)
                                .background(
                                    campaign.id == recentlyCreatedCampaignID ?
                                        Color.red.opacity(0.15) : Color.clear
                                )
                                .animation(.easeInOut(duration: 0.3), value: recentlyCreatedCampaignID)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .staggeredAnimation(delay: Double(index) * Animation.staggerDelay)
                        .id(campaign.id) // Required for ScrollViewReader
                    }
                }
            }
        }
    }
}

// MARK: - Empty State Section

struct CampaignEmptyStateSection: View {
    let hooks: CampaignsHooks
    let store: CampaignV2Store
    let filter: CampaignFilter
    
    var filteredCampaigns: [CampaignV2] {
        switch filter {
        case .active:
            return store.campaigns.filter { $0.status != .completed }
        case .completed:
            return store.campaigns.filter { $0.status == .completed }
        }
    }
    
    var body: some View {
        if hooks.campaigns.isEmpty && store.campaigns.isEmpty {
            if hooks.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading campaigns...")
                        .bodyText()
                        .foregroundColor(.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                EmptyState.noCampaigns
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
            }
        } else if !store.campaigns.isEmpty && filteredCampaigns.isEmpty {
            // Show empty state when there are campaigns but none match the filter
            VStack(spacing: 8) {
                Text("No \(filter.rawValue.lowercased()) campaigns")
                    .font(.body)
                    .foregroundColor(.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - Campaign Card

struct CampaignCard: View {
    let campaign: Campaign
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
    
    private var progress: Double {
        guard campaign.totalFlyers > 0 else { return 0.0 }
        return Double(campaign.scans) / Double(campaign.totalFlyers)
    }
    
    private var progressPercentage: Int {
        Int(progress * 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Title and Badge
            HStack {
                Text(campaign.title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                
                Spacer()
                
                Badge(text: "Legacy")
            }
            
            // Created date
            Text("Created \(campaign.createdAt, formatter: dateFormatter)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Progress section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    
                    Text("\(progressPercentage)%")
                        .font(.subheadline)
                        .foregroundColor(.text)
                }
                
                ProgressView(value: progress)
                    .tint(.red)
            }
            
            // Stats row
            HStack {
                Label("\(campaign.totalFlyers) flyers", systemImage: "paperplane")
                    .font(.subheadline)
                    .foregroundColor(.text)
                
                Spacer()
                
                if let region = campaign.region {
                    Text(region)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(campaign.scans) scans")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .shadow(
            color: Color.black.opacity(0.5),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}

#Preview {
    NavigationStack {
        CampaignsListView()
    }
}
