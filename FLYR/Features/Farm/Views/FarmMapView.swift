import SwiftUI
import CoreLocation
import MapboxMaps
import Combine

struct FarmMapView: View {
    let farm: Farm
    let addresses: [CampaignAddressViewRow]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var uiState: AppUIState
    @StateObject private var viewModel: FarmMapViewModel
    @State private var displayMode: DisplayMode = .buildings
    @State private var mapView: MapView?
    @State private var layerManager: MapLayerManager?
    @State private var mapObservers: [AnyCancelable] = []
    @State private var hasFlownToFarm = false
    @State private var selectedBuilding: BuildingProperties?
    @State private var selectedAddress: MapLayerManager.AddressTapResult?
    @State private var selectedAddressIdForCard: UUID?
    @State private var showLocationCard = false
    @State private var addressStatuses: [UUID: AddressStatus] = [:]
    @State private var resolvedAddressIdsByBuilding: [String: [UUID]] = [:]

    init(farm: Farm, addresses: [CampaignAddressViewRow]) {
        self.farm = farm
        self.addresses = addresses
        _viewModel = StateObject(wrappedValue: FarmMapViewModel(farm: farm, addresses: addresses))
    }

    private var polygon: [CLLocationCoordinate2D] {
        farm.polygonCoordinates ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                CampaignMapboxMapViewRepresentable(
                    preferredSize: geometry.size,
                    useDarkStyle: colorScheme == .dark,
                    sessionLocation: nil,
                    sessionHeadingState: .unavailable,
                    showSessionPuck: false,
                    onMapReady: { map in
                        if self.mapView !== map {
                            self.mapView = map
                            setupMap(map)
                        }
                    },
                    onTap: { point in
                        handleTap(at: point)
                    },
                    onLongPress: { _ in }
                )
                .ignoresSafeArea()

                HStack(alignment: .top, spacing: 0) {
                    BuildingCircleToggle(mode: $displayMode) { _ in
                        updateMapData()
                    }
                    Spacer(minLength: 8)
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .safeAreaPadding(.top, 48)
                .safeAreaPadding(.leading, 4)
                .safeAreaPadding(.trailing, 4)

                VStack {
                    Spacer()

                    if showLocationCard {
                        locationCardOverlay(bottomInset: 20)
                            .padding(.horizontal, 12)
                    } else if let defaultCampaignId = defaultCampaignId {
                        openCampaignToolsButton(campaignId: defaultCampaignId, title: "Open Campaign Tools")
                            .padding(.horizontal, 12)
                            .padding(.bottom, 20)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadBuildings()
            updateMapData()
        }
        .onChange(of: viewModel.renderVersion) { _, _ in
            updateMapData()
        }
        .onChange(of: addresses.map(\.id)) { _, _ in
            viewModel.updateAddresses(addresses)
        }
    }

    private func setupMap(_ map: MapView) {
        let manager = MapLayerManager(mapView: map)
        manager.includeBuildingsLayer = true
        manager.includeAddressesLayer = true
        manager.showRoadOverlay = false
        layerManager = manager

        map.ornaments.options.scaleBar.visibility = .hidden
        map.ornaments.options.compass.visibility = .hidden

        mapObservers.removeAll()

        let styleLoaded = map.mapboxMap.onStyleLoaded.observe { _ in
            Self.removeStyleBuildingLayers(map: map)
            manager.setupLayers()
            updateMapData()
            fitMapToFarmIfNeeded(map: map, force: true)
        }

        let cameraChanged = map.mapboxMap.onCameraChanged.observe { _ in
            updateLayerVisibility()
        }

        mapObservers = [styleLoaded, cameraChanged]
    }

    private func updateMapData() {
        guard let manager = layerManager else { return }

        manager.updateBuildings(viewModel.buildingsData)
        manager.updateAddressNumberLabels(
            addresses: viewModel.addressFeatures,
            buildings: viewModel.buildingFeatures,
            orderedAddressIdsByBuilding: resolvedAddressIdsByBuilding
        )

        if let addressesData = viewModel.addressesData {
            manager.updateAddresses(addressesData)
        } else {
            manager.updateAddressesFromBuildingCentroids(buildingGeoJSONData: viewModel.buildingsData)
        }

        updateLayerVisibility()

        applyLoadedStatusesToMap()

        if let mapView {
            fitMapToFarmIfNeeded(map: mapView)
        }
    }

    private func updateLayerVisibility() {
        guard let manager = layerManager else { return }
        guard let map = mapView?.mapboxMap else { return }

        let hasBuildingsLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsLayerId })
        let hasTownhomeOverlayLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.townhomeOverlayLayerId })
        let hasAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressesLayerId })

        switch displayMode {
        case .buildings:
            manager.includeBuildingsLayer = true
            manager.includeAddressesLayer = false
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(viewModel.buildingFeatures.isEmpty ? .none : .visible)
                }
            }
            if hasTownhomeOverlayLayer {
                try? map.updateLayer(withId: MapLayerManager.townhomeOverlayLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.none)
                }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.none)
                }
            }
            manager.updateAddressNumberLabelVisibility(isVisible: shouldShowAddressNumberLabels())

        case .addresses:
            manager.includeBuildingsLayer = false
            manager.includeAddressesLayer = true
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.none)
                }
            }
            if hasTownhomeOverlayLayer {
                try? map.updateLayer(withId: MapLayerManager.townhomeOverlayLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.none)
                }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.visible)
                }
            }
            manager.updateAddressNumberLabelVisibility(isVisible: shouldShowAddressNumberLabels())
            if let mapView, mapView.mapboxMap.cameraState.zoom < 16.2 {
                mapView.camera.ease(
                    to: CameraOptions(
                        center: mapView.mapboxMap.cameraState.center,
                        zoom: 16.2,
                        bearing: mapView.mapboxMap.cameraState.bearing,
                        pitch: mapView.mapboxMap.cameraState.pitch
                    ),
                    duration: 0.35
                )
            }
        }
    }

    private func shouldShowAddressNumberLabels() -> Bool {
        guard let cameraState = mapView?.mapboxMap.cameraState else { return false }
        return cameraState.pitch <= 60
    }

    private var defaultCampaignId: UUID? {
        let ids = Set(addresses.map(\.campaignId))
        guard ids.count == 1 else { return nil }
        return ids.first
    }

    private func handleTap(at point: CGPoint) {
        guard let manager = layerManager else { return }

        switch displayMode {
        case .buildings:
            manager.getBuildingAt(point: point) { building in
                if let building {
                    presentBuildingSelection(building, tappedPoint: point)
                    return
                }

                manager.getAddressAt(point: point) { address in
                    guard let address else { return }
                    presentAddressSelection(address)
                }
            }
        case .addresses:
            manager.getAddressAt(point: point) { address in
                if let address {
                    presentAddressSelection(address)
                    return
                }

                manager.getBuildingAt(point: point) { building in
                    guard let building else { return }
                    presentBuildingSelection(building, tappedPoint: point)
                }
            }
        }
    }

    private func presentBuildingSelection(_ building: BuildingProperties, tappedPoint: CGPoint? = nil) {
        selectedBuilding = building
        selectedAddress = resolveAddressForBuilding(building: building, tappedPoint: tappedPoint)
        selectedAddressIdForCard = nil
        withAnimation { showLocationCard = true }
    }

    private func presentAddressSelection(_ address: MapLayerManager.AddressTapResult) {
        selectedAddress = address
        selectedAddressIdForCard = address.addressId
        let gersIdString = address.buildingGersId ?? address.gersId ?? ""
        if !gersIdString.isEmpty,
           let match = viewModel.buildingFeatures.first(where: {
               $0.properties.buildingIdentifierCandidates.contains(where: {
                   $0.caseInsensitiveCompare(gersIdString) == .orderedSame
               }) || ($0.id?.caseInsensitiveCompare(gersIdString) == .orderedSame)
           }) {
            selectedBuilding = match.properties
        } else {
            selectedBuilding = nil
        }
        withAnimation { showLocationCard = true }
    }

    private func resolveAddress(for tappedAddress: MapLayerManager.AddressTapResult) -> CampaignAddressViewRow? {
        let tappedId = tappedAddress.addressId.uuidString.lowercased()
        if let exact = addresses.first(where: { $0.id.uuidString.lowercased() == tappedId }) {
            return exact
        }

        let tappedFormatted = normalizeAddressText(tappedAddress.formatted)
        if !tappedFormatted.isEmpty,
           let formattedMatch = addresses.first(where: { normalizeAddressText($0.formatted) == tappedFormatted }) {
            return formattedMatch
        }

        let tappedHouse = normalizeHouseNumber(tappedAddress.houseNumber)
        if !tappedHouse.isEmpty,
           let houseMatch = addresses.first(where: { normalizeHouseNumber($0.houseNumber) == tappedHouse }) {
            return houseMatch
        }

        return nil
    }

    private func resolveAddressForBuilding(building: BuildingProperties, tappedPoint: CGPoint? = nil) -> MapLayerManager.AddressTapResult? {
        if let addrId = UUID(uuidString: building.id.trimmingCharacters(in: .whitespacesAndNewlines)),
           let featureMatch = viewModel.addressFeatures.first(where: {
               let featureId = (($0.properties.id ?? $0.id) ?? "").lowercased()
               return featureId == addrId.uuidString.lowercased()
           }),
           let resolved = addressTapResult(from: featureMatch) {
            return resolved
        }

        if let addressId = building.addressId?.lowercased(),
           let exact = addresses.first(where: { $0.id.uuidString.lowercased() == addressId }) {
            return addressTapResult(from: exact)
        }

        if let addressId = building.addressId?.lowercased(),
           let featureMatch = viewModel.addressFeatures.first(where: {
               let featureId = (($0.properties.id ?? $0.id) ?? "").lowercased()
               return featureId == addressId
           }),
           let resolved = addressTapResult(from: featureMatch) {
            return resolved
        }

        let buildingAddress = normalizeAddressText(building.addressText)
        if !buildingAddress.isEmpty,
           let formattedMatch = addresses.first(where: { normalizeAddressText($0.formatted) == buildingAddress }) {
            return addressTapResult(from: formattedMatch)
        }

        let buildingHouse = normalizeHouseNumber(building.houseNumber)
        if !buildingHouse.isEmpty {
            let houseMatches = addresses.filter { normalizeHouseNumber($0.houseNumber) == buildingHouse }
            if houseMatches.count == 1 {
                return addressTapResult(from: houseMatches[0])
            }
            let normalizedStreetName = normalizeAddressText(building.streetName)
            if !normalizedStreetName.isEmpty,
               let streetNameMatch = houseMatches.first(where: {
                   normalizeAddressText(streetOnly(from: $0.formatted)) == normalizedStreetName
               }) {
                return addressTapResult(from: streetNameMatch)
            }
            if let addressText = building.addressText {
                let normalizedStreet = normalizeAddressText(streetOnly(from: addressText))
                if let streetMatch = houseMatches.first(where: { normalizeAddressText(streetOnly(from: $0.formatted)) == normalizedStreet }) {
                    return addressTapResult(from: streetMatch)
                }
            }
            return houseMatches.first.flatMap(addressTapResult(from:))
        }

        let buildingIds = Set(
            [building.gersId, building.buildingId, building.id]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        if !buildingIds.isEmpty,
           let featureMatch = viewModel.addressFeatures.first(where: { feature in
               let candidates = [
                   feature.properties.buildingGersId,
                   feature.properties.gersId
               ]
               .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
               return candidates.contains { buildingIds.contains($0) }
           }),
           let resolved = addressTapResult(from: featureMatch) {
            return resolved
        }

        if !buildingAddress.isEmpty,
           let featureMatch = viewModel.addressFeatures.first(where: { feature in
               let formatted = normalizeAddressText(feature.properties.formatted)
               guard !formatted.isEmpty else { return false }
               return formatted.contains(buildingAddress) || buildingAddress.contains(formatted)
           }),
           let resolved = addressTapResult(from: featureMatch) {
            return resolved
        }

        if let tappedPoint,
           let nearestByTap = nearestAddress(to: tappedPoint) {
            return nearestByTap
        }

        return nil
    }

    private func addressTapResult(from feature: AddressFeature) -> MapLayerManager.AddressTapResult? {
        let idString = feature.properties.id ?? feature.id ?? ""
        guard let uuid = UUID(uuidString: idString) else { return nil }
        let formatted = nonEmptyAddressText(
            formatted: feature.properties.formatted,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName
        ) ?? "Address"
        return MapLayerManager.AddressTapResult(
            addressId: uuid,
            formatted: formatted,
            gersId: feature.properties.gersId,
            buildingGersId: feature.properties.buildingGersId,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName,
            source: feature.properties.source
        )
    }

    private func addressTapResult(from address: CampaignAddressViewRow) -> MapLayerManager.AddressTapResult {
        MapLayerManager.AddressTapResult(
            addressId: address.id,
            formatted: address.formatted,
            gersId: nil,
            buildingGersId: nil,
            houseNumber: address.houseNumber,
            streetName: streetOnly(from: address.formatted),
            source: address.source
        )
    }

    private func nonEmptyAddressText(formatted: String?, houseNumber: String?, streetName: String?) -> String? {
        let formattedValue = formatted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !formattedValue.isEmpty {
            return formattedValue
        }
        let house = houseNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let street = streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(house) \(street)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private func nearestAddress(to point: CGPoint, maxDistanceMeters: CLLocationDistance = 45) -> MapLayerManager.AddressTapResult? {
        guard let mapView else { return nil }
        let tappedCoordinate = mapView.mapboxMap.coordinate(for: point)
        let tappedLocation = CLLocation(latitude: tappedCoordinate.latitude, longitude: tappedCoordinate.longitude)

        var bestMatch: CampaignAddressViewRow?
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        for address in addresses {
            let candidate = CLLocation(
                latitude: address.geom.coordinate.latitude,
                longitude: address.geom.coordinate.longitude
            )
            let distance = tappedLocation.distance(from: candidate)
            if distance < bestDistance {
                bestDistance = distance
                bestMatch = address
            }
        }

        guard bestDistance <= maxDistanceMeters else { return nil }
        return bestMatch.map(addressTapResult(from:))
    }

    private func normalizeAddressText(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizeHouseNumber(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func streetOnly(from full: String) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = trimmed.firstIndex(of: ",") {
            return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    @ViewBuilder
    private func locationCardOverlay(bottomInset: CGFloat) -> some View {
        if showLocationCard,
           let building = selectedBuilding,
           let campId = selectedAddress.flatMap({ campaignIdForAddress($0.addressId) }) ?? defaultCampaignId {
            let gersIdString = building.canonicalBuildingIdentifier ?? building.id
            let resolvedAddrId = selectedAddress?.addressId ?? building.addressId.flatMap(UUID.init(uuidString:))
            let resolvedAddrText = nonEmptyAddressText(
                formatted: selectedAddress?.formatted,
                houseNumber: selectedAddress?.houseNumber,
                streetName: selectedAddress?.streetName
            ) ?? nonEmptyAddressText(
                formatted: building.addressText,
                houseNumber: building.houseNumber,
                streetName: building.streetName
            )
            LocationCardView(
                gersId: gersIdString,
                campaignId: campId,
                sessionId: nil,
                addressId: resolvedAddrId,
                addressText: resolvedAddrText,
                preferredAddressId: selectedAddressIdForCard,
                buildingSource: building.source,
                addressSource: selectedAddress?.source,
                addressStatuses: addressStatuses,
                onSelectAddress: { setSelectedAddressForCard($0) },
                onAddressesResolved: { ids in
                    let key = normalizedBuildingId(gersIdString)
                    guard !key.isEmpty else { return }
                    resolvedAddressIdsByBuilding[key] = ids
                },
                onClose: {
                    showLocationCard = false
                    selectedBuilding = nil
                    selectedAddress = nil
                    selectedAddressIdForCard = nil
                },
                onStatusUpdated: { addressId, status in
                    handleLocationCardStatusUpdated(
                        gersId: gersIdString,
                        addressId: addressId,
                        status: status
                    )
                }
            )
            .id("farm-building-\(gersIdString)-\(resolvedAddrId?.uuidString ?? "")")
            .padding(.bottom, bottomInset)
            .transition(.move(edge: .bottom))
        } else if showLocationCard,
                  let address = selectedAddress,
                  let campId = campaignIdForAddress(address.addressId) ?? defaultCampaignId {
            let gersIdString = address.buildingGersId ?? address.gersId ?? ""
            LocationCardView(
                gersId: gersIdString,
                campaignId: campId,
                sessionId: nil,
                addressId: address.addressId,
                addressText: nonEmptyAddressText(
                    formatted: address.formatted,
                    houseNumber: address.houseNumber,
                    streetName: address.streetName
                ),
                preferredAddressId: selectedAddressIdForCard,
                buildingSource: selectedBuilding?.source,
                addressSource: address.source,
                addressStatuses: addressStatuses,
                onSelectAddress: { setSelectedAddressForCard($0) },
                onAddressesResolved: { ids in
                    let key = normalizedBuildingId(gersIdString)
                    guard !key.isEmpty else { return }
                    resolvedAddressIdsByBuilding[key] = ids
                },
                onClose: {
                    showLocationCard = false
                    selectedBuilding = nil
                    selectedAddress = nil
                    selectedAddressIdForCard = nil
                },
                onStatusUpdated: { addressId, status in
                    handleLocationCardStatusUpdated(
                        gersId: gersIdString,
                        addressId: addressId,
                        status: status
                    )
                }
            )
            .id("farm-address-\(address.addressId.uuidString)")
            .padding(.bottom, bottomInset)
            .transition(.move(edge: .bottom))
        }
    }

    private func setSelectedAddressForCard(_ addressId: UUID?) {
        selectedAddressIdForCard = addressId

        guard let addressId else {
            selectedAddress = nil
            return
        }

        selectedAddress = nil
        let targetId = addressId.uuidString.lowercased()
        if let feature = viewModel.addressFeatures.first(where: {
            (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
        }) {
            selectedAddress = addressTapResult(from: feature)
        }
    }

    private func campaignIdForAddress(_ addressId: UUID) -> UUID? {
        addresses.first(where: { $0.id == addressId })?.campaignId
    }

    private func handleLocationCardStatusUpdated(gersId: String, addressId: UUID, status: AddressStatus) {
        addressStatuses[addressId] = status

        let layerStatus = status.mapLayerStatus
        layerManager?.updateAddressState(
            addressId: addressId.uuidString,
            status: layerStatus,
            scansTotal: 0
        )

        let normalizedGersId = normalizedBuildingId(gersId)
        guard !normalizedGersId.isEmpty else { return }

        let buildingStatus = computeBuildingLayerStatus(
            gersId: normalizedGersId,
            addressIds: addressIdsForBuilding(gersId: normalizedGersId)
        )
        layerManager?.updateBuildingState(
            gersId: normalizedGersId,
            status: buildingStatus,
            scansTotal: 0
        )
    }

    private func addressIdsForBuilding(gersId: String) -> [UUID] {
        let normalizedGersId = normalizedBuildingId(gersId)
        if let resolvedIds = resolvedAddressIdsByBuilding[normalizedGersId], !resolvedIds.isEmpty {
            return resolvedIds
        }

        let matchedFeatureIds = viewModel.addressFeatures
            .filter { feature in
                let candidates = [
                    feature.properties.buildingGersId,
                    feature.properties.gersId
                ]
                .compactMap(normalizedBuildingId)
                return candidates.contains(normalizedGersId)
            }
            .compactMap { feature -> UUID? in
                guard let id = feature.properties.id ?? feature.id else { return nil }
                return UUID(uuidString: id)
            }

        if !matchedFeatureIds.isEmpty {
            let deduped = Array(NSOrderedSet(array: matchedFeatureIds)) as? [UUID] ?? matchedFeatureIds
            resolvedAddressIdsByBuilding[normalizedGersId] = deduped
            return deduped
        }

        if let matchedRows = addressRowsForBuilding(gersId: normalizedGersId), !matchedRows.isEmpty {
            let ids = matchedRows.map(\.id)
            resolvedAddressIdsByBuilding[normalizedGersId] = ids
            return ids
        }

        if let selectedAddress,
           normalizedBuildingId(selectedAddress.buildingGersId ?? selectedAddress.gersId) == normalizedGersId {
            return [selectedAddress.addressId]
        }

        return []
    }

    private func computeBuildingLayerStatus(gersId: String, addressIds: [UUID]) -> String {
        guard !addressIds.isEmpty else { return "not_visited" }
        let statuses = addressIds.compactMap { addressStatuses[$0] }
        guard !statuses.isEmpty else { return "not_visited" }

        let allVisited = statuses.allSatisfy {
            switch $0 {
            case .delivered, .noAnswer, .doNotKnock, .futureSeller:
                return true
            default:
                return false
            }
        }
        if allVisited {
            let allDoNotKnock = statuses.allSatisfy { $0 == .doNotKnock }
            return allDoNotKnock ? "do_not_knock" : "visited"
        }

        let anyHot = statuses.contains {
            switch $0 {
            case .talked, .appointment, .hotLead:
                return true
            default:
                return false
            }
        }
        if anyHot { return "hot" }

        let anyVisited = statuses.contains {
            switch $0 {
            case .delivered, .noAnswer, .doNotKnock, .futureSeller:
                return true
            default:
                return false
            }
        }
        return anyVisited ? "visited" : "not_visited"
    }

    private func normalizedBuildingId(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func addressRowsForBuilding(gersId: String) -> [CampaignAddressViewRow]? {
        let normalizedGersId = normalizedBuildingId(gersId)
        guard !normalizedGersId.isEmpty else { return nil }

        let matchedBySelectedBuildingAddress = selectedBuilding
            .flatMap { building -> [CampaignAddressViewRow]? in
                let buildingAddress = normalizeAddressText(building.addressText)
                guard !buildingAddress.isEmpty else { return nil }
                let matches = addresses.filter { normalizeAddressText($0.formatted) == buildingAddress }
                return matches.isEmpty ? nil : matches
            }

        if let matchedBySelectedBuildingAddress, !matchedBySelectedBuildingAddress.isEmpty {
            return matchedBySelectedBuildingAddress
        }

        let matchedBySelectedAddress = selectedAddress
            .flatMap { tapped -> [CampaignAddressViewRow]? in
                guard normalizedBuildingId(tapped.buildingGersId ?? tapped.gersId) == normalizedGersId else {
                    return nil
                }
                let matches = addresses.filter { $0.id == tapped.addressId }
                return matches.isEmpty ? nil : matches
            }

        return matchedBySelectedAddress
    }

    private func applyLoadedStatusesToMap(forceRefresh: Bool = false) {
        guard layerManager != nil else { return }

        let campaignIds = Array(Set(addresses.map(\.campaignId)))
        guard !campaignIds.isEmpty else { return }

        Task {
            for campaignId in campaignIds {
                do {
                    let statuses = try await VisitsAPI.shared.fetchStatuses(
                        campaignId: campaignId,
                        forceRefresh: forceRefresh
                    )
                    await MainActor.run {
                        mergeStatusesIntoMap(statuses)
                    }
                } catch {
                    print("⚠️ [FarmMapView] Failed to load statuses for campaign \(campaignId.uuidString): \(error)")
                }
            }
        }
    }

    @MainActor
    private func mergeStatusesIntoMap(_ statuses: [UUID: AddressStatusRow]) {
        guard let manager = layerManager else { return }

        for (addressId, row) in statuses {
            let displayStatus = AddressStatus.preferredForDisplay(
                current: addressStatuses[addressId],
                incoming: row.status
            )
            addressStatuses[addressId] = displayStatus
            manager.updateAddressState(
                addressId: addressId.uuidString,
                status: displayStatus.mapLayerStatus,
                scansTotal: 0
            )
        }

        for building in viewModel.buildingFeatures {
            let buildingId = normalizedBuildingId(building.properties.canonicalBuildingIdentifier ?? building.id)
            guard !buildingId.isEmpty else { continue }

            let addressIds = addressIdsForBuilding(gersId: buildingId)
            let buildingStatus = computeBuildingLayerStatus(
                gersId: buildingId,
                addressIds: addressIds
            )
            manager.updateBuildingState(
                gersId: buildingId,
                status: buildingStatus,
                scansTotal: building.properties.scansTotal
            )
        }
    }

    private func openCampaignToolsButton(campaignId: UUID, title: String) -> some View {
        Button {
            let selectedAddressText = selectedAddress?.formatted
            uiState.selectCampaign(id: campaignId, name: streetOnly(from: selectedAddressText ?? farm.name))
            uiState.selectedTabIndex = 1
            dismiss()
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func fitMapToFarmIfNeeded(map: MapView, force: Bool = false) {
        guard force || !hasFlownToFarm else { return }
        let coordinates = mapCoordinates()
        guard !coordinates.isEmpty else { return }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = max(maxLat - minLat, maxLon - minLon)
        let computedZoom = zoomLevel(for: span)
        let zoom = displayMode == .addresses ? max(computedZoom, 16.2) : computedZoom

        map.camera.fly(
            to: CameraOptions(
                center: center,
                padding: nil,
                zoom: zoom,
                bearing: nil,
                pitch: 60
            ),
            duration: 0.8
        )
        hasFlownToFarm = true
    }

    private func mapCoordinates() -> [CLLocationCoordinate2D] {
        let addressCoordinates = addresses.map(\.geom.coordinate)
        if !addressCoordinates.isEmpty {
            return addressCoordinates
        }
        return polygon
    }

    private func zoomLevel(for span: Double) -> CGFloat {
        switch span {
        case ..<0.0015: return 17.2
        case ..<0.003: return 16.5
        case ..<0.006: return 15.8
        case ..<0.012: return 15.0
        case ..<0.025: return 14.2
        case ..<0.05: return 13.4
        default: return 12.6
        }
    }

    private static func removeStyleBuildingLayers(map: MapView) {
        let idsToRemove = map.mapboxMap.allLayerIdentifiers
            .map(\.id)
            .filter { $0.lowercased().contains("building") }
        for id in idsToRemove {
            try? map.mapboxMap.removeLayer(withId: id)
        }
    }
}

@MainActor
private final class FarmMapViewModel: ObservableObject {
    @Published private(set) var renderVersion = 0
    @Published private(set) var buildingFeatures: [BuildingFeature] = []
    @Published private(set) var buildingsData: Data?
    @Published private(set) var addressFeatures: [AddressFeature] = []
    @Published private(set) var addressesData: Data?

    private let farm: Farm
    private var addresses: [CampaignAddressViewRow]

    init(farm: Farm, addresses: [CampaignAddressViewRow]) {
        self.farm = farm
        self.addresses = addresses
        let data = Self.makeAddressesGeoJSONData(from: addresses)
        self.addressesData = data
        self.addressFeatures = Self.decodeAddressFeatures(from: data)
    }

    func updateAddresses(_ addresses: [CampaignAddressViewRow]) {
        self.addresses = addresses
        let data = Self.makeAddressesGeoJSONData(from: addresses)
        addressesData = data
        addressFeatures = Self.decodeAddressFeatures(from: data)
        renderVersion += 1
    }

    func loadBuildings() async {
        let addressIds = addresses.map(\.id)
        guard !addressIds.isEmpty || !(farm.polygon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
            buildingsData = nil
            buildingFeatures = []
            renderVersion += 1
            return
        }

        do {
            let collection: GeoJSONFeatureCollection
            if let polygonGeoJSON = farm.polygon?.trimmingCharacters(in: .whitespacesAndNewlines),
               !polygonGeoJSON.isEmpty {
                collection = try await BuildingsAPI.shared.fetchBuildingPolygons(polygonGeoJSON: polygonGeoJSON)
                print("✅ [FarmMapView] Loaded \(collection.features.count) polygon-scoped building features")
            } else {
                collection = try await BuildingsAPI.shared.fetchBuildingPolygons(addressIds: addressIds)
                print("ℹ️ [FarmMapView] Loaded \(collection.features.count) address-scoped building features (fallback)")
            }
            let polygonsOnly = GeoJSONFeatureCollection(
                features: collection.features.filter {
                    $0.geometry.type == "Polygon" || $0.geometry.type == "MultiPolygon"
                }
            )
            let data = try JSONEncoder().encode(polygonsOnly)
            buildingsData = data
            buildingFeatures = Self.decodeBuildingFeatures(from: data)
        } catch {
            buildingsData = nil
            buildingFeatures = []
            print("⚠️ [FarmMapView] Failed to load building polygons: \(error)")
        }

        renderVersion += 1
    }

    private static func makeAddressesGeoJSONData(from addresses: [CampaignAddressViewRow]) -> Data? {
        let features: [[String: Any]] = addresses.map { address in
            [
                "type": "Feature",
                "id": address.id.uuidString,
                "geometry": [
                    "type": "Point",
                    "coordinates": [
                        address.geom.coordinate.longitude,
                        address.geom.coordinate.latitude
                    ]
                ],
                "properties": [
                    "id": address.id.uuidString,
                    "formatted": address.formatted,
                    "house_number": address.houseNumber ?? "",
                    "source": address.source ?? "farm"
                ]
            ]
        }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]
        return try? JSONSerialization.data(withJSONObject: collection)
    }

    private static func decodeAddressFeatures(from data: Data?) -> [AddressFeature] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(AddressFeatureCollection.self, from: data))?.features ?? []
    }

    private static func decodeBuildingFeatures(from data: Data?) -> [BuildingFeature] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(BuildingFeatureCollection.self, from: data))?.features ?? []
    }
}
