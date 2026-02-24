import SwiftUI
import CoreHaptics
import CoreLocation

struct NewCampaignScreen: View {
    @ObservedObject var store: CampaignV2Store
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var entitlementsService: EntitlementsService
    
    @State private var name = ""
    @State private var description = ""
    @State private var tags = ""
    @State private var source: AddressSource = .map
    @State private var count: AddressCountOption = .c100

    @StateObject private var auto = UseAddressAutocomplete()
    @State private var showMapSeed = false
    @State private var seedLabel: String = ""
    @State private var selectedCenter: CLLocationCoordinate2D? = nil
    @State private var drawnPolygon: [CLLocationCoordinate2D]? = nil

    @StateObject private var createHook = UseCreateCampaign()
    @StateObject private var locationManager = LocationManager()
    @Environment(\.colorScheme) private var colorScheme
    /// Screen-level lock for the full workflow (create + territory save + provision + navigation).
    /// Do not use createHook.isCreating for this because createHook resets after insert/createV2 returns.
    @State private var isSubmittingCampaign = false
    @State private var showPaywall = false

    private var mapPreviewCenter: CLLocationCoordinate2D {
        selectedCenter ?? locationManager.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
    }

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return drawnPolygon != nil && drawnPolygon!.count >= 3
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                
                FormSection("Campaign") {
                    // Title field
                    HStack {
                        TextField("Title", text: $name)
                            .textInputAutocapitalization(.words)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Tags field with consistent styling
                    HStack {
                        TextField("Tags (optional)", text: $tags)
                            .textInputAutocapitalization(.words)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .formContainerPadding()
                
                // Territory: starting address + map preview + draw polygon
                VStack(alignment: .leading, spacing: 16) {
                    Text("Territory")
                        .font(.flyrHeadline)

                    Text("Starting address (optional)")
                        .font(.flyrSubheadline)
                        .foregroundStyle(.secondary)

                    AddressSearchField(auto: auto) { suggestion in
                        selectedCenter = suggestion.coordinate
                        seedLabel = auto.query
                        auto.clear()
                    }

                    // Map preview: tap to open draw polygon workflow
                    TerritoryPreviewMapView(center: selectedCenter ?? locationManager.currentLocation?.coordinate, polygon: drawnPolygon, useDarkStyle: colorScheme == .dark, height: 220)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showMapSeed = true
                        }

                    Button {
                        showMapSeed = true
                    } label: {
                        HStack {
                            Image(systemName: "map")
                            Text(seedLabel.isEmpty ? "Draw polygon on map" : seedLabel)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.flyrCaption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    if !seedLabel.isEmpty {
                        Text("Create Campaign will save the territory and provision addresses from the area.")
                            .font(.flyrFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .formContainerPadding()

                Rectangle()
                    .fill(.clear)
                    .frame(height: 8)
            }
        }
        .navigationTitle("New Campaign")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let err = createHook.error { 
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.flyrFootnote) 
                }
                PrimaryButton(
                    title: "Create Campaign",
                    enabled: canCreate && !isSubmittingCampaign,
                    isLoading: isSubmittingCampaign
                ) {
                    guard !isSubmittingCampaign else { return }
                    isSubmittingCampaign = true
                    Task { await createCampaignTapped() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
        }
                .onAppear {
                    locationManager.requestLocation()
                }
                .sheet(isPresented: $showMapSeed) {
                    MapDrawingView(
                        initialCenter: selectedCenter ?? locationManager.currentLocation?.coordinate,
                        onPolygonDone: { vertices in
                            self.drawnPolygon = vertices
                            self.selectedCenter = nil
                            self.seedLabel = "Polygon (\(vertices.count) points)"
                            self.showMapSeed = false
                        },
                        onCreateCampaign: { vertices in
                            self.drawnPolygon = vertices
                            self.selectedCenter = nil
                            self.seedLabel = "Polygon (\(vertices.count) points)"
                            self.showMapSeed = false
                            guard !self.isSubmittingCampaign else { return }
                            self.isSubmittingCampaign = true
                            Task { await self.createCampaignTapped(polygonFromSheet: vertices) }
                        }
                    )
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
                .overlay {
                    if isSubmittingCampaign {
                        CampaignCreatingOverlayView(useDarkStyle: colorScheme == .dark)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                    }
                }
                .hidesTabBar()
    }
    
    /// If polygonFromSheet is non-nil, use it for the map flow (avoids relying on state when coming from sheet).
    private func createCampaignTapped(polygonFromSheet: [CLLocationCoordinate2D]? = nil) async {
        defer { isSubmittingCampaign = false }
        guard await canCreateCampaignInCurrentPlan() else {
            await MainActor.run { showPaywall = true }
            return
        }
        let effectivePolygon = polygonFromSheet ?? drawnPolygon
        let canCreateFromForm = canCreate
        let canCreateFromMapSheet = source == .map && (effectivePolygon?.count ?? 0) >= 3 && !name.trimmingCharacters(in: .whitespaces).isEmpty
        print("🚀 [CAMPAIGN DEBUG] Starting campaign creation workflow")
        print("🚀 [CAMPAIGN DEBUG] Campaign name: '\(name)'")
        print("🚀 [CAMPAIGN DEBUG] Address source: \(source.rawValue)")
        print("🚀 [CAMPAIGN DEBUG] Can create (form): \(canCreateFromForm), (map sheet): \(canCreateFromMapSheet)")
        
        guard canCreateFromForm || canCreateFromMapSheet else {
            print("❌ [CAMPAIGN DEBUG] Cannot create campaign - validation failed")
            return
        }
        
        switch source {
        case .closestHome:
            print("🏠 [CAMPAIGN DEBUG] Creating campaign with closest home source (create first, then address backend)")
            var center: CLLocationCoordinate2D?
            if let c = selectedCenter {
                center = c
            } else if !auto.query.isEmpty {
                do {
                    let seed = try await GeoAPI.shared.forwardGeocodeSeed(auto.query)
                    center = seed.coordinate
                } catch {
                    print("❌ [CAMPAIGN DEBUG] Geocode failed: \(error)")
                    createHook.error = "Could not find location for \"\(auto.query)\""
                    return
                }
            }
            guard let center else {
                createHook.error = "Select an address or enter a location"
                return
            }
            print("🏠 [CAMPAIGN DEBUG] Seed center: (\(center.latitude), \(center.longitude)), target count: \(count.rawValue)")

            let workspaceId = await RoutePlansAPI.shared.primaryWorkspaceIdForCurrentUser()
            guard let workspaceId else {
                createHook.error = "No workspace found. Please sign out and back in, or try again."
                return
            }
            let payload = CampaignCreatePayloadV2(
                name: name,
                description: description.isEmpty ? "Campaign created from \(source.displayName)" : description,
                type: nil,
                addressSource: source,
                addressTargetCount: count.rawValue,
                seedQuery: auto.query.isEmpty ? nil : auto.query,
                seedLon: center.longitude,
                seedLat: center.latitude,
                tags: tags.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tags.trimmingCharacters(in: .whitespaces),
                addressesJSON: [],
                workspaceId: workspaceId
            )

            if let created = await createHook.createV2(payload: payload, store: store) {
                print("✅ [CAMPAIGN DEBUG] Campaign created with ID: \(created.id), calling generate-address-list...")
                do {
                    _ = try await OvertureAddressService.shared.getAddressesNearest(center: center, limit: count.rawValue, campaignId: created.id, startingAddress: auto.query.isEmpty ? nil : auto.query)
                    print("✅ [CAMPAIGN DEBUG] Address list generated")
                } catch {
                    print("⚠️ [CAMPAIGN DEBUG] generate-address-list failed: \(error)")
                    createHook.error = "Campaign created. Address list is still loading or failed; check the campaign in a moment."
                }
                await routeToCampaignMap(created)
            } else {
                print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            }
            
        case .map:
            print("🗺️ [CAMPAIGN DEBUG] Creating campaign with map source")
            if let polygon = effectivePolygon, polygon.count >= 3 {
                // Polygon flow: create campaign (minimal addresses), then provision (backend Lambda/S3)
                print("🗺️ [CAMPAIGN DEBUG] Using drawn polygon (\(polygon.count) points) – will provision after create")
                print("🗺️ [CAMPAIGN DEBUG] Polygon bounds: \(polygonBoundsSummary(for: polygon))")
                let workspaceId = await RoutePlansAPI.shared.primaryWorkspaceIdForCurrentUser()
                guard let workspaceId else {
                    createHook.error = "No workspace found. Please sign out and back in, or try again."
                    return
                }
                let payload = CampaignCreatePayloadV2(
                    name: name,
                    description: description.isEmpty ? "Campaign created from polygon" : description,
                    type: nil,
                    addressSource: source,
                    addressTargetCount: 0,
                    seedQuery: nil,
                    seedLon: nil,
                    seedLat: nil,
                    tags: tags.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tags.trimmingCharacters(in: .whitespaces),
                    addressesJSON: [],
                    workspaceId: workspaceId
                )
                if let created = await createHook.createV2(payload: payload, store: store) {
                    print("✅ [CAMPAIGN DEBUG] Campaign created with ID: \(created.id)")
                    let geoJSON = polygonToGeoJSON(polygon)
                    var shouldNavigateToDetails = true
                    do {
                        try await CampaignsAPI.shared.updateTerritoryBoundary(campaignId: created.id, polygonGeoJSON: geoJSON)
                        print("🗺️ [CAMPAIGN DEBUG] Territory updated, calling generate-address-list (polygon mode)...")
                        do {
                            let preview = try await OvertureAddressService.shared.getAddressesInPolygon(
                                polygonGeoJSON: geoJSON,
                                campaignId: created.id
                            )
                            print("✅ [CAMPAIGN DEBUG] generate-address-list completed, preview_count=\(preview.count)")
                        } catch {
                            print("⚠️ [CAMPAIGN DEBUG] generate-address-list (polygon) failed: \(error)")
                        }
                        print("🗺️ [CAMPAIGN DEBUG] Territory updated, starting provision...")
                        let provisionResponse = try await CampaignsAPI.shared.provisionCampaign(campaignId: created.id)
                        let provisionState = try await CampaignsAPI.shared.waitForProvisionReady(campaignId: created.id)
                        if provisionState.provisionStatus != "ready" {
                            createHook.error = "Campaign created but provisioning did not complete (status: \(provisionState.provisionStatus ?? "unknown")). You can retry from campaign details."
                            shouldNavigateToDetails = false
                        } else {
                            let dbAddressCount = (try? await CampaignsAPI.shared.fetchAddresses(campaignId: created.id).count) ?? 0
                            let addressesSaved = provisionResponse?.addressesSaved ?? dbAddressCount
                            let buildingsSaved = provisionResponse?.buildingsSaved ?? 0
                            print("🗺️ [CAMPAIGN DEBUG] Provision result: addresses=\(addressesSaved), buildings=\(buildingsSaved), dbAddresses=\(dbAddressCount)")
                            if addressesSaved == 0 && buildingsSaved == 0 {
                                createHook.error = "Campaign was created, but no addresses/buildings were found in this area. Try drawing a larger polygon or a different location."
                                shouldNavigateToDetails = false
                            }
                        }
                    } catch {
                        print("❌ [CAMPAIGN DEBUG] Provision failed: \(error)")
                        createHook.error = "Campaign created but provisioning failed: \(error.localizedDescription). You can retry from campaign details."
                        shouldNavigateToDetails = false
                    }
                    guard shouldNavigateToDetails else { return }
                    await routeToCampaignMap(created)
                } else {
                    print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
                }
            } else {
                createHook.error = "Draw a polygon on the map"
            }
            
        case .sameStreet, .importList:
            print("📋 [CAMPAIGN DEBUG] Import list functionality not implemented")
            // TODO: Implement import list functionality if needed
        }
    }

    private func canCreateCampaignInCurrentPlan() async -> Bool {
        if entitlementsService.canUsePro {
            return true
        }
        if !store.campaigns.isEmpty {
            return false
        }
        let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId)
        do {
            let campaigns = try await CampaignsAPI.shared.fetchCampaignsMetadata(workspaceId: workspaceId)
            return campaigns.isEmpty
        } catch {
            return store.campaigns.isEmpty
        }
    }

    /// Build GeoJSON Polygon for territory_boundary (matches web: draw_polygon → getAll() → geometry).
    /// Ring is closed (first point = last point), coordinates [longitude, latitude], at least 4 points.
    private func polygonToGeoJSON(_ polygon: [CLLocationCoordinate2D]) -> String {
        var coords = polygon
        if coords.first != coords.last, let first = coords.first {
            coords.append(first)
        }
        // GeoJSON: [lng, lat] per point; ring must have ≥4 points (closed = 3 vertices + repeat first).
        let coordinateArray = coords.map { [$0.longitude, $0.latitude] }
        let geoJSON: [String: Any] = ["type": "Polygon", "coordinates": [coordinateArray]]
        let data = (try? JSONSerialization.data(withJSONObject: geoJSON)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func polygonBoundsSummary(for polygon: [CLLocationCoordinate2D]) -> String {
        guard let first = polygon.first else { return "empty" }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coord in polygon {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        return "lat[\(minLat), \(maxLat)] lon[\(minLon), \(maxLon)]"
    }

    /// After successful creation/provision, close create flow and open the new campaign in map mode.
    private func routeToCampaignMap(_ campaign: CampaignV2) async {
        dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            uiState.selectedMapCampaignId = campaign.id
            uiState.selectedMapCampaignName = campaign.name
            uiState.selectedTabIndex = 1
        }
    }
}

#Preview {
    NavigationStack {
        NewCampaignScreen(store: CampaignV2Store.shared)
    }
    .environmentObject(AppUIState())
}
