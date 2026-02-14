import SwiftUI
import CoreLocation

/// Detail view for CampaignV2
struct NewCampaignDetailView: View {
    let campaignID: UUID
    @ObservedObject var store: CampaignV2Store
    @StateObject private var hook = UseCampaignV2()
    @State private var mapCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38) // Toronto default
    @State private var isMapFullscreen = false
    @State private var addressStatuses: [String: AddressStatus] = [:]
    @State private var showSessionStart = false
    @State private var selectedAddressId: String? = nil
    @State private var selectedAddressLabel: String = ""
    @State private var isStatusSheetPresented = false
    @State private var isAddressesExpanded = false
    @State private var showFullAddressesSheet = false
    @State private var isLeadsExpanded = false
    @State private var campaignLeadsCount: Int = 0
    @State private var campaignLeads: [FieldLead] = []
    @State private var leadsLoaded = false
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
                            .font(.flyrCaption)
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
                
                // Map Section - 3D Campaign Map (MapFeaturesService + MapLayerManager)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Campaign Area")
                        .font(.subheading)
                        .foregroundColor(.text)
                    
                    ZStack {
                        CampaignMapView(campaignId: campaignID.uuidString)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .matchedGeometryEffect(id: "map", in: mapNamespace, isSource: !isMapFullscreen)
                        
                        // Fullscreen trigger
                        Button(action: {
                            HapticManager.medium()
                            isMapFullscreen = true
                        }) {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.flyrCaption)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(8)
                        }
                    }
                }
                .fullScreenCover(isPresented: $isMapFullscreen) {
                    FullscreenMapView(
                        campaignID: campaignID,
                        namespace: mapNamespace,
                        onClose: { isMapFullscreen = false }
                    )
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
                
                // Leads Section (collapsible, same style as Addresses)
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLeadsExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "tray.full.fill")
                                .font(.subheadline)
                                .foregroundColor(.accent)
                            Text("Leads")
                                .font(.subheading)
                                .foregroundColor(.text)
                            Spacer()
                            Text("\(campaignLeadsCount) total")
                                .font(.label)
                                .foregroundColor(.muted)
                            Image(systemName: isLeadsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.muted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onChange(of: isLeadsExpanded) { _, expanded in
                        if expanded && !leadsLoaded, let userId = AuthManager.shared.user?.id {
                            Task {
                                do {
                                    let leads = try await FieldLeadsService.shared.fetchLeads(userId: userId, campaignId: campaignID)
                                    await MainActor.run {
                                        campaignLeads = leads
                                        campaignLeadsCount = leads.count
                                        leadsLoaded = true
                                    }
                                } catch {
                                    await MainActor.run {
                                        campaignLeads = []
                                        leadsLoaded = true
                                    }
                                }
                            }
                        }
                    }

                    if isLeadsExpanded {
                        if !campaignLeads.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(campaignLeads.prefix(5).enumerated()), id: \.element.id) { index, lead in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.flyrCaption)
                                            .foregroundColor(.muted)
                                            .frame(width: 20, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(lead.address)
                                                .font(.body)
                                                .foregroundColor(.text)
                                            if let name = lead.name, !name.isEmpty {
                                                Text(name)
                                                    .font(.flyrCaption)
                                                    .foregroundColor(.muted)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                if campaignLeads.count > 5 {
                                    Button("See all \(campaignLeads.count) leads") {
                                        // TODO: Show full leads list
                                    }
                                    .font(.label)
                                    .foregroundColor(.accent)
                                }
                            }
                            .padding(12)
                            .background(Color.bgTertiary)
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        } else if leadsLoaded {
                            Text("No leads yet")
                                .font(.body)
                                .foregroundColor(.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
                .background(Color.bgSecondary)
                .cornerRadius(12)

                // Addresses Section (collapsible, at bottom, hidden by default)
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAddressesExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "house.fill")
                                .font(.subheadline)
                                .foregroundColor(.accent)
                            Text("Addresses")
                                .font(.subheading)
                                .foregroundColor(.text)
                            Spacer()
                            if let campaign = hook.item {
                                Text("\(campaign.addresses.count) total")
                                    .font(.label)
                                    .foregroundColor(.muted)
                            }
                            Image(systemName: isAddressesExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.muted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isAddressesExpanded {
                        if let campaign = hook.item, !campaign.addresses.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(campaign.addresses.prefix(5).enumerated()), id: \.offset) { index, address in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.flyrCaption)
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
                                        HapticManager.light()
                                        showFullAddressesSheet = true
                                    }
                                    .font(.label)
                                    .foregroundColor(.accent)
                                }
                            }
                            .padding(12)
                            .background(Color.bgTertiary)
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        } else {
                            Text("No addresses added yet")
                                .font(.body)
                                .foregroundColor(.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
                .background(Color.bgSecondary)
                .cornerRadius(12)
                
                Spacer(minLength: 100) // Space for button
            }
            .padding()
        }
        .navigationTitle("Campaign Details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                
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
                .padding()
            }
            .background(Color.bg)
        }
        .sheet(isPresented: $showSessionStart) {
            SessionStartView(preselectedCampaign: hook.item)
        }
        .sheet(isPresented: $showFullAddressesSheet) {
            if let campaign = hook.item {
                FullAddressesSheet(addresses: campaign.addresses)
            }
        }
        .sheet(isPresented: $isStatusSheetPresented) {
            if let addressId = selectedAddressId {
                StatusPickerSheet(
                    addressLabel: selectedAddressLabel,
                    currentStatus: addressStatuses[addressId] ?? .none,
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
                
                // Load address statuses for status sheet
                Task {
                    do {
                        let statusRows = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignID)
                        let dict = Dictionary(uniqueKeysWithValues: statusRows.map { ($0.key.uuidString, $0.value.status) })
                        await MainActor.run { addressStatuses = dict }
                    } catch {
                        print("⚠️ [DETAIL] Failed to fetch address statuses: \(error)")
                    }
                }
                // Load leads count for this campaign
                if let userId = AuthManager.shared.user?.id {
                    Task {
                        do {
                            let leads = try await FieldLeadsService.shared.fetchLeads(userId: userId, campaignId: campaignID)
                            await MainActor.run { campaignLeadsCount = leads.count }
                        } catch {
                            await MainActor.run { campaignLeadsCount = 0 }
                        }
                    }
                } else {
                    campaignLeadsCount = 0
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
        if let address = hook.item?.addresses.first(where: { $0.id.uuidString == addressId }) {
            selectedAddressId = addressId
            selectedAddressLabel = address.address
            isStatusSheetPresented = true
            print("📋 [STATUS] Address tapped: \(address.address) (ID: \(addressId))")
        } else {
            print("⚠️ [STATUS] Address not found: \(addressId)")
        }
    }
    
    private func handleStatusSelected(addressId: String, newStatus: AddressStatus) {
        guard let addressUUID = UUID(uuidString: addressId) else {
            print("❌ [STATUS] Invalid address ID: \(addressId)")
            return
        }
        
        Task {
            do {
                try await VisitsAPI.shared.updateStatus(
                    addressId: addressUUID,
                    campaignId: campaignID,
                    status: newStatus,
                    notes: nil
                )
                await MainActor.run {
                    addressStatuses[addressId] = newStatus
                }
                print("✅ [STATUS] Status updated: \(addressId) -> \(newStatus.rawValue)")
            } catch {
                print("❌ [STATUS] Error updating status: \(error)")
            }
        }
    }
    
    // MARK: - Analytics Helpers
    
    private func generalAnalyticsStats(for campaign: CampaignV2) -> [StatPill] {
        // New campaigns show 0.0 km and 0m time; real values when we have session/stats API
        let distanceKm: Double = 0.0   // TODO: from session/stats when available
        let _: Int = 0     // TODO: time from session/stats when available
        let timeString = "0m"
        let flyersPerHour = 0.0

        return [
            StatPill(
                value: "\(campaign.scans)",
                label: "Flyers Delivered"
            ),
            StatPill(
                value: String(format: "%.1f", flyersPerHour),
                label: "Flyers/Hour"
            ),
            StatPill(
                value: timeString,
                label: "Time"
            ),
            StatPill(
                value: String(format: "%.1f", distanceKm),
                label: "KM Traveled"
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

// MARK: - Full Addresses Sheet

private struct FullAddressesSheet: View {
    let addresses: [CampaignAddress]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(addresses.enumerated()), id: \.element.id) { index, address in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.flyrCaption)
                            .foregroundColor(.muted)
                            .frame(width: 24, alignment: .leading)
                        Text(address.address)
                            .font(.body)
                            .foregroundColor(.text)
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.bgTertiary)
                    .listRowSeparatorTint(.muted.opacity(0.3))
                }
            }
            .listStyle(.plain)
            .background(Color.bg)
            .navigationTitle("\(addresses.count) Addresses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.light()
                        dismiss()
                    }
                    .font(.label)
                    .foregroundColor(.accent)
                }
            }
        }
    }
}

// MARK: - Fullscreen Map View

struct FullscreenMapView: View {
    let campaignID: UUID
    let namespace: Namespace.ID
    let onClose: () -> Void
    @ObservedObject private var sessionManager = SessionManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CampaignMapView(campaignId: campaignID.uuidString)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .matchedGeometryEffect(id: "map", in: namespace, isSource: true)

            // X close button only when no active session (Finish is in map overlay when session active)
            // Top-right, aligned with building toggle (same insets as map overlayUI)
            if sessionManager.sessionId == nil {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
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
                        .padding(.trailing, 8)
                    }
                    .padding(.top, 52)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
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



