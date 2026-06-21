import SwiftUI
import CoreHaptics
import CoreLocation

private enum CampaignCreationStage {
    case territory
    case creating
    case details
}

private struct PendingCampaignProvision {
    let polygon: [CLLocationCoordinate2D]
    let regionCode: String?
}

struct NewCampaignScreen: View {
    private let store: CampaignV2Store
    private let resumedCampaignId: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @ObservedObject private var workspaceContext = WorkspaceContext.shared
    @ObservedObject private var provisionMonitor = CampaignProvisionMonitor.shared
    
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
    @State private var isCancellingProvision = false
    @State private var cancelProvisionError: String?
    @State private var hasLoadedResumedCampaign = false
    @State private var hasRegisteredCreationPresentation = false
    @State private var campaignCreationTask: Task<Void, Never>?
    @State private var provisioningTask: Task<Void, Never>?
    @State private var mapBundlePrewarmTask: Task<Void, Never>?
    @State private var mapBundlePrewarmCampaignId: UUID?
    @State private var pendingProvision: PendingCampaignProvision?
    @State private var campaignHomeLimitAlertMessage: String?

    init(store: CampaignV2Store, resumedCampaignId: UUID? = nil) {
        self.store = store
        self.resumedCampaignId = resumedCampaignId
        _creationStage = State(initialValue: resumedCampaignId == nil ? .territory : .creating)
    }

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
        showCampaignReadinessOverlay && !campaignMapDataReady && !provisionFailed
    }

    private var activeCreatingCampaignId: UUID? {
        createdCampaign?.id ?? resumedCampaignId ?? provisionMonitor.tracked?.campaignId
    }

    private var trackedForActiveCampaign: TrackedCampaignProvision? {
        guard let activeCreatingCampaignId,
              provisionMonitor.tracked?.campaignId == activeCreatingCampaignId else {
            return nil
        }
        return provisionMonitor.tracked
    }

    private var creatingProgressPercent: Int {
        max(
            CampaignProvisionMonitor.clampedProgress(provisionProgressPercent),
            trackedForActiveCampaign?.displayProgressPercent ?? 0
        )
    }

    private var creatingActivityText: String {
        trackedForActiveCampaign?.activityText ?? CampaignProvisionMonitor.activityText(progressPercent: creatingProgressPercent)
    }

    private var creatingErrorText: String? {
        cancelProvisionError ?? createHook.error
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
            switch creationStage {
            case .territory:
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
            case .creating:
                CampaignCreatingOverlayView(
                    useDarkStyle: colorScheme == .dark,
                    progressPercent: creatingProgressPercent,
                    activityText: creatingActivityText,
                    isCancelling: isCancellingProvision,
                    errorText: creatingErrorText,
                    onCancel: {
                        Task { await cancelCampaignCreation() }
                    },
                    onReady: {
                        Task { await handleCreatingOverlayReady() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            case .details:
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
        .navigationTitle(creationStage == .details ? "New Campaign" : "")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(creationStage == .details ? .visible : .hidden, for: .navigationBar)
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
            registerCampaignCreationPresentationIfNeeded()
            locationManager.requestLocation()
            reconcileCampaignTypeWithIndustry()
            configureResumedCampaignIfNeeded()
        }
        .onDisappear {
            unregisterCampaignCreationPresentationIfNeeded()
        }
        .onChange(of: provisionMonitor.tracked) { _, _ in
            Task { await reconcileTrackedProvisionState() }
        }
        .task(id: creationStage) {
            guard creationStage == .creating else { return }
            while !Task.isCancelled, creationStage == .creating {
                await provisionMonitor.refreshLatest()
                await reconcileTrackedProvisionState()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .onChange(of: name) { _, _ in
            markDetailsDirtyIfNeeded()
        }
        .onChange(of: campaignType) { _, _ in
            markDetailsDirtyIfNeeded()
        }
        .onChange(of: description) { _, _ in
            markDetailsDirtyIfNeeded()
        }
        .onChange(of: workspaceContext.industry) { _, _ in
            reconcileCampaignTypeWithIndustry()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert(
            "Campaign size limit",
            isPresented: Binding(
                get: { campaignHomeLimitAlertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        campaignHomeLimitAlertMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                campaignHomeLimitAlertMessage = nil
            }
        } message: {
            Text(campaignHomeLimitAlertMessage ?? "")
        }
        .overlay {
            if shouldShowCampaignCreatingOverlay {
                CampaignCreatingOverlayView(
                    useDarkStyle: colorScheme == .dark,
                    progressPercent: creatingProgressPercent,
                    activityText: creatingActivityText,
                    isCancelling: isCancellingProvision,
                    errorText: creatingErrorText,
                    onCancel: {
                        Task { await cancelCampaignCreation() }
                    },
                    onReady: {
                        Task { await handleCreatingOverlayReady() }
                    }
                )
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
                    .foregroundStyle(.secondary)

                TypeChips(selected: $campaignType, options: campaignTypeOptions)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.flyrSubheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Add notes", text: $description, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .font(.system(size: 16))
                    .lineLimit(3...6)
                    .frame(minHeight: 86, alignment: .topLeading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

        }
        .formContainerPadding()
    }

    @MainActor
    private func registerCampaignCreationPresentationIfNeeded() {
        guard !hasRegisteredCreationPresentation else { return }
        hasRegisteredCreationPresentation = true
        uiState.campaignCreationFlowDidAppear()
    }

    @MainActor
    private func unregisterCampaignCreationPresentationIfNeeded() {
        guard hasRegisteredCreationPresentation else { return }
        hasRegisteredCreationPresentation = false
        uiState.campaignCreationFlowDidDisappear()
    }

    @MainActor
    private func configureResumedCampaignIfNeeded() {
        guard let resumedCampaignId, !hasLoadedResumedCampaign else { return }
        hasLoadedResumedCampaign = true
        creationStage = .creating
        if let tracked = trackedForActiveCampaign {
            provisionProgressPercent = tracked.displayProgressPercent
            provisionStatusText = tracked.statusText
        }
        Task {
            await loadCampaignForCreatingFlow(campaignId: resumedCampaignId)
            await provisionMonitor.refreshLatest()
            await reconcileTrackedProvisionState()
        }
    }

    @MainActor
    private func reconcileTrackedProvisionState() async {
        guard creationStage == .creating || creationStage == .details,
              let activeCreatingCampaignId,
              let tracked = trackedForActiveCampaign,
              tracked.campaignId == activeCreatingCampaignId else {
            return
        }

        provisionProgressPercent = max(provisionProgressPercent, tracked.displayProgressPercent)
        provisionStatusText = tracked.statusText

        switch tracked.state {
        case .ready:
            provisionComplete = true
            provisionFailed = false
            provisionProgressPercent = 100
            await markCampaignReadyToOpen(
                campaignId: activeCreatingCampaignId,
                campaignName: createdCampaign?.name ?? tracked.campaignName
            )
        case .needsAttention:
            provisionComplete = true
            provisionFailed = true
            createHook.error = tracked.statusText
        case .queued, .preparingMap, .optimizing:
            break
        }
    }

    @MainActor
    @discardableResult
    private func loadCampaignForCreatingFlow(campaignId: UUID) async -> CampaignV2? {
        if let campaign = store.campaign(id: campaignId) {
            createdCampaign = campaign
            applyDetailsDefaults(from: campaign)
            await loadTerritoryBoundaryIfNeeded(campaignId: campaignId)
            return campaign
        }

        do {
            let row = try await CampaignsAPI.shared.fetchCampaignDBRow(id: campaignId)
            let campaign = campaignV2(from: row)
            if store.campaign(id: campaign.id) == nil {
                store.append(campaign)
            } else {
                store.update(campaign)
            }
            createdCampaign = campaign
            description = row.description ?? ""
            applyDetailsDefaults(from: campaign)
            await loadTerritoryBoundaryIfNeeded(campaignId: campaignId)
            return campaign
        } catch {
            createHook.error = "Could not load campaign details: \(error.localizedDescription)"
            return nil
        }
    }

    @MainActor
    private func moveCreatingFlowToDetails(campaignId: UUID) async {
        if createdCampaign?.id != campaignId {
            _ = await loadCampaignForCreatingFlow(campaignId: campaignId)
        }
        guard let campaign = createdCampaign else { return }
        applyDetailsDefaults(from: campaign)
        provisionProgressPercent = 100
        provisionStatusText = "Campaign is ready."
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            creationStage = .details
        }
    }

    @MainActor
    private func loadTerritoryBoundaryIfNeeded(campaignId: UUID) async {
        if let drawnPolygon, drawnPolygon.count >= 3 {
            return
        }
        guard let boundary = await CampaignsAPI.shared.fetchTerritoryBoundary(campaignId: campaignId),
              boundary.count >= 3 else {
            return
        }
        drawnPolygon = boundary
        if uiState.selectedMapCampaignId == campaignId {
            uiState.selectCampaign(
                id: campaignId,
                name: createdCampaign?.name ?? uiState.selectedMapCampaignName,
                boundaryCoordinates: boundary
            )
        }
    }

    @MainActor
    private func handleCreatingOverlayReady() async {
        guard creationStage == .creating,
              let campaignId = activeCreatingCampaignId else {
            return
        }

        if detailsSaved && campaignMapDataReady {
            await openCreatedCampaign()
        } else {
            await moveCreatingFlowToDetails(campaignId: campaignId)
        }
    }

    @MainActor
    private func applyDetailsDefaults(from campaign: CampaignV2) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = campaign.name
        }
        campaignType = campaign.type
    }

    private func campaignV2(from row: CampaignDBRow) -> CampaignV2 {
        CampaignV2(
            id: row.id,
            name: row.title,
            type: row.campaignType,
            addressSource: row.addressSource,
            addresses: [],
            totalFlyers: 0,
            scans: row.scans,
            conversions: row.conversions,
            createdAt: row.createdAt,
            status: row.status ?? .draft,
            seedQuery: row.region,
            dataConfidence: row.dataConfidence,
            provisionStatus: row.provisionStatus,
            provisionSource: row.provisionSource,
            provisionPhase: row.provisionPhase,
            addressesReadyAt: row.addressesReadyAt,
            mapReadyAt: row.mapReadyAt,
            optimizedAt: row.optimizedAt,
            hasParcels: row.hasParcels,
            buildingLinkConfidence: row.buildingLinkConfidence,
            mapMode: row.mapMode,
            coverageScore: row.coverageScore,
            dataQuality: row.dataQuality,
            standardModeRecommended: row.standardModeRecommended,
            dataQualityReason: row.dataQualityReason
        )
    }

    @MainActor
    private func beginCampaignCreation(with vertices: [CLLocationCoordinate2D]) {
        drawnPolygon = vertices
        guard !isSubmittingCampaign else { return }
        isSubmittingCampaign = true
        campaignCreationTask?.cancel()
        campaignCreationTask = Task { await createCampaignTapped(polygonFromSheet: vertices) }
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
        let trace = PerfTrace.begin("campaign_create", "create_campaign_tapped", fields: [
            "hasPolygonFromSheet": polygonFromSheet != nil,
            "drawnPoints": (polygonFromSheet ?? drawnPolygon)?.count ?? 0
        ])
        defer { isSubmittingCampaign = false }
        let effectivePolygon = polygonFromSheet ?? drawnPolygon
        print("🚀 [CAMPAIGN DEBUG] Starting campaign creation workflow")

        guard let polygon = effectivePolygon, polygon.count >= 3 else {
            createHook.error = "Draw a polygon on the map"
            trace.end(status: "missing_polygon")
            return
        }

        creationStage = .details
        cancelProvisionError = nil
        provisionStatusText = "Creating campaign"
        provisionProgressPercent = 0
        // Give SwiftUI a turn to render the lightweight details screen before setup resumes.
        await Task.yield()
        guard !Task.isCancelled else { return }
        let planTrace = PerfTrace.begin("campaign_create", "plan_gate", fields: [
            "points": polygon.count
        ])
        guard await canCreateCampaignInCurrentPlan() else {
            planTrace.end(status: "blocked")
            showPaywall = true
            creationStage = .territory
            trace.end(status: "plan_blocked")
            return
        }
        planTrace.end(status: "allowed")
        guard !Task.isCancelled else { return }
        print("🗺️ [CAMPAIGN DEBUG] Using drawn polygon (\(polygon.count) points) - will provision in background")
        print("🗺️ [CAMPAIGN DEBUG] Polygon bounds: \(polygonBoundsSummary(for: polygon))")
        let regionTrace = PerfTrace.begin("campaign_create", "infer_provision_region", fields: [
            "points": polygon.count
        ])
        let provisionRegionCode = await inferredProvisionRegionCode(for: polygon)
        regionTrace.end(status: provisionRegionCode == nil ? "none" : "resolved", fields: [
            "region": provisionRegionCode ?? "nil"
        ])
        guard !Task.isCancelled else { return }
        if let provisionRegionCode {
            print("🗺️ [CAMPAIGN DEBUG] Inferred provision region: \(provisionRegionCode)")
        }
        let workspaceTrace = PerfTrace.begin("campaign_create", "resolve_workspace", fields: [:])
        let workspaceId = await RoutePlansAPI.shared.primaryWorkspaceIdForCurrentUser()
        workspaceTrace.end(status: workspaceId == nil ? "missing" : "resolved", fields: [
            "workspace": workspaceId?.uuidString ?? "nil"
        ])
        guard !Task.isCancelled else { return }
        guard let workspaceId else {
            createHook.error = "No workspace found. Please sign out and back in, or try again."
            creationStage = .territory
            trace.end(status: "no_workspace")
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
        let createTrace = PerfTrace.begin("campaign_create", "create_campaign_shell", fields: [
            "workspace": workspaceId.uuidString,
            "points": polygon.count
        ])
        if var created = await createHook.createV2(payload: payload, store: store, polygon: polygon) {
            createTrace.end(status: "success", fields: [
                "campaign": created.id.uuidString
            ])
            if Task.isCancelled {
                try? await CampaignsAPI.shared.deleteCampaign(campaignId: created.id)
                store.remove(id: created.id)
                trace.end(status: "cancelled_after_create", fields: [
                    "campaign": created.id.uuidString
                ])
                return
            }
            print("✅ [CAMPAIGN DEBUG] Campaign created with ID: \(created.id)")
            created.type = campaignType
            createdCampaign = created
            createHook.error = nil
            pendingProvision = nil
            startBackgroundProvision(
                campaign: created,
                polygon: polygon,
                regionCode: provisionRegionCode
            )
            trace.end(status: "created_provisioning_in_background", fields: [
                "campaign": created.id.uuidString
            ])
        } else {
            print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            creationStage = .territory
            createTrace.end(status: "failed")
            trace.end(status: "create_failed")
        }
    }

    @MainActor
    private func saveCampaignDetailsTapped() async {
        guard var campaign = createdCampaign else { return }
        let trace = PerfTrace.begin("campaign_create", "save_campaign_details", fields: [
            "campaign": campaign.id.uuidString,
            "mapReady": campaignMapDataReady
        ])
        if detailsSaved && !isProvisioningCampaign && campaignMapDataReady {
            await openCreatedCampaign()
            trace.end(status: "already_saved_opened")
            return
        }

        detailsSaving = true
        defer { detailsSaving = false }

        do {
            try await CampaignsAPI.shared.updateCampaignDetails(
                campaignId: campaign.id,
                name: trimmedCampaignName,
                type: campaignType,
                description: description
            )
            campaign.name = trimmedCampaignName
            campaign.type = campaignType
            createdCampaign = campaign
            store.update(campaign)
            CampaignProvisionMonitor.shared.update(
                campaignId: campaign.id,
                campaignName: campaign.name,
                state: campaignMapDataReady ? .ready : .optimizing,
                statusText: campaignMapDataReady ? "Campaign is ready." : CampaignProvisionMonitor.runningStatusText,
                progressPercent: campaignMapDataReady ? 100 : provisionProgressPercent
            )
            detailsSaved = true
            createHook.error = nil
            if let pendingProvision {
                self.pendingProvision = nil
                startBackgroundProvision(
                    campaign: campaign,
                    polygon: pendingProvision.polygon,
                    regionCode: pendingProvision.regionCode
                )
            }
            await provisionMonitor.refreshLatest()
            await reconcileTrackedProvisionState()

            if campaignMapDataReady {
                await openCreatedCampaign()
            } else {
                showCampaignReadinessOverlay = false
                withAnimation(.easeInOut(duration: 0.22)) {
                    creationStage = .creating
                }
            }
            trace.end(status: "success", fields: [
                "mapReady": campaignMapDataReady
            ])
        } catch {
            createHook.error = "Could not save campaign details: \(error.localizedDescription)"
            trace.end(status: "error", fields: [
                "error": error.localizedDescription
            ])
        }
    }

    @MainActor
    private func cancelCampaignCreation() async {
        guard !isCancellingProvision else { return }
        isCancellingProvision = true
        cancelProvisionError = nil
        campaignCreationTask?.cancel()
        provisioningTask?.cancel()

        guard let campaignId = activeCreatingCampaignId else {
            isSubmittingCampaign = false
            isProvisioningCampaign = false
            isCancellingProvision = false
            dismiss()
            return
        }

        do {
            try await CampaignsAPI.shared.deleteCampaign(campaignId: campaignId)
            store.remove(id: campaignId)
            provisionMonitor.dismiss(campaignId: campaignId)
            if createdCampaign?.id == campaignId {
                createdCampaign = nil
            }
            if uiState.selectedMapCampaignId == campaignId {
                uiState.clearMapSelection()
            }
            isSubmittingCampaign = false
            isProvisioningCampaign = false
            provisionComplete = false
            provisionFailed = false
            dismiss()
        } catch {
            cancelProvisionError = "Could not cancel campaign setup: \(error.localizedDescription)"
            isCancellingProvision = false
        }
    }

    @MainActor
    private func startBackgroundProvision(
        campaign: CampaignV2,
        polygon: [CLLocationCoordinate2D],
        regionCode: String?
    ) {
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
        let task = Task {
            await provisionCampaignInBackground(campaign: campaign, polygon: polygon, regionCode: regionCode)
        }
        provisioningTask = task
    }

    @MainActor
    private func handleCampaignHomeLimitFailure(
        campaign: CampaignV2,
        polygon: [CLLocationCoordinate2D],
        regionCode: String?,
        code: String?,
        message: String
    ) {
        provisionFailed = true
        provisionComplete = false
        isProvisioningCampaign = false
        campaignMapDataReady = false
        showCampaignReadinessOverlay = false
        pendingProvision = nil
        createdCampaign = nil
        detailsSaved = false
        detailsSaving = false
        provisionStatusText = ""
        provisionProgressPercent = 0
        createHook.error = nil
        campaignHomeLimitAlertMessage = message
        store.remove(id: campaign.id)
        CampaignProvisionMonitor.shared.dismiss(campaignId: campaign.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            creationStage = .territory
        }
        Task {
            try? await CampaignsAPI.shared.deleteCampaign(campaignId: campaign.id)
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
        let trace = PerfTrace.begin("campaign_create", "continue_monitoring_provision", fields: [
            "campaign": campaignId.uuidString
        ])
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
                trace.end(status: "not_usable", fields: [
                    "status": state.provisionStatus?.rawValue ?? "nil",
                    "phase": state.provisionPhase?.rawValue ?? "nil"
                ])
                return
            }

            if var workingCampaign = createdCampaign, workingCampaign.id == campaignId {
                workingCampaign.provisionStatus = state.provisionStatus
                workingCampaign.provisionSource = state.provisionSource
                workingCampaign.provisionPhase = state.provisionPhase
                workingCampaign.addressesReadyAt = state.addressesReadyAt
                workingCampaign.mapReadyAt = state.mapReadyAt
                workingCampaign.optimizedAt = state.optimizedAt
                preserveCurrentDetails(in: &workingCampaign)
                store.update(workingCampaign)
                createdCampaign = workingCampaign
            }

            await markCampaignReadyToOpen(
                campaignId: campaignId,
                campaignName: createdCampaign?.name ?? campaignName
            )
            startMapWarmupAfterReady(campaignId: campaignId)
            trace.end(status: "ready", fields: [
                "status": state.provisionStatus?.rawValue ?? "nil",
                "phase": state.provisionPhase?.rawValue ?? "nil"
            ])
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("⚠️ [CAMPAIGN DEBUG] Background provision monitor failed: \(error.localizedDescription)")
            #endif
            trace.end(status: "error", fields: [
                "error": error.localizedDescription
            ])
        }
    }

    @MainActor
    private func provisionCampaignInBackground(campaign: CampaignV2, polygon: [CLLocationCoordinate2D], regionCode: String?) async {
        let trace = PerfTrace.begin("campaign_create", "provision_campaign_background", fields: [
            "campaign": campaign.id.uuidString,
            "points": polygon.count,
            "region": regionCode ?? "nil"
        ])
        var workingCampaign = campaign
        let geoJSON = polygonToGeoJSON(polygon)

        do {
            let boundaryTrace = PerfTrace.begin("campaign_create", "update_territory_boundary", fields: [
                "campaign": campaign.id.uuidString,
                "points": polygon.count,
                "region": regionCode ?? "nil"
            ])
            try await CampaignsAPI.shared.updateTerritoryBoundary(
                campaignId: campaign.id,
                polygonGeoJSON: geoJSON,
                regionCode: regionCode
            )
            boundaryTrace.end(status: "success")
            guard !Task.isCancelled else { return }
            provisionStatusText = CampaignProvisionMonitor.runningStatusText
            updateProvisionProgress(18)
            let provisionTrace = PerfTrace.begin("campaign_create", "provision_request", fields: [
                "campaign": campaign.id.uuidString,
                "waitUntilReady": false
            ])
            let provisionResponse = try await CampaignsAPI.shared.provisionCampaign(
                campaignId: campaign.id,
                waitForLinker: true,
                waitUntilReady: true
            )
            provisionTrace.end(status: "accepted_or_complete", fields: [
                "accepted": provisionResponse?.accepted ?? false,
                "status": provisionResponse?.provisionStatus?.rawValue ?? "nil",
                "phase": provisionResponse?.provisionPhase?.rawValue ?? "nil",
                "addresses": provisionResponse?.addressesSaved ?? 0,
                "buildings": provisionResponse?.buildingsSaved ?? 0
            ])
            guard !Task.isCancelled else { return }
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
                trace.end(status: "accepted_background_monitoring", fields: [
                    "status": provisionResponse?.provisionStatus?.rawValue ?? "nil",
                    "phase": provisionResponse?.provisionPhase?.rawValue ?? "nil"
                ])
                return
            }

            let needsProvisionWait = !isProvisionMapUsable(
                status: provisionResponse?.provisionStatus,
                phase: provisionResponse?.provisionPhase
            )
            var finalProvisionStatus = provisionResponse?.provisionStatus
            if needsProvisionWait {
                provisionStatusText = CampaignProvisionMonitor.runningStatusText
                let waitTrace = PerfTrace.begin("campaign_create", "wait_for_provision_ready", fields: [
                    "campaign": campaign.id.uuidString
                ])
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
                waitTrace.end(status: "complete", fields: [
                    "status": provisionState.provisionStatus?.rawValue ?? "nil",
                    "phase": provisionState.provisionPhase?.rawValue ?? "nil"
                ])
                guard !Task.isCancelled else { return }
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

            if finalProvisionStatus == .ready {
                let addressesSaved = provisionResponse?.addressesSaved ?? workingCampaign.totalFlyers
                let buildingsSaved = provisionResponse?.buildingsSaved ?? 0
                print("🗺️ [CAMPAIGN DEBUG] Provision result: addresses=\(addressesSaved), buildings=\(buildingsSaved)")
                workingCampaign.totalFlyers = max(workingCampaign.totalFlyers, addressesSaved)
                preserveCurrentDetails(in: &workingCampaign)
                store.update(workingCampaign)
                createdCampaign = workingCampaign

                guard !Task.isCancelled else { return }
                await markCampaignReadyToOpen(
                    campaignId: campaign.id,
                    campaignName: workingCampaign.name
                )
                startMapWarmupAfterReady(campaignId: campaign.id)
                trace.end(status: "ready", fields: [
                    "addresses": addressesSaved,
                    "buildings": buildingsSaved
                ])
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
                trace.end(status: "not_ready", fields: [
                    "status": finalProvisionStatus?.rawValue ?? "unknown"
                ])
            }
        } catch {
            guard !Task.isCancelled else { return }
            if let message = CampaignsAPI.campaignHomeLimitMessage(from: error) {
                handleCampaignHomeLimitFailure(
                    campaign: campaign,
                    polygon: polygon,
                    regionCode: regionCode,
                    code: CampaignsAPI.campaignHomeLimitCode(from: error),
                    message: message
                )
                trace.end(status: "home_limit", fields: [
                    "error": message
                ])
            } else if isDiamondGeometryReadinessError(error) {
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
                trace.end(status: "geometry_warmup", fields: [
                    "error": error.localizedDescription
                ])
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
                trace.end(status: "error", fields: [
                    "error": error.localizedDescription
                ])
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
    private func markCampaignReadyToOpen(campaignId: UUID, campaignName: String) async {
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

        if detailsSaved {
            await openCreatedCampaign()
        } else {
            startCampaignMapBundlePrewarmIfNeeded(campaignId: campaignId)
        }
    }

    @MainActor
    private func startCampaignMapBundlePrewarmIfNeeded(campaignId: UUID) {
        guard mapBundlePrewarmCampaignId != campaignId || mapBundlePrewarmTask == nil else { return }
        mapBundlePrewarmTask?.cancel()
        mapBundlePrewarmCampaignId = campaignId
        mapBundlePrewarmTask = Task {
            await prewarmCampaignMapBundleForOpen(campaignId: campaignId)
            await MainActor.run {
                if mapBundlePrewarmCampaignId == campaignId {
                    mapBundlePrewarmTask = nil
                }
            }
        }
    }

    @MainActor
    private func prewarmCampaignMapBundleForOpen(campaignId: UUID) async {
        let campaignIdString = campaignId.uuidString
        let trace = PerfTrace.begin("campaign_create", "prewarm_campaign_map_bundle", fields: [
            "campaign": campaignIdString
        ])

        if let cachedBundle = await CampaignRepository.shared.getCampaignMapBundle(campaignId: campaignIdString),
           !cachedBundle.buildings.features.isEmpty || !cachedBundle.addresses.features.isEmpty || !cachedBundle.parcels.features.isEmpty {
            trace.end(status: "local_bundle_ready", fields: [
                "buildings": cachedBundle.buildings.features.count,
                "addresses": cachedBundle.addresses.features.count,
                "parcels": cachedBundle.parcels.features.count
            ])
            return
        }

        await MapFeaturesService.shared.fetchAllCampaignFeatures(campaignId: campaignIdString, forceRefresh: false)
        trace.end(status: "fetched", fields: [
            "buildings": MapFeaturesService.shared.buildings?.features.count ?? 0,
            "addresses": MapFeaturesService.shared.addresses?.features.count ?? 0,
            "parcels": MapFeaturesService.shared.parcels?.features.count ?? 0
        ])
    }

    @MainActor
    private func startMapWarmupAfterReady(campaignId: UUID) {
        MapFeaturesService.shared.beginDiamondManifestPrewarm(
            campaignId: campaignId.uuidString,
            timeoutSeconds: 90
        )
        print("💎 [CAMPAIGN DEBUG] Diamond/Bedrock geometry will warm while the campaign map opens")
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
            ("EC", 22.7, -34.4, 30.2, -30.0),
            ("FS", 24.0, -30.8, 29.8, -26.6),
            ("GP", 27.1, -26.9, 29.1, -25.1),
            ("KZN", 28.5, -31.2, 32.9, -26.8),
            ("LP", 26.4, -25.6, 32.0, -22.1),
            ("MP", 28.4, -27.5, 32.0, -24.6),
            ("NC", 16.4, -32.9, 25.9, -24.7),
            ("NW", 22.6, -28.1, 28.3, -24.6),
            ("WC", 17.7, -35.0, 24.3, -30.3),
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
        provisionStatusText = "Opening campaign map..."
        uiState.selectCampaign(
            id: campaign.id,
            name: campaign.name,
            boundaryCoordinates: boundaryCoordinates
        )
        uiState.selectedTabIndex = 1
        dismiss()
        Task {
            await CampaignDownloadService.shared.refreshMapAssetReadiness(campaignId: campaign.id.uuidString)
        }
    }
}

extension NewCampaignScreen {
    static func featureCollectionHasLinkedAddressIdentity(_ collection: GeoJSONFeatureCollection) -> Bool {
        collection.features.contains { feature in
            hasLinkedAddressIdentity(in: feature.properties["address_id"]?.value) ||
                hasLinkedAddressIdentity(in: feature.properties["address_ids"]?.value)
        }
    }

    private static func hasLinkedAddressIdentity(in value: Any?) -> Bool {
        switch value {
        case let string as String:
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let uuid as UUID:
            return !uuid.uuidString.isEmpty
        case let strings as [String]:
            return strings.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case let uuids as [UUID]:
            return !uuids.isEmpty
        case let values as [AnyCodable]:
            return values.contains { hasLinkedAddressIdentity(in: $0.value) }
        case let values as [Any]:
            return values.contains { hasLinkedAddressIdentity(in: $0) }
        default:
            return false
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
