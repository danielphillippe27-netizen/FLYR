import SwiftUI
import CoreHaptics
import CoreLocation

private enum CampaignCreationStage {
    case territory
    case details
}

struct NewCampaignScreen: View {
    @ObservedObject var store: CampaignV2Store
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @ObservedObject private var workspaceContext = WorkspaceContext.shared
    
    @State private var name = ""
    @State private var description = ""

    @StateObject private var auto = UseAddressAutocomplete()
    @State private var showMapSeed = false
    @State private var mapCenterLabel: String = ""
    @State private var selectedCenter: CLLocationCoordinate2D? = nil
    @State private var drawnPolygon: [CLLocationCoordinate2D]? = nil

    @StateObject private var createHook = UseCreateCampaign()
    @StateObject private var locationManager = LocationManager()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSubmittingCampaign = false
    @State private var showPaywall = false
    @State private var campaignType: CampaignType = .justSold
    @State private var creationStage: CampaignCreationStage = .territory
    @State private var createdCampaign: CampaignV2?
    @State private var isProvisioningCampaign = false
    @State private var provisionComplete = false
    @State private var provisionFailed = false
    @State private var provisionStatusText = ""
    @State private var provisionProgressPercent = 0
    @State private var detailsSaving = false
    @State private var detailsSaved = false
    @State private var hasNavigatedToCampaign = false
    @State private var campaignMapDataReady = false
    @State private var showCampaignReadinessOverlay = false
    @State private var provisioningTask: Task<Void, Never>?

    private var mapPreviewCenter: CLLocationCoordinate2D {
        selectedCenter ?? locationManager.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
    }

    private var trimmedCampaignName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCampaignName: Bool {
        !trimmedCampaignName.isEmpty
    }

    private var hasDrawnTerritory: Bool {
        (drawnPolygon?.count ?? 0) >= 3
    }

    private var hasMapCenterAddress: Bool {
        !mapCenterLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCreate: Bool {
        creationStage == .territory && hasDrawnTerritory && createdCampaign == nil
    }

    private var createButtonTitle: String {
        if !hasDrawnTerritory {
            return "Draw Territory"
        }
        return "Create Territory"
    }

    private var detailsButtonTitle: String {
        if createdCampaign == nil || isSubmittingCampaign {
            return "Preparing Campaign"
        }
        if detailsSaving {
            return "Saving Details"
        }
        if detailsSaved && campaignMapDataReady {
            return "Open Campaign"
        }
        if detailsSaved {
            return "Done"
        }
        return "Save & Open"
    }

    private var detailsButtonEnabled: Bool {
        createdCampaign != nil && hasCampaignName && !detailsSaving && !hasNavigatedToCampaign
    }

    private var shouldShowCampaignCreatingOverlay: Bool {
        showCampaignReadinessOverlay && isProvisioningCampaign && !provisionFailed
    }

    private var territoryHelperText: String {
        if !hasDrawnTerritory {
            return hasMapCenterAddress
                ? "Map centered. Now draw your territory on the map."
                : "Territory not set yet - draw on the map to continue."
        }
        return "Territory set. Create it, then name the campaign while homes load."
    }

    private var territoryHelperColor: Color {
        if hasDrawnTerritory {
            return .green
        }
        return .secondary
    }

    private var campaignTypeOptions: [CampaignType] {
        CampaignType.ordered(forIndustry: workspaceContext.industry)
    }

    var body: some View {
        Group {
            if creationStage == .territory {
                ZStack(alignment: .bottom) {
                    MapDrawingView(
                        initialCenter: selectedCenter ?? locationManager.currentLocation?.coordinate,
                        onPolygonDone: { vertices in
                            self.beginCampaignCreation(with: vertices)
                        },
                        onCreateCampaign: { vertices in
                            self.beginCampaignCreation(with: vertices)
                        },
                        dismissOnPolygonDone: false,
                        dismissOnCreateCampaign: false
                    )

                    if let err = createHook.error {
                        Text(err)
                            .font(.flyrFootnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 118)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 28) {
                    campaignDetailsSection

                        Rectangle()
                            .fill(.clear)
                            .frame(height: 8)
                    }
                }
            }
        }
        .navigationTitle(creationStage == .territory ? "" : "New Campaign")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(creationStage == .territory ? .hidden : .visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if creationStage == .details {
                VStack(spacing: 12) {
                    if let err = createHook.error {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.flyrFootnote)
                    }
                    Group {
                        PrimaryButton(
                            title: detailsButtonTitle,
                            enabled: detailsButtonEnabled,
                            isLoading: detailsSaving
                        ) {
                            Task { await saveCampaignDetailsTapped() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                .background(.ultraThinMaterial)
            }
        }
                .onAppear {
                    locationManager.requestLocation()
                    reconcileCampaignTypeWithIndustry()
                }
                .onChange(of: name) { _, _ in
                    markDetailsDirtyIfNeeded()
                }
                .onChange(of: campaignType) { _, _ in
                    markDetailsDirtyIfNeeded()
                }
                .onChange(of: workspaceContext.industry) { _, _ in
                    reconcileCampaignTypeWithIndustry()
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
                .overlay {
                    if shouldShowCampaignCreatingOverlay {
                        CampaignCreatingOverlayView(useDarkStyle: colorScheme == .dark)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                    }
                }
                .hidesTabBar()
    }

    private var territorySetupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1")
                .font(.flyrCaption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Draw your territory")
                .font(.flyrHeadline)

            ZStack(alignment: .topLeading) {
                TerritoryPreviewMapView(center: mapPreviewCenter, polygon: drawnPolygon, useDarkStyle: colorScheme == .dark, height: 220)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openMapDrawing()
                    }

                if !hasDrawnTerritory {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No territory drawn yet")
                            .font(.flyrFootnote.weight(.semibold))
                        Text("Tap or drag on the map to outline your area.")
                            .font(.flyrCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }

            Text(territoryHelperText)
                .font(.flyrFootnote)
                .foregroundStyle(territoryHelperColor)

            Divider()

            HStack(spacing: 8) {
                Text("Map center")
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("(Optional)")
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            AddressSearchField(
                auto: auto,
                onPick: { suggestion in
                    applySelectedCenter(
                        suggestion.coordinate,
                        label: formattedAddress(from: suggestion)
                    )
                    auto.clear()
                },
                onSubmitQuery: { query in
                    Task { await centerMap(on: query) }
                }
            )

            if hasMapCenterAddress {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Map centered at")
                            .font(.flyrFootnote)
                            .foregroundStyle(.secondary)
                        Text(mapCenterLabel)
                            .font(.flyrSubheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .formContainerPadding()
    }

    private var campaignDetailsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Step 2")
                .font(.flyrCaption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Name campaign")
                .font(.flyrHeadline)

            HStack {
                TextField("Campaign name", text: $name)
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 16))
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Campaign type")
                    .font(.flyrSubheadline.weight(.semibold))

                Picker("Campaign type", selection: $campaignType) {
                    ForEach(campaignTypeOptions) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let tracked = localProvisionBanner {
                CampaignProvisionStatusBanner(tracked: tracked)
            }
        }
        .formContainerPadding()
    }

    private var localProvisionBanner: TrackedCampaignProvision? {
        guard let campaign = createdCampaign else { return nil }
        if provisionFailed {
            return TrackedCampaignProvision(
                campaignId: campaign.id,
                campaignName: campaign.name,
                state: .needsAttention,
                statusText: provisionStatusText.isEmpty ? "Setup needs attention." : provisionStatusText,
                progressPercent: provisionProgressPercent
            )
        }
        if isProvisioningCampaign {
            return TrackedCampaignProvision(
                campaignId: campaign.id,
                campaignName: campaign.name,
                state: .preparingMap,
                statusText: CampaignProvisionMonitor.runningStatusText,
                progressPercent: provisionProgressPercent
            )
        }
        if provisionComplete {
            return TrackedCampaignProvision(
                campaignId: campaign.id,
                campaignName: campaign.name,
                state: campaignMapDataReady ? .ready : .optimizing,
                statusText: campaignMapDataReady ? "Campaign is ready." : CampaignProvisionMonitor.runningStatusText,
                progressPercent: campaignMapDataReady ? 100 : provisionProgressPercent
            )
        }
        return nil
    }

    @MainActor
    private func beginCampaignCreation(with vertices: [CLLocationCoordinate2D]) {
        drawnPolygon = vertices
        guard !isSubmittingCampaign else { return }
        isSubmittingCampaign = true
        Task { await createCampaignTapped(polygonFromSheet: vertices) }
    }

    private func openMapDrawing() {
        showMapSeed = true
    }

    private func markDetailsDirtyIfNeeded() {
        guard creationStage == .details, detailsSaved else { return }
        detailsSaved = false
    }

    private func reconcileCampaignTypeWithIndustry() {
        let options = campaignTypeOptions
        guard !options.contains(campaignType), let fallbackType = options.first else { return }
        campaignType = fallbackType
    }
    
    /// If polygonFromSheet is non-nil, use it for the map flow (avoids relying on state when coming from sheet).
    @MainActor
    private func createCampaignTapped(polygonFromSheet: [CLLocationCoordinate2D]? = nil) async {
        defer { isSubmittingCampaign = false }
        let effectivePolygon = polygonFromSheet ?? drawnPolygon
        print("🚀 [CAMPAIGN DEBUG] Starting campaign creation workflow")

        guard let polygon = effectivePolygon, polygon.count >= 3 else {
            createHook.error = "Draw a polygon on the map"
            return
        }

        creationStage = .details
        guard await canCreateCampaignInCurrentPlan() else {
            showPaywall = true
            creationStage = .territory
            return
        }
        print("🗺️ [CAMPAIGN DEBUG] Using drawn polygon (\(polygon.count) points) - will provision in background")
        print("🗺️ [CAMPAIGN DEBUG] Polygon bounds: \(polygonBoundsSummary(for: polygon))")
        let provisionRegionCode = await inferredProvisionRegionCode(for: polygon)
        if let provisionRegionCode {
            print("🗺️ [CAMPAIGN DEBUG] Inferred provision region: \(provisionRegionCode)")
        }
        let workspaceId = await RoutePlansAPI.shared.primaryWorkspaceIdForCurrentUser()
        guard let workspaceId else {
            createHook.error = "No workspace found. Please sign out and back in, or try again."
            creationStage = .territory
            return
        }
        let payload = CampaignCreatePayloadV2(
            name: "Untitled Campaign",
            description: description.isEmpty ? "Campaign created from polygon" : description,
            type: campaignType,
            addressSource: .map,
            addressTargetCount: 0,
            seedQuery: provisionRegionCode,
            seedLon: nil,
            seedLat: nil,
            tags: nil,
            addressesJSON: [],
            workspaceId: workspaceId
        )
        if var created = await createHook.createV2(payload: payload, store: store, polygon: polygon) {
            print("✅ [CAMPAIGN DEBUG] Campaign created with ID: \(created.id)")
            created.type = campaignType
            createdCampaign = created
            createHook.error = nil
            uiState.selectCampaign(
                id: created.id,
                name: created.name,
                boundaryCoordinates: polygon
            )
            startBackgroundProvision(campaign: created, polygon: polygon, regionCode: provisionRegionCode)
        } else {
            print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            creationStage = .territory
        }
    }

    @MainActor
    private func saveCampaignDetailsTapped() async {
        guard var campaign = createdCampaign else { return }
        if detailsSaved && !isProvisioningCampaign && campaignMapDataReady {
            await openCreatedCampaign()
            return
        }

        detailsSaving = true
        defer { detailsSaving = false }

        do {
            try await CampaignsAPI.shared.updateCampaignDetails(
                campaignId: campaign.id,
                name: trimmedCampaignName,
                type: campaignType
            )
            campaign.name = trimmedCampaignName
            campaign.type = campaignType
            createdCampaign = campaign
            store.update(campaign)
            CampaignProvisionMonitor.shared.update(
                campaignId: campaign.id,
                campaignName: campaign.name,
                state: .optimizing,
                statusText: CampaignProvisionMonitor.runningStatusText,
                progressPercent: provisionProgressPercent
            )
            detailsSaved = true
            createHook.error = nil

            if campaignMapDataReady {
                await openCreatedCampaign()
            } else {
                dismiss()
            }
        } catch {
            createHook.error = "Could not save campaign details: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func startBackgroundProvision(campaign: CampaignV2, polygon: [CLLocationCoordinate2D], regionCode: String?) {
        provisioningTask?.cancel()
        isProvisioningCampaign = true
        provisionComplete = false
        provisionFailed = false
        campaignMapDataReady = false
        provisionStatusText = CampaignProvisionMonitor.runningStatusText
        updateProvisionProgress(5)
        CampaignProvisionMonitor.shared.track(
            campaign: campaign,
            state: .queued,
            statusText: CampaignProvisionMonitor.runningStatusText,
            progressPercent: provisionProgressPercent
        )
        provisioningTask = Task {
            await provisionCampaignInBackground(campaign: campaign, polygon: polygon, regionCode: regionCode)
        }
    }

    @MainActor
    private func updateProvisionProgress(_ percent: Int) {
        let clamped = CampaignProvisionMonitor.clampedProgress(percent)
        guard clamped >= provisionProgressPercent else { return }
        provisionProgressPercent = clamped
        guard let campaign = createdCampaign else { return }
        CampaignProvisionMonitor.shared.update(
            campaignId: campaign.id,
            campaignName: campaign.name,
            state: provisionBadgeState(forProgress: clamped),
            statusText: clamped >= 100 ? "Campaign is ready." : CampaignProvisionMonitor.runningStatusText,
            progressPercent: clamped
        )
    }

    private func provisionBadgeState(forProgress progressPercent: Int) -> CampaignProvisionBadgeState {
        if progressPercent >= 100 {
            return .ready
        }
        if progressPercent >= 68 {
            return .optimizing
        }
        if progressPercent >= 18 {
            return .preparingMap
        }
        return .queued
    }

    @MainActor
    private func updateProvisionProgress(
        for state: CampaignProvisionState,
        campaignId: UUID,
        campaignName: String
    ) {
        let badgeState = CampaignProvisionMonitor.badgeState(
            status: state.provisionStatus,
            phase: state.provisionPhase
        )
        let statusText = CampaignProvisionMonitor.statusText(
            status: state.provisionStatus,
            phase: state.provisionPhase
        )
        let derivedProgress = CampaignProvisionMonitor.progressPercent(
            status: state.provisionStatus,
            phase: state.provisionPhase
        )
        if let derivedProgress {
            updateProvisionProgress(derivedProgress)
        }
        CampaignProvisionMonitor.shared.update(
            campaignId: campaignId,
            campaignName: campaignName,
            state: badgeState,
            statusText: statusText,
            progressPercent: provisionProgressPercent
        )
    }

    private func continueMonitoringProvision(campaignId: UUID, campaignName: String) async {
        do {
            let state = try await CampaignsAPI.shared.waitForProvisionReady(
                campaignId: campaignId,
                requireOptimized: false,
                timeoutSeconds: 300,
                pollIntervalSeconds: 2,
                onProgress: { state in
                    updateProvisionProgress(
                        for: state,
                        campaignId: campaignId,
                        campaignName: campaignName
                    )
                }
            )
            updateProvisionProgress(
                for: state,
                campaignId: campaignId,
                campaignName: campaignName
            )
            guard isProvisionMapUsable(status: state.provisionStatus, phase: state.provisionPhase) else {
                return
            }

            if var workingCampaign = createdCampaign, workingCampaign.id == campaignId {
                workingCampaign.provisionStatus = state.provisionStatus
                workingCampaign.provisionSource = state.provisionSource
                workingCampaign.provisionPhase = state.provisionPhase
                workingCampaign.addressesReadyAt = state.addressesReadyAt
                workingCampaign.mapReadyAt = state.mapReadyAt
                workingCampaign.optimizedAt = state.optimizedAt

                let dbAddressCount = (try? await CampaignsAPI.shared.fetchCampaignAddressCount(campaignId: campaignId)) ?? 0
                let campaignAddresses = (try? await fetchCampaignAddressesWithRetry(campaignId: campaignId)) ?? []
                workingCampaign.totalFlyers = max(
                    workingCampaign.totalFlyers,
                    dbAddressCount,
                    campaignAddresses.count
                )
                preserveCurrentDetails(in: &workingCampaign)
                store.update(workingCampaign)
                createdCampaign = workingCampaign
            }

            let prewarmedMapDataReadiness = await prewarmCampaignBuildingsAfterProvision(campaignId: campaignId)
            await MapFeaturesService.shared.fetchAllCampaignFeatures(
                campaignId: campaignId.uuidString,
                forceRefresh: true
            )
            MapFeaturesService.shared.beginDiamondManifestPrewarm(
                campaignId: campaignId.uuidString,
                timeoutSeconds: 90
            )
            let mapDataReadiness: CampaignMapDataReadiness?
            if let prewarmedMapDataReadiness {
                mapDataReadiness = prewarmedMapDataReadiness
            } else {
                mapDataReadiness = await waitForCampaignMapDataReady(campaignId: campaignId)
            }

            if let mapDataReadiness {
                campaignMapDataReady = true
                provisionFailed = false
                provisionStatusText = "Campaign is ready."
                updateProvisionProgress(100)
                CampaignProvisionMonitor.shared.update(
                    campaignId: campaignId,
                    campaignName: campaignName,
                    state: .ready,
                    statusText: "Campaign is ready.",
                    progressPercent: provisionProgressPercent
                )
                print("🗺️ [CAMPAIGN DEBUG] Background map data ready: buildings=\(mapDataReadiness.buildingCount) addresses=\(mapDataReadiness.addressCount)")

                if detailsSaved {
                    await openCreatedCampaign()
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ [CAMPAIGN DEBUG] Background provision monitor failed: \(error.localizedDescription)")
            #endif
        }
    }

    @MainActor
    private func provisionCampaignInBackground(campaign: CampaignV2, polygon: [CLLocationCoordinate2D], regionCode: String?) async {
        var workingCampaign = campaign
        let geoJSON = polygonToGeoJSON(polygon)

        do {
            try await CampaignsAPI.shared.updateTerritoryBoundary(
                campaignId: campaign.id,
                polygonGeoJSON: geoJSON,
                regionCode: regionCode
            )
            provisionStatusText = CampaignProvisionMonitor.runningStatusText
            updateProvisionProgress(18)
            let provisionResponse = try await CampaignsAPI.shared.provisionCampaign(
                campaignId: campaign.id,
                waitUntilReady: false
            )
            updateProvisionProgress(35)
            if let confidence = provisionResponse?.dataConfidenceSummary {
                workingCampaign.dataConfidence = confidence
            }
            workingCampaign.provisionStatus = provisionResponse?.provisionStatus
            workingCampaign.provisionSource = provisionResponse?.provisionSource
            workingCampaign.provisionPhase = provisionResponse?.provisionPhase
            workingCampaign.hasParcels = provisionResponse?.hasParcels
            workingCampaign.buildingLinkConfidence = provisionResponse?.buildingLinkConfidence
            workingCampaign.mapMode = provisionResponse?.mapMode
            if let addressesSaved = provisionResponse?.addressesSaved {
                workingCampaign.totalFlyers = max(workingCampaign.totalFlyers, addressesSaved)
            }
            preserveCurrentDetails(in: &workingCampaign)
            store.update(workingCampaign)
            createdCampaign = workingCampaign

            if provisionResponse?.accepted == true || provisionResponse?.provisionStatus == .pending {
                CampaignProvisionMonitor.shared.update(
                    campaignId: campaign.id,
                    campaignName: workingCampaign.name,
                    state: .optimizing,
                    statusText: CampaignProvisionMonitor.runningStatusText,
                    progressPercent: provisionProgressPercent
                )
                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                isProvisioningCampaign = false
                provisionComplete = true
                provisionFailed = false
                Task {
                    await continueMonitoringProvision(
                        campaignId: campaign.id,
                        campaignName: workingCampaign.name
                    )
                }
                Task {
                    await PushRegistrationService.shared.requestCampaignReadyPermissionAndRegister()
                }
                return
            }

            let needsProvisionWait = !isProvisionMapUsable(
                status: provisionResponse?.provisionStatus,
                phase: provisionResponse?.provisionPhase
            )
            var finalProvisionStatus = provisionResponse?.provisionStatus
            if needsProvisionWait {
                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                let provisionState = try await CampaignsAPI.shared.waitForProvisionReady(
                    campaignId: campaign.id,
                    requireOptimized: false,
                    onProgress: { state in
                        updateProvisionProgress(
                            for: state,
                            campaignId: campaign.id,
                            campaignName: workingCampaign.name
                        )
                    }
                )
                workingCampaign.provisionStatus = provisionState.provisionStatus
                workingCampaign.provisionSource = provisionState.provisionSource
                workingCampaign.provisionPhase = provisionState.provisionPhase
                workingCampaign.addressesReadyAt = provisionState.addressesReadyAt
                workingCampaign.mapReadyAt = provisionState.mapReadyAt
                workingCampaign.optimizedAt = provisionState.optimizedAt
                preserveCurrentDetails(in: &workingCampaign)
                store.update(workingCampaign)
                createdCampaign = workingCampaign
                finalProvisionStatus = provisionState.provisionStatus
            }

            var mapDataReadiness: CampaignMapDataReadiness?
            if finalProvisionStatus == .ready {
                let dbAddressCount = (try? await CampaignsAPI.shared.fetchCampaignAddressCount(campaignId: campaign.id)) ?? 0
                let addressesSaved = max(provisionResponse?.addressesSaved ?? 0, dbAddressCount)
                let buildingsSaved = provisionResponse?.buildingsSaved ?? 0
                print("🗺️ [CAMPAIGN DEBUG] Provision result: addresses=\(addressesSaved), buildings=\(buildingsSaved), dbAddresses=\(dbAddressCount)")
                workingCampaign.totalFlyers = max(workingCampaign.totalFlyers, addressesSaved, dbAddressCount)
                preserveCurrentDetails(in: &workingCampaign)
                store.update(workingCampaign)
                createdCampaign = workingCampaign
                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                updateProvisionProgress(68)
                let addressTask = Task {
                    (try? await fetchCampaignAddressesWithRetry(campaignId: campaign.id)) ?? []
                }
                let buildingTask = Task {
                    await prewarmCampaignBuildingsAfterProvision(campaignId: campaign.id)
                }

                let campaignAddresses = await addressTask.value
                if !campaignAddresses.isEmpty {
                    workingCampaign.totalFlyers = max(workingCampaign.totalFlyers, campaignAddresses.count)
                    preserveCurrentDetails(in: &workingCampaign)
                    store.update(workingCampaign)
                    createdCampaign = workingCampaign
                    updateProvisionProgress(75)
                }
                let prewarmedMapDataReadiness = await buildingTask.value

                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                updateProvisionProgress(82)
                await MapFeaturesService.shared.fetchAllCampaignFeatures(
                    campaignId: campaign.id.uuidString,
                    forceRefresh: true
                )

                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                updateProvisionProgress(88)
                MapFeaturesService.shared.beginDiamondManifestPrewarm(
                    campaignId: campaign.id.uuidString,
                    timeoutSeconds: 90
                )
                print("💎 [CAMPAIGN DEBUG] Diamond/Bedrock geometry will warm in the background")

                if let prewarmedMapDataReadiness {
                    mapDataReadiness = prewarmedMapDataReadiness
                } else {
                    mapDataReadiness = await waitForCampaignMapDataReady(campaignId: campaign.id)
                }
                if let mapDataReadiness {
                    campaignMapDataReady = true
                    provisionStatusText = "Campaign is ready."
                    updateProvisionProgress(100)
                    CampaignProvisionMonitor.shared.update(
                        campaignId: campaign.id,
                        campaignName: workingCampaign.name,
                        state: .ready,
                        statusText: "Campaign is ready.",
                        progressPercent: provisionProgressPercent
                    )
                    print("🗺️ [CAMPAIGN DEBUG] Map data ready: buildings=\(mapDataReadiness.buildingCount) addresses=\(mapDataReadiness.addressCount)")
                } else {
                    campaignMapDataReady = false
                    provisionFailed = true
                    provisionStatusText = "Created, but map data is still preparing."
                    createHook.error = "Campaign created, but buildings are not ready yet. Keep this screen open or retry from campaign details."
                    CampaignProvisionMonitor.shared.update(
                        campaignId: campaign.id,
                        campaignName: workingCampaign.name,
                        state: .optimizing,
                        statusText: CampaignProvisionMonitor.runningStatusText,
                        progressPercent: provisionProgressPercent
                    )
                }
            } else {
                provisionFailed = true
                provisionStatusText = "Created, but setup needs another try."
                createHook.error = "Campaign created but provisioning did not complete (status: \(finalProvisionStatus?.rawValue ?? "unknown")). You can retry from campaign details."
                CampaignProvisionMonitor.shared.update(
                    campaignId: campaign.id,
                    campaignName: workingCampaign.name,
                    state: .needsAttention,
                    statusText: "Setup needs attention. Open the campaign to retry.",
                    progressPercent: provisionProgressPercent
                )
            }
        } catch {
            if isDiamondGeometryReadinessError(error) {
                print("💎 [CAMPAIGN DEBUG] Diamond/Bedrock geometry not ready yet; warming in the background")
                MapFeaturesService.shared.beginDiamondManifestPrewarm(
                    campaignId: campaign.id.uuidString,
                    timeoutSeconds: 90
                )
                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                campaignMapDataReady = false
                CampaignProvisionMonitor.shared.update(
                    campaignId: campaign.id,
                    state: .optimizing,
                    statusText: CampaignProvisionMonitor.runningStatusText,
                    progressPercent: provisionProgressPercent
                )
            } else {
                print("❌ [CAMPAIGN DEBUG] Provision failed: \(error)")
                provisionFailed = true
                campaignMapDataReady = false
                provisionStatusText = "Created, but setup needs another try."
                createHook.error = "Campaign created but provisioning failed: \(error.localizedDescription). You can retry from campaign details."
                CampaignProvisionMonitor.shared.update(
                    campaignId: campaign.id,
                    state: .needsAttention,
                    statusText: "Setup needs attention. Open the campaign to retry.",
                    progressPercent: provisionProgressPercent
                )
            }
        }

        isProvisioningCampaign = false
        provisionComplete = true

        if detailsSaved && campaignMapDataReady {
            await openCreatedCampaign()
        }
    }

    @MainActor
    private func preserveCurrentDetails(in campaign: inout CampaignV2) {
        if let current = createdCampaign {
            campaign.name = current.name
            campaign.type = current.type
        }
        if detailsSaved {
            campaign.name = trimmedCampaignName
            campaign.type = campaignType
        }
    }

    private func isProvisionMapUsable(
        status: CampaignProvisionStatus?,
        phase: CampaignProvisionPhase?
    ) -> Bool {
        guard status == .ready else { return false }
        guard let phase else { return true }
        return phase.isMapUsable
    }

    @MainActor
    private func openCreatedCampaign() async {
        guard !hasNavigatedToCampaign, let campaign = createdCampaign else { return }
        guard campaignMapDataReady else {
            provisionStatusText = CampaignProvisionMonitor.runningStatusText
            showCampaignReadinessOverlay = true
            return
        }
        hasNavigatedToCampaign = true
        showCampaignReadinessOverlay = false
        await routeToCampaignMap(campaign, boundaryCoordinates: drawnPolygon ?? [])
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

    private func inferredProvisionRegionCode(for polygon: [CLLocationCoordinate2D]) async -> String? {
        guard let first = polygon.first else { return nil }
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

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        if let regionCode = try? await GeoAPI.shared.reverseProvisionRegionCode(at: center) {
            return regionCode
        }

        let regionBounds: [(code: String, minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)] = [
            ("NZ", 166.0, -48.5, 179.5, -33.0),
            ("AU", 96.0, -44.0, 168.5, -9.0),
            ("GB", -6.5, 49.8, 1.9, 58.8),
            ("ZA", 16.4, -35.0, 33.1, -22.0),
            ("BC", -139.06, 48.2, -114.03, 60.01),
            ("AB", -120.0, 48.9, -109.0, 60.0),
            ("SK", -110.0, 49.0, -101.3, 60.0),
            ("MB", -102.0, 49.0, -89.0, 60.0),
            ("ON", -95.2, 41.6, -74.0, 56.9),
            ("QC", -79.9, 44.9, -57.1, 62.6),
            ("NB", -69.1, 44.5, -63.5, 48.2),
            ("NS", -66.5, 43.3, -59.7, 47.2),
            ("PE", -64.6, 45.9, -61.8, 47.1),
            ("NL", -67.9, 46.5, -52.5, 60.7),
            ("YT", -141.1, 59.9, -123.8, 69.7),
            ("NT", -136.5, 59.9, -102.0, 78.0),
            ("NU", -110.0, 50.0, -60.0, 84.0),
            ("AK", -179.2, 51.0, -129.9, 71.6),
            ("AL", -88.6, 30.1, -84.8, 35.1),
            ("AR", -94.7, 33.0, -89.6, 36.6),
            ("AZ", -114.9, 31.2, -109.0, 37.1),
            ("CA", -124.5, 32.4, -114.1, 42.1),
            ("CO", -109.1, 36.9, -102.0, 41.1),
            ("CT", -73.8, 40.9, -71.7, 42.1),
            ("DC", -77.2, 38.7, -76.8, 39.1),
            ("DE", -75.8, 38.4, -75.0, 39.9),
            ("FL", -87.7, 24.3, -79.8, 31.1),
            ("GA", -85.7, 30.3, -80.7, 35.1),
            ("HI", -160.3, 18.8, -154.7, 22.3),
            ("IA", -96.7, 40.3, -90.1, 43.6),
            ("ID", -117.3, 42.0, -111.0, 49.1),
            ("IL", -91.6, 36.9, -87.0, 42.6),
            ("IN", -88.2, 37.7, -84.7, 41.8),
            ("KS", -102.1, 36.9, -94.5, 40.1),
            ("KY", -89.7, 36.4, -81.9, 39.2),
            ("LA", -94.1, 28.8, -88.7, 33.1),
            ("MA", -73.6, 41.2, -69.9, 42.9),
            ("MD", -79.6, 37.8, -75.0, 39.8),
            ("ME", -71.1, 42.9, -66.8, 47.6),
            ("MI", -90.5, 41.6, -82.3, 48.4),
            ("MN", -97.3, 43.4, -89.5, 49.4),
            ("MO", -95.8, 35.9, -89.1, 40.7),
            ("MS", -91.8, 30.1, -88.1, 35.1),
            ("MT", -116.1, 44.3, -104.0, 49.1),
            ("NC", -84.4, 33.8, -75.4, 36.7),
            ("ND", -104.1, 45.9, -96.5, 49.1),
            ("NE", -104.1, 39.9, -95.2, 43.1),
            ("NH", -72.7, 42.6, -70.6, 45.4),
            ("NJ", -75.6, 38.8, -73.8, 41.4),
            ("NM", -109.1, 31.2, -103.0, 37.1),
            ("NV", -120.1, 35.0, -114.0, 42.1),
            ("NY", -79.8, 40.4, -71.8, 45.1),
            ("OH", -84.9, 38.3, -80.5, 42.4),
            ("OK", -103.1, 33.6, -94.3, 37.1),
            ("OR", -124.7, 41.9, -116.4, 46.4),
            ("PA", -80.6, 39.6, -74.6, 42.3),
            ("PR", -67.4, 17.8, -65.2, 18.6),
            ("RI", -71.9, 41.1, -71.0, 42.1),
            ("SC", -83.4, 32.0, -78.5, 35.3),
            ("SD", -104.1, 42.4, -96.4, 45.9),
            ("TN", -90.4, 34.9, -81.6, 36.8),
            ("TX", -106.7, 25.8, -93.5, 36.6),
            ("UT", -114.1, 36.9, -109.0, 42.1),
            ("VA", -83.8, 36.5, -75.2, 39.5),
            ("VI", -65.2, 17.6, -64.5, 18.5),
            ("VT", -73.5, 42.7, -71.4, 45.1),
            ("WA", -124.9, 45.5, -116.8, 49.1),
            ("WI", -92.9, 42.4, -86.8, 47.2),
            ("WV", -82.7, 37.1, -77.7, 40.7),
            ("WY", -111.1, 40.9, -104.0, 45.1)
        ]

        return regionBounds.first { bounds in
            centerLon >= bounds.minLon &&
            centerLon <= bounds.maxLon &&
            centerLat >= bounds.minLat &&
            centerLat <= bounds.maxLat
        }?.code
    }

    private func isDiamondGeometryReadinessError(_ error: Error) -> Bool {
        if let diamondError = error as? DiamondManifestAPIError {
            switch diamondError {
            case .httpStatus(let status):
                return status == 202 || status == 404
            case .notReady:
                return true
            case .invalidResponse:
                return false
            }
        }

        return error.localizedDescription.localizedCaseInsensitiveContains("Diamond geometry was not ready")
    }

    private struct CampaignMapDataReadiness {
        let buildingCount: Int
        let addressCount: Int

        var isUsable: Bool {
            buildingCount > 0 || addressCount > 0
        }
    }

    private func fetchCampaignAddressesWithRetry(
        campaignId: UUID,
        attempts: Int = 8,
        delayMs: UInt64 = 350
    ) async throws -> [CampaignAddressRow] {
        var lastError: Error?

        for attempt in 1...max(attempts, 1) {
            do {
                let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaignId)
                if !addresses.isEmpty {
                    print("✅ [CAMPAIGN DEBUG] Loaded \(addresses.count) addresses after provision (attempt \(attempt))")
                    return addresses
                }
                print("⚠️ [CAMPAIGN DEBUG] No addresses yet for campaign \(campaignId) (attempt \(attempt)/\(attempts))")
            } catch {
                lastError = error
                print("⚠️ [CAMPAIGN DEBUG] Address fetch attempt \(attempt)/\(attempts) failed: \(error)")
            }

            if attempt < attempts {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    private func prewarmCampaignBuildingsAfterProvision(campaignId: UUID) async -> CampaignMapDataReadiness? {
        async let buildingsResult: [BuildingFeature]? = try? BuildingLinkService.shared.fetchBuildings(campaignId: campaignId.uuidString)
        async let addressesResult: [CampaignAddressRow]? = try? fetchCampaignAddressesWithRetry(
            campaignId: campaignId,
            attempts: 3,
            delayMs: 250
        )

        let buildings = await buildingsResult ?? []
        let addresses = await addressesResult ?? []

        if !buildings.isEmpty {
            MapFeaturesService.shared.primeBuildingFeatures(
                campaignId: campaignId.uuidString,
                features: buildings
            )
        }

        let readiness = CampaignMapDataReadiness(
            buildingCount: renderableBuildingCount(in: buildings),
            addressCount: addresses.count
        )
        print("✅ [CAMPAIGN DEBUG] Campaign map prewarm loaded buildings=\(readiness.buildingCount) addresses=\(readiness.addressCount)")
        return readiness.isUsable ? readiness : nil
    }

    private func waitForCampaignMapDataReady(
        campaignId: UUID,
        timeoutSeconds: TimeInterval = 150,
        pollIntervalSeconds: TimeInterval = 2
    ) async -> CampaignMapDataReadiness? {
        let startedAt = Date()
        var attempt = 0

        while Date().timeIntervalSince(startedAt) < timeoutSeconds {
            attempt += 1
            async let buildingsResult: [BuildingFeature]? = try? BuildingLinkService.shared.fetchBuildings(campaignId: campaignId.uuidString)
            async let addressesResult: [CampaignAddressRow]? = try? fetchCampaignAddressesWithRetry(
                campaignId: campaignId,
                attempts: 2,
                delayMs: 200
            )

            let buildings = await buildingsResult ?? []
            let addresses = await addressesResult ?? []

            if !buildings.isEmpty {
                MapFeaturesService.shared.primeBuildingFeatures(
                    campaignId: campaignId.uuidString,
                    features: buildings
                )
            }

            let readiness = CampaignMapDataReadiness(
                buildingCount: renderableBuildingCount(in: buildings),
                addressCount: addresses.count
            )

            print("🧭 [CAMPAIGN DEBUG] map_data_gate attempt=\(attempt) buildings=\(readiness.buildingCount) addresses=\(readiness.addressCount)")
            if readiness.isUsable {
                return readiness
            }

            try? await Task.sleep(nanoseconds: UInt64(max(0.5, pollIntervalSeconds) * 1_000_000_000))
        }

        return nil
    }

    private func renderableBuildingCount(in buildings: [BuildingFeature]) -> Int {
        buildings.filter { feature in
            let type = feature.geometry.type.lowercased()
            return type == "polygon" || type == "multipolygon"
        }.count
    }

    @MainActor
    private func applySelectedCenter(_ coordinate: CLLocationCoordinate2D, label: String) {
        selectedCenter = coordinate
        mapCenterLabel = label
        createHook.error = nil
    }

    private func centerMap(on query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        do {
            let seed = try await GeoAPI.shared.forwardGeocodeSeed(trimmedQuery)
            await MainActor.run {
                applySelectedCenter(seed.coordinate, label: trimmedQuery)
            }
        } catch {
            await MainActor.run {
                createHook.error = "Could not center map on \"\(trimmedQuery)\""
            }
        }
    }

    private func formattedAddress(from suggestion: AddressSuggestion) -> String {
        [suggestion.title, suggestion.subtitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// After successful creation/provision, close create flow and open the new campaign in the Session tab.
    @MainActor
    private func routeToCampaignMap(
        _ campaign: CampaignV2,
        boundaryCoordinates: [CLLocationCoordinate2D] = []
    ) async {
        provisionStatusText = "Preparing campaign map..."
        let isMapReady: Bool
        if campaignMapDataReady {
            isMapReady = true
        } else {
            isMapReady = await CampaignDownloadService.shared.ensureUsableMapAssetsAvailable(
                campaignId: campaign.id.uuidString
            )
        }
        guard isMapReady else {
            await MainActor.run {
                createHook.error = "Campaign is ready, but the map has not fully downloaded to this device yet. Please keep this screen open and try again."
                showCampaignReadinessOverlay = true
                hasNavigatedToCampaign = false
            }
            return
        }

        dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            uiState.selectCampaign(
                id: campaign.id,
                name: campaign.name,
                boundaryCoordinates: boundaryCoordinates
            )
            uiState.selectedTabIndex = 1
        }
        Task {
            await CampaignDownloadService.shared.prefetchIfNeeded(campaignId: campaign.id.uuidString)
        }
    }
}

private struct CampaignBackgroundSetupCard: View {
    let isProvisioning: Bool
    let isComplete: Bool
    let didFail: Bool
    let statusText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isProvisioning {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            } else {
                Image(systemName: didFail ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(didFail ? .orange : .green)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isProvisioning ? "Setting up in the background" : didFail ? "Setup needs attention" : isComplete ? "Setup finished" : "Setup queued")
                    .font(.flyrFootnote.weight(.semibold))
                Text(statusText.isEmpty ? "Homes and map data will continue loading while you finish these details." : statusText)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        NewCampaignScreen(store: CampaignV2Store.shared)
    }
    .environmentObject(AppUIState())
}
