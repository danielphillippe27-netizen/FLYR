import SwiftUI
import CoreLocation

/// Detail view for CampaignV2
struct NewCampaignDetailView: View {
    let campaignID: UUID
    @ObservedObject var store: CampaignV2Store
    @StateObject private var hook = UseCampaignV2()
    @StateObject private var mapVM = UseCampaignMap()
    @State private var mapCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38) // Toronto default
    @State private var isMapFullscreen = false
    @State private var isDrawingPolygon = false
    @State private var showCreateQR = false
    @State private var showSessionStart = false
    @State private var selectedAddressId: String? = nil
    @State private var selectedAddressLabel: String = ""
    @State private var isStatusSheetPresented = false
    @Namespace private var mapNamespace
    
    // Pro Mode: Campaign markers for map
    private var campaignMarkers: [MapMarker] {
        guard let campaign = hook.item else { return [] }
        
        var markers: [MapMarker] = []
        
        // Add campaign center marker
        markers.append(MapMarker(
            coordinate: mapCenter,
            title: campaign.name,
            color: "red"
        ))
        
        // Add address markers
        for (index, address) in campaign.addresses.prefix(5).enumerated() {
            if let coordinate = address.coordinate {
                markers.append(MapMarker(
                    coordinate: coordinate,
                    title: "Address \(index + 1)",
                    color: "blue"
                ))
            }
        }
        
        return markers
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(hook.item?.name ?? "Loading...")
                            .font(.heading)
                            .foregroundColor(.text)
                        
                        Spacer()
                        
                        if let campaign = hook.item {
                            CampaignTypeLabel(type: campaign.type, size: .medium)
                        }
                    }
                    
                    if let campaign = hook.item {
                        Text("Created \(campaign.createdAt, formatter: dateFormatter)")
                            .font(.caption)
                            .foregroundColor(.muted)
                    }
                }
                
                // Progress Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Progress")
                            .font(.subheading)
                            .foregroundColor(.text)
                        
                        Spacer()
                        
                        if let campaign = hook.item {
                            Text("\(Int(campaign.progress * 100))% completed")
                                .font(.label)
                                .fontWeight(.medium)
                                .foregroundColor(.text)
                        }
                    }
                    
                    if let campaign = hook.item {
                        ProgressBar(value: campaign.progress)
                    }
                }
                .padding(16)
                .background(Color.bgSecondary)
                .cornerRadius(12)
                
                // Map Section - Interactive Campaign Map
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Campaign Area")
                            .font(.subheading)
                            .foregroundColor(.text)
                        
                        Spacer()
                        
                        // Draw Area button
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            if isDrawingPolygon {
                                // Exiting draw mode - polygon will be finalized in updateUIView
                                isDrawingPolygon = false
                            } else {
                                // Entering draw mode
                                isDrawingPolygon = true
                            }
                        }) {
                            Text(isDrawingPolygon ? "Done" : "Draw Area")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(isDrawingPolygon ? .white : .accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isDrawingPolygon ? Color.accent : Color.accent.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    ZStack {
                        CampaignMapView(
                            vm: mapVM,
                            centerCoordinate: mapCenter,
                            isDrawingPolygon: $isDrawingPolygon,
                            onPolygonComplete: { vertices in
                                Task {
                                    await mapVM.loadAddressesInPolygon(polygon: vertices, campaignId: campaignID)
                                    let count = mapVM.homes.count
                                    print("✅ [POLYGON] Total addresses after polygon query: \(count)")
                                }
                                isDrawingPolygon = false
                            },
                            onAddressTapped: { addressId in
                                handleAddressTapped(addressId: addressId)
                            }
                        )
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .matchedGeometryEffect(id: "map", in: mapNamespace)
                        
                        // Overlay button for fullscreen (only when not drawing)
                        if !isDrawingPolygon {
                            Button(action: {
                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                                isMapFullscreen = true
                            }) {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        // Overlays: fetching ribbon + footnote
                        VStack {
                            // Fetching buildings ribbon
                            if mapVM.isFetchingBuildings {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Fetching buildings…")
                                        .font(.footnote)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(10)
                                .padding(.top, 8)
                            }
                            
                            Spacer()
                            
                            // Buildings X/Y footnote
                            HStack {
                                Text(mapVM.buildingStats.isEmpty ? "Buildings: 0/0" : mapVM.buildingStats)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.55))
                                    .cornerRadius(8)
                                Spacer()
                            }
                            .padding(.leading, 8)
                            .padding(.bottom, 8)
                        }
                        
                        // Tap indicator overlay (only show when not drawing)
                        if !isDrawingPolygon {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(8)
                                Spacer()
                            }
                        }
                        
                        // Drawing mode indicator
                        if isDrawingPolygon {
                            VStack {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 4) {
                                        Image(systemName: "hand.tap.fill")
                                            .font(.caption)
                                        Text("Tap to add points")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.accent.opacity(0.8))
                                    .cornerRadius(8)
                                }
                                .padding(8)
                                Spacer()
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $isMapFullscreen) {
                    FullscreenMapView(
                        campaignID: campaignID,
                        store: store,
                        mapVM: mapVM,
                        mapCenter: mapCenter,
                        namespace: mapNamespace,
                        isDrawingPolygon: $isDrawingPolygon,
                        onClose: {
                            isMapFullscreen = false
                        }
                    )
                }
                
                // Addresses Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Addresses")
                            .font(.subheading)
                            .foregroundColor(.text)
                        
                        Spacer()
                        
                        if let campaign = hook.item {
                            Text("\(campaign.addresses.count) total")
                                .font(.label)
                                .foregroundColor(.muted)
                        }
                    }
                    
                    if let campaign = hook.item, !campaign.addresses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(campaign.addresses.prefix(5).enumerated()), id: \.offset) { index, address in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.muted)
                                        .frame(width: 20, alignment: .leading)
                                    
                                    Text(address.address)
                                        .font(.body)
                                        .foregroundColor(.text)
                                    
                                    Spacer()
                                }
                            }
                            
                            if campaign.addresses.count > 5 {
                                Button("See all \(campaign.addresses.count) addresses") {
                                    // TODO: Show full address list
                                }
                                .font(.label)
                                .foregroundColor(.accent)
                            }
                        }
                        .padding(12)
                        .background(Color.bgTertiary)
                        .cornerRadius(8)
                    } else {
                        Text("No addresses added yet")
                            .font(.body)
                            .foregroundColor(.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(20)
                            .background(Color.bgTertiary)
                            .cornerRadius(8)
                    }
                }
                
                // Landing Pages Section
                if let campaign = hook.item {
                    LandingPagesSection(campaignId: campaignID, campaign: campaign)
                }
                
                // Analytics Section
                if let campaign = hook.item {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Analytics")
                            .font(.subheading)
                            .foregroundColor(.text)
                        
                        // General Campaign Analytics
                        VStack(alignment: .leading, spacing: 12) {
                            StatGrid(stats: generalAnalyticsStats(for: campaign), columns: 2)
                        }
                        .padding(16)
                        .background(Color.bgSecondary)
                        .cornerRadius(12)
                        
                        // Doorknock Mode Analytics
                        if campaign.type == .doorKnock {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Door Knock Metrics")
                                    .font(.label)
                                    .fontWeight(.medium)
                                    .foregroundColor(.text)
                                
                                StatGrid(stats: doorknockAnalyticsStats(for: campaign), columns: 2)
                            }
                            .padding(16)
                            .background(Color.bgSecondary)
                            .cornerRadius(12)
                        }
                    }
                }
                
                Spacer(minLength: 100) // Space for button
            }
            .padding()
        }
        .navigationTitle("Campaign Details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // Action Buttons
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    // Create QR Code Button
                    Button(action: {
                        showCreateQR = true
                    }) {
                        HStack {
                            Image(systemName: "qrcode")
                                .font(.system(size: 16, weight: .medium))
                            Text("Create QR Code")
                                .font(.label)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accent.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Start Session Button
                    Button(action: {
                        showSessionStart = true
                    }) {
                        Text("Start Session")
                            .font(.label)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.accent)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Color.bg)
        }
        .sheet(isPresented: $showCreateQR) {
            NavigationStack {
                CreateQRView(selectedCampaignId: campaignID)
            }
        }
        .sheet(isPresented: $showSessionStart) {
            SessionStartView()
        }
        .sheet(isPresented: $isStatusSheetPresented) {
            if let addressId = selectedAddressId {
                StatusPickerSheet(
                    addressLabel: selectedAddressLabel,
                    currentStatus: mapVM.addressStatuses[addressId] ?? .none,
                    onSelect: { status in
                        handleStatusSelected(addressId: addressId, newStatus: status)
                    }
                )
            }
        }
        .onAppear {
            print("📱 [DETAIL DEBUG] NewCampaignDetailView appeared for campaign ID: \(campaignID)")
            hook.load(id: campaignID, store: store)
        }
        .onChange(of: hook.item) { _, campaign in
            if let campaign = campaign {
                print("📱 [DETAIL DEBUG] Campaign loaded: '\(campaign.name)'")
                print("📱 [DETAIL DEBUG] Campaign progress: \(Int(campaign.progress * 100))%")
                print("📱 [DETAIL DEBUG] Campaign addresses: \(campaign.addresses.count)")
                updateMapCenter(for: campaign)
                
                // Always reload map when campaign loads (ensures it shows)
                Task {
                    print("🗺️ [MAP] Loading map with \(campaign.addresses.count) addresses")
                    await mapVM.loadHomes(campaignId: campaignID, campaign: campaign)
                    print("🗺️ [MAP] Map loaded with \(mapVM.homes.count) home points")
                    // Load footprints after homes are loaded
                    await mapVM.loadFootprints()
                }
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private func updateMapCenter(for campaign: CampaignV2) {
        // Use the first address in the list to center the map
        if let firstAddress = campaign.addresses.first {
            if let coord = firstAddress.coordinate {
                mapCenter = coord
                print("🗺️ [MAP] Centering map on first address: \(firstAddress.address) at \(coord)")
            } else {
                // If first address doesn't have coordinates, try to find any address with coordinates
                if let firstAddressWithCoords = campaign.addresses.first(where: { $0.coordinate != nil }) {
                    mapCenter = firstAddressWithCoords.coordinate!
                    print("🗺️ [MAP] First address has no coordinates, using first available: \(firstAddressWithCoords.coordinate!)")
                } else {
                    // Keep default Toronto center if no addresses have coordinates
                    print("🗺️ [MAP] No addresses with coordinates, using default center")
                }
            }
        } else {
            // Keep default Toronto center if campaign has no addresses
            print("🗺️ [MAP] Campaign has no addresses, using default center")
        }
    }
    
    // MARK: - Status Picker Handlers
    
    private func handleAddressTapped(addressId: String) {
        // Look up address label from mapVM.homes
        if let home = mapVM.homes.first(where: { $0.id.uuidString == addressId }) {
            selectedAddressId = addressId
            selectedAddressLabel = home.address
            isStatusSheetPresented = true
            print("📋 [STATUS] Address tapped: \(home.address) (ID: \(addressId))")
        } else {
            print("⚠️ [STATUS] Address not found in homes: \(addressId)")
        }
    }
    
    private func handleStatusSelected(addressId: String, newStatus: AddressStatus) {
        guard let addressUUID = UUID(uuidString: addressId) else {
            print("❌ [STATUS] Invalid address ID: \(addressId)")
            return
        }
        
        Task {
            do {
                // Update Supabase
                try await VisitsAPI.shared.updateStatus(
                    addressId: addressUUID,
                    campaignId: campaignID,
                    status: newStatus,
                    notes: nil
                )
                
                // Update view model on main thread
                await MainActor.run {
                    mapVM.addressStatuses[addressId] = newStatus
                }
                
                // Update Mapbox feature-state if MapView is available
                if let mapView = mapVM.mapView {
                    await MainActor.run {
                        MapController.shared.applyStatusFeatureState(
                            statuses: [addressId: newStatus],
                            mapView: mapView
                        )
                    }
                } else {
                    print("⚠️ [STATUS] MapView not available for feature-state update")
                }
                
                print("✅ [STATUS] Status updated: \(addressId) -> \(newStatus.rawValue)")
            } catch {
                print("❌ [STATUS] Error updating status: \(error)")
            }
        }
    }
    
    // MARK: - Analytics Helpers
    
    private func generalAnalyticsStats(for campaign: CampaignV2) -> [StatPill] {
        // Calculate distance traveled (placeholder - would need to track actual route)
        // For now, estimate based on addresses count (rough estimate: 0.1 km per address)
        let estimatedDistance = Double(campaign.addresses.count) * 0.1
        
        // Calculate time (placeholder - would need to track actual time)
        // Estimate: 2 minutes per address
        let estimatedTimeMinutes = campaign.addresses.count * 2
        let hours = estimatedTimeMinutes / 60
        let minutes = estimatedTimeMinutes % 60
        let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        
        // Calculate flyers per hour
        let flyersPerHour = estimatedTimeMinutes > 0 ? Double(campaign.scans) / (Double(estimatedTimeMinutes) / 60.0) : 0.0
        
        return [
            StatPill(
                value: String(format: "%.1f", estimatedDistance),
                label: "KM Traveled"
            ),
            StatPill(
                value: "\(campaign.scans)",
                label: "Flyers Delivered"
            ),
            StatPill(
                value: timeString,
                label: "Time"
            ),
            StatPill(
                value: String(format: "%.1f", flyersPerHour),
                label: "Flyers/Hour"
            )
        ]
    }
    
    private func doorknockAnalyticsStats(for campaign: CampaignV2) -> [StatPill] {
        // Placeholder data - would need to track actual conversations and leads
        // For now, estimate based on scans (assuming some conversations happened)
        let estimatedConversations = Int(Double(campaign.scans) * 0.3) // 30% conversation rate
        let estimatedLeads = campaign.conversions // Use conversions as leads
        
        // Calculate conversion rate from conversations to leads
        let convoToLeadRate = estimatedConversations > 0 
            ? Double(estimatedLeads) / Double(estimatedConversations) * 100.0 
            : 0.0
        
        return [
            StatPill(
                value: "\(estimatedConversations)",
                label: "Conversations"
            ),
            StatPill(
                value: "\(estimatedLeads)",
                label: "Leads"
            ),
            StatPill(
                value: String(format: "%.1f%%", convoToLeadRate),
                label: "Convo → Lead"
            )
        ]
    }
    
    // Pro Mode: No need for building outlines rendering - using static map API
}

// MARK: - Fullscreen Map View

struct FullscreenMapView: View {
    let campaignID: UUID
    let store: CampaignV2Store
    @ObservedObject var mapVM: UseCampaignMap
    let mapCenter: CLLocationCoordinate2D
    let namespace: Namespace.ID
    @Binding var isDrawingPolygon: Bool
    let onClose: () -> Void
    @State private var selectedAddressId: String? = nil
    @State private var selectedAddressLabel: String = ""
    @State private var isStatusSheetPresented = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CampaignMapView(
                vm: mapVM,
                centerCoordinate: mapCenter,
                isDrawingPolygon: $isDrawingPolygon,
                onPolygonComplete: { vertices in
                    Task {
                        await mapVM.loadAddressesInPolygon(polygon: vertices, campaignId: campaignID)
                        let count = mapVM.homes.count
                        print("✅ [POLYGON] Total addresses after polygon query: \(count)")
                    }
                    isDrawingPolygon = false
                },
                onAddressTapped: { addressId in
                    handleAddressTapped(addressId: addressId)
                }
            )
            .ignoresSafeArea()
            .matchedGeometryEffect(id: "map", in: namespace)
            
            // Top controls
            VStack {
                HStack {
                    // Draw Area button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        if isDrawingPolygon {
                            // Exiting draw mode - polygon will be finalized in updateUIView
                            isDrawingPolygon = false
                        } else {
                            // Entering draw mode
                            isDrawingPolygon = true
                        }
                    }) {
                        Text(isDrawingPolygon ? "Done" : "Draw Area")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(isDrawingPolygon ? .white : .accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isDrawingPolygon ? Color.accent : Color.accent.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    // Close button
                    Button(action: {
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        onClose()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding()
                
                Spacer()
            }
            
            // Overlays: fetching ribbon + footnote
            VStack {
                // Fetching buildings ribbon
                if mapVM.isFetchingBuildings {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Fetching buildings…")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .padding(.top, 100) // Account for top controls
                }
                
                Spacer()
                
                // Drawing mode indicator
                if isDrawingPolygon {
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.caption)
                                    Text("Tap map to add polygon points")
                                        .font(.caption)
                                }
                                Text("Tap 'Done' when finished")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.accent.opacity(0.9))
                            .cornerRadius(10)
                            Spacer()
                        }
                        .padding(.leading, 8)
                        .padding(.bottom, 8)
                    }
                }
                
                // Buildings X/Y footnote
                HStack {
                    Text(mapVM.buildingStats.isEmpty ? "Buildings: 0/0" : mapVM.buildingStats)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $isStatusSheetPresented) {
            if let addressId = selectedAddressId {
                StatusPickerSheet(
                    addressLabel: selectedAddressLabel,
                    currentStatus: mapVM.addressStatuses[addressId] ?? .none,
                    onSelect: { status in
                        handleStatusSelected(addressId: addressId, newStatus: status)
                    }
                )
            }
        }
    }
    
    // MARK: - Status Picker Handlers
    
    private func handleAddressTapped(addressId: String) {
        // Look up address label from mapVM.homes
        if let home = mapVM.homes.first(where: { $0.id.uuidString == addressId }) {
            selectedAddressId = addressId
            selectedAddressLabel = home.address
            isStatusSheetPresented = true
            print("📋 [STATUS] Address tapped: \(home.address) (ID: \(addressId))")
        } else {
            print("⚠️ [STATUS] Address not found in homes: \(addressId)")
        }
    }
    
    private func handleStatusSelected(addressId: String, newStatus: AddressStatus) {
        guard let addressUUID = UUID(uuidString: addressId) else {
            print("❌ [STATUS] Invalid address ID: \(addressId)")
            return
        }
        
        Task {
            do {
                // Update Supabase
                try await VisitsAPI.shared.updateStatus(
                    addressId: addressUUID,
                    campaignId: campaignID,
                    status: newStatus,
                    notes: nil
                )
                
                // Update view model on main thread
                await MainActor.run {
                    mapVM.addressStatuses[addressId] = newStatus
                }
                
                // Update Mapbox feature-state if MapView is available
                if let mapView = mapVM.mapView {
                    await MainActor.run {
                        MapController.shared.applyStatusFeatureState(
                            statuses: [addressId: newStatus],
                            mapView: mapView
                        )
                    }
                } else {
                    print("⚠️ [STATUS] MapView not available for feature-state update")
                }
                
                print("✅ [STATUS] Status updated: \(addressId) -> \(newStatus.rawValue)")
            } catch {
                print("❌ [STATUS] Error updating status: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let store = CampaignV2Store.shared
    let mockCampaign = CampaignV2.mockCampaigns[0]
    store.append(mockCampaign)
    
    return NavigationStack {
        NewCampaignDetailView(campaignID: mockCampaign.id, store: store)
    }
}
