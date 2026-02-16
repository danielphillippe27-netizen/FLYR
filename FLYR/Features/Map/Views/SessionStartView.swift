import SwiftUI
import CoreLocation
struct SessionStartView: View {
    @Environment(\.dismiss) private var dismiss

    /// When false, Cancel button is hidden (e.g. when used as Record tab root).
    var showCancelButton: Bool = true

    /// When set (e.g. from campaigns list play button), preselect this campaign on appear.
    var preselectedCampaign: CampaignV2?
    
    @State private var selectedCampaign: CampaignV2?
    @State private var targetAmount: Int = 100

    // Data loading
    @State private var campaigns: [CampaignV2] = []
    @State private var isLoadingData: Bool = false
    @State private var isFetchingData: Bool = false
    @State private var lastFetchTime: Date?
    
    // Route optimization
    @State private var isOptimizing: Bool = false
    @State private var optimizedRoute: OptimizedRoute?
    @State private var showRoutePreview: Bool = false
    @State private var errorMessage: String?
    /// When true, navigate to campaign map for door-knock (tap-to-complete) workflow
    @State private var showCampaignMap: Bool = false
    
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
            .overlay(alignment: .bottom) {
                if selectedCampaign != nil {
                    bottomButtons
                }
            }
            .task(id: "sessionStartData") {
                await loadData()
                if let pre = preselectedCampaign {
                    let campaign = campaigns.first { $0.id == pre.id } ?? pre
                    selectedCampaign = campaign
                    let maxHomes = max(campaign.totalFlyers, campaign.addresses.count)
                    targetAmount = min(max(10, maxHomes), max(10, min(1000, maxHomes)))
                }
            }
            .onChange(of: selectedCampaign) { _, newCampaign in
                if let campaign = newCampaign {
                    let maxHomes = max(campaign.totalFlyers, campaign.addresses.count)
                    let cap = max(10, min(1000, maxHomes))
                    targetAmount = cap
                }
            }
            .navigationDestination(isPresented: $showRoutePreview) {
                routePreviewDestination
            }
            .navigationDestination(isPresented: $showCampaignMap) {
                campaignMapDestination
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                campaignList
                    .padding(.horizontal)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.flyrCaption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.vertical)
        }
    }

    private var targetAmountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target Homes")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(targetAmount) Homes")
                        .font(.flyrHeadline)
                    Text("Available: \(maxAvailableAddresses) addresses")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                    if let estimate = estimatedTime {
                        Text("Estimated: \(estimate)")
                            .font(.flyrSubheadline)
                            .foregroundColor(.red)
                    }
                }
                Spacer(minLength: 12)
                Stepper(value: $targetAmount, in: 10...max(10, min(1000, maxAvailableAddresses)), step: 10) {
                    EmptyView()
                }
                .onChange(of: targetAmount) { _, _ in HapticManager.light() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
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
    private var routePreviewDestination: some View {
        if let route = optimizedRoute {
            RoutePreviewView(
                route: route,
                goalType: .flyers,
                goalAmount: route.stopCount,
                campaignId: selectedCampaign?.id,
                sessionNotes: nil,
                showCancelButton: showCancelButton
            )
        }
    }

    @ViewBuilder
    private var campaignMapDestination: some View {
        if let campaign = selectedCampaign {
            CampaignMapView(campaignId: campaign.id.uuidString)
        }
    }
    
    // MARK: - Campaign List
    
    private var campaignList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAMPAIGN")
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
                ForEach(campaigns) { campaign in
                    VStack(alignment: .leading, spacing: 12) {
                        campaignRow(campaign)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.light()
                                selectedCampaign = campaign
                            }
                        if selectedCampaign?.id == campaign.id {
                            targetAmountSection
                        }
                    }
                }
            }
        }
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
            
            if selectedCampaign?.id == campaign.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedCampaign?.id == campaign.id ? Color.red.opacity(0.1) : Color(.systemGray6))
        )
    }
    
    // MARK: - Bottom Button (Start Session)

    private var bottomButtons: some View {
        VStack(spacing: 0) {
            if selectedCampaign != nil {
                Button {
                    HapticManager.medium()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showCampaignMap = true
                    }
                } label: {
                    Text("Start Session")
                        .font(.flyrHeadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Helpers
    
    private var maxAvailableAddresses: Int {
        if let campaign = selectedCampaign {
            return max(campaign.totalFlyers, campaign.addresses.count)
        }
        return 100
    }
    
    private var estimatedTime: String? {
        let minutes = targetAmount * 2 // 2 minutes per home
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
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
            campaigns = try await CampaignsAPI.shared.fetchCampaignsV2()
            print("✅ Loaded \(campaigns.count) campaigns")
        } catch {
            // CRITICAL: Don't treat cancellation as failure — prevents infinite retry loop
            if (error as NSError).code == NSURLErrorCancelled {
                print("Fetch cancelled (view disposed) - not retrying")
                return
            }
            print("❌ Failed to load campaigns: \(error)")
            campaigns = []
        }
    }
    
    // MARK: - Route Generation
    
    private func generateRoute() async {
        guard let location = SessionManager.shared.currentLocation else {
            errorMessage = "Unable to get current location. Please ensure location services are enabled."
            return
        }
        
        isOptimizing = true
        errorMessage = nil
        
        do {
            if let campaign = selectedCampaign {
                try await generateCampaignRoute(campaign: campaign, startLocation: location.coordinate)
            }
        } catch {
            errorMessage = "Failed to optimize route: \(error.localizedDescription)"
            HapticManager.error()
            print("❌ Route optimization failed: \(error)")
        }
        
        isOptimizing = false
    }
    
    private func generateCampaignRoute(campaign: CampaignV2, startLocation: CLLocationCoordinate2D) async throws {
        // Fetch addresses if not already loaded
        var addresses = campaign.addresses
        if addresses.isEmpty {
            // Fetch from API and convert to CampaignAddress
            let addressRows = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaign.id)
            addresses = addressRows.map { row in
                CampaignAddress(
                    id: row.id,
                    address: row.formatted,
                    coordinate: CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon),
                    buildingOutline: nil
                )
            }
        }
        
        // Optimize route
        let route = await RouteOptimizationService.shared.optimizeRoute(
            addresses: addresses,
            startLocation: startLocation,
            targetCount: targetAmount,
            campaignId: campaign.id.uuidString
        )
        
        if let route = route {
            optimizedRoute = route
            showRoutePreview = true
            HapticManager.success()
        } else {
            errorMessage = "Failed to generate route"
            HapticManager.error()
        }
    }
}


