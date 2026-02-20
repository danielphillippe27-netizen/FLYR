import SwiftUI
import CoreHaptics
import CoreLocation

struct NewCampaignScreen: View {
    @ObservedObject var store: CampaignV2Store
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var type: CampaignType? = nil
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

    private var mapPreviewCenter: CLLocationCoordinate2D {
        selectedCenter ?? locationManager.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
    }

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              type != nil else { return false }
        return drawnPolygon != nil && drawnPolygon!.count >= 3
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                
                FormSection("Campaign") {
                    // Title field — user enters manually; not auto-filled from Type
                    HStack {
                        TextField("Title", text: $name)
                            .textInputAutocapitalization(.words)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Type: Flyer or Door Knock only; no default selection
                    HStack {
                        Text("Type")
                        Spacer()
                        Menu {
                            Button("Flyer") { type = .flyer }
                            Button("Door Knock") { type = .doorKnock }
                        } label: {
                            HStack(spacing: 4) {
                                Text(type?.title ?? "Select type")
                                    .foregroundStyle(type == nil ? .secondary : .primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.flyrCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: 200, alignment: .trailing)
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
        guard let selectedType = type else { return }
        let effectivePolygon = polygonFromSheet ?? drawnPolygon
        let canCreateFromForm = canCreate
        let canCreateFromMapSheet = source == .map && (effectivePolygon?.count ?? 0) >= 3 && !name.trimmingCharacters(in: .whitespaces).isEmpty
        print("🚀 [CAMPAIGN DEBUG] Starting campaign creation workflow")
        print("🚀 [CAMPAIGN DEBUG] Campaign name: '\(name)'")
        print("🚀 [CAMPAIGN DEBUG] Campaign type: \(type?.rawValue ?? "nil")")
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
                type: selectedType,
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
                dismiss()
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { store.routeToV2Detail?(created.id) }
            } else {
                print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            }
            
        case .map:
            print("🗺️ [CAMPAIGN DEBUG] Creating campaign with map source")
            if let polygon = effectivePolygon, polygon.count >= 3 {
                // Polygon flow: create campaign (minimal addresses), then provision (backend Lambda/S3)
                print("🗺️ [CAMPAIGN DEBUG] Using drawn polygon (\(polygon.count) points) – will provision after create")
                let workspaceId = await RoutePlansAPI.shared.primaryWorkspaceIdForCurrentUser()
                guard let workspaceId else {
                    createHook.error = "No workspace found. Please sign out and back in, or try again."
                    return
                }
                let payload = CampaignCreatePayloadV2(
                    name: name,
                    description: description.isEmpty ? "Campaign created from polygon" : description,
                    type: selectedType,
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
                    let geoJSON = polygonToGeoJSON(polygon)
                    do {
                        try await CampaignsAPI.shared.updateTerritoryBoundary(campaignId: created.id, polygonGeoJSON: geoJSON)
                        print("🗺️ [CAMPAIGN DEBUG] Territory updated, starting provision...")
                        try await CampaignsAPI.shared.provisionCampaign(campaignId: created.id)
                        let provisionState = try await CampaignsAPI.shared.waitForProvisionReady(campaignId: created.id)
                        if provisionState.provisionStatus != "ready" {
                            createHook.error = "Campaign created but provisioning did not complete (status: \(provisionState.provisionStatus ?? "unknown")). You can retry from campaign details."
                        }
                    } catch {
                        print("❌ [CAMPAIGN DEBUG] Provision failed: \(error)")
                        createHook.error = "Campaign created but provisioning failed: \(error.localizedDescription). You can retry from campaign details."
                    }
                    // Always dismiss and navigate once campaign exists and territory is set (don't leave user stuck on loading)
                    dismiss()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await MainActor.run { store.routeToV2Detail?(created.id) }
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
}

#Preview {
    NavigationStack {
        NewCampaignScreen(store: CampaignV2Store.shared)
    }
}
