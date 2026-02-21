import SwiftUI
import CoreLocation

/// Session delivery method: door knock (current flow) or flyer-only (no knock).
/// Use one process with this mode—same session/map/route; only what we record (flyers distributed vs doors knocked) and counts differ. No need for two separate processes.
enum SessionMethod: String, CaseIterable {
    case doorKnock = "door_knock"
    case flyerNoKnock = "flyer_no_knock"

    var displayName: String {
        switch self {
        case .doorKnock: return "Door Knock"
        case .flyerNoKnock: return "Flyer (no knock)"
        }
    }

    var subtitle: String {
        switch self {
        case .doorKnock: return "Knock and deliver"
        case .flyerNoKnock: return "Drop flyer only"
        }
    }
}

struct SessionStartView: View {
    @Environment(\.dismiss) private var dismiss

    /// When false, Cancel button is hidden (e.g. when used as Record tab root).
    var showCancelButton: Bool = true

    /// When set (e.g. from campaigns list play button), preselect this campaign on appear.
    var preselectedCampaign: CampaignV2?
    
    @State private var selectedCampaign: CampaignV2?
    @State private var targetAmount: Int = 100
    /// Door knock (current flow) vs flyer-only (no knock); flyer path is same as door knock for now, named separately for future differentiation.
    @State private var sessionMethod: SessionMethod = .doorKnock

    // Data loading
    @State private var campaigns: [CampaignV2] = []
    @State private var routes: [RouteAssignmentSummary] = []
    @State private var isLoadingData: Bool = false
    @State private var isFetchingData: Bool = false
    @State private var lastFetchTime: Date?
    
    /// Show at most this many items before "More" menu
    private let maxVisibleItems = 3
    
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
            VStack(alignment: .leading, spacing: 24) {
                campaignList
                routesList

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

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Method")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sessionMethod.displayName)
                        .font(.flyrHeadline)
                    Text(sessionMethod.subtitle)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                Picker("Method", selection: $sessionMethod) {
                    ForEach(SessionMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: sessionMethod) { _, _ in HapticManager.light() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    /// Optimized Route button — wire to route generation / preview when ready.
    private var optimizedRouteButton: some View {
        Button {
            HapticManager.light()
            // TODO: Wire to optimized route flow (e.g. generateRoute + showRoutePreview)
        } label: {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(.secondary)
                Text("Optimized Route")
                    .font(.flyrHeadline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
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
                    VStack(alignment: .leading, spacing: 12) {
                        campaignRow(campaign)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.light()
                                selectedCampaign = campaign
                            }
                        if selectedCampaign?.id == campaign.id {
                            targetAmountSection
                            methodSection
                            optimizedRouteButton
                        }
                    }
                }
                if !remaining.isEmpty {
                    Menu {
                        ForEach(remaining) { campaign in
                            Button(campaign.name) {
                                HapticManager.light()
                                selectedCampaign = campaign
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
    
    // MARK: - Routes List
    
    private var routesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTES")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)
            
            if isLoadingData && routes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if routes.isEmpty {
                Text("No routes available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(routes) { route in
                    NavigationLink {
                        RoutePlanDetailView(routePlanId: route.routePlanId, assignment: route)
                    } label: {
                        routeRow(route)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func routeRow(_ route: RouteAssignmentSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RouteCardEmblem()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(route.name)
                        .font(.flyrHeadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Spacer()
                    Text(route.statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(routeStatusColor(route.status))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(routeStatusColor(route.status).opacity(0.15))
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Label("\(route.totalStops) stops", systemImage: "mappin.and.ellipse")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                    if let estMinutes = route.estMinutes {
                        Label("\(estMinutes) min", systemImage: "clock")
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                    }
                    if let meters = route.distanceMeters {
                        Label(formatDistance(meters), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                    }
                }

                ProgressView(value: route.progressFraction)
                    .tint(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text(route.assignedByName.map { "Assigned by \($0)" } ?? "Assigned route")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                    Text("\(route.completedStops)/\(max(route.totalStops, 0)) complete")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
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
    
    private func statusColor(_ status: CampaignStatus) -> Color {
        switch status {
        case .draft: return .blue
        case .active: return .green
        case .completed: return .gray
        case .paused: return .flyrPrimary
        case .archived: return .gray
        }
    }

    private func routeStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed":
            return .green
        case "in_progress":
            return .orange
        case "cancelled":
            return .gray
        default:
            return .blue
        }
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters)m"
    }

    @ViewBuilder
    private func RouteCardEmblem() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.9))
                .frame(width: 44, height: 44)

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
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
        await loadAssignedRoutes()
    }
    
    private func loadCampaigns() async {
        do {
            campaigns = try await CampaignsAPI.shared.fetchCampaignsV2(workspaceId: WorkspaceContext.shared.workspaceId)
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

    private func loadAssignedRoutes() async {
        do {
            guard let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId) else {
                routes = []
                return
            }
            routes = try await RoutePlansAPI.shared.fetchMyAssignedRoutes(workspaceId: workspaceId)
            print("✅ Loaded \(routes.count) assigned routes")
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                print("Route fetch cancelled (view disposed) - not retrying")
                return
            }
            print("❌ Failed to load assigned routes: \(error)")
            routes = []
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
