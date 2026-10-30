#if DEBUG
import SwiftUI
import Combine
import MapboxMaps
import UIKit

/// Device-only verification using externally supplied, private canonical fixtures.
/// Does not write visits, contacts or campaign state to the backend.
struct CanonicalTileVerificationView: View {
    @StateObject private var controller = CanonicalTileVerificationController()
    var body: some View {
        VStack(spacing: 8) {
            Text(controller.message).font(.caption.monospaced()).accessibilityIdentifier("canonical-tile-result")
            CanonicalTileVerificationMap(controller: controller)
        }.padding(.top, 12)
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct CanonicalTileVerificationMap: UIViewRepresentable {
    let controller: CanonicalTileVerificationController
    func makeUIView(context: Context) -> MapView {
        MapboxOptions.accessToken = Config.mapboxAccessToken
        let map = MapView(frame: .zero, mapInitOptions: MapInitOptions(styleURI: nil, styleJSON: CanonicalTileVerificationController.style))
        Task { @MainActor in try? await Task.sleep(nanoseconds: 800_000_000); await controller.run(map) }
        return map
    }
    func updateUIView(_ uiView: MapView, context: Context) {}
}

@MainActor
private final class CanonicalTileVerificationController: ObservableObject {
    static let style = ##"{"version":8,"sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"#192331"}}]}"##
    @Published var message = "Preparing device comparison"
    private var ran = false
    private var report: [[String: Any]] = []
    private var errorSubscription: AnyCancelable?
    private var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CanonicalTileVerification") }
    private struct Target: Decodable {
        let address: String; let building: String; let coordinate: [Double]; let buildingCoordinate: [Double]
        func location(addressMode: Bool) -> CLLocationCoordinate2D {
            let point = addressMode ? coordinate : buildingCoordinate
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
    }
    private struct Fixture: Decodable { let bundle: CanonicalCampaignMapBundle; let tiles: CanonicalCampaignTiles; let targets: [Target] }
    private enum Failure: Error { case missingTargets, timeout(String), wrongState(String), missingHit(String), pixelUnchanged, neighbourChanged }

    func run(_ map: MapView) async {
        guard !ran else { return }; ran = true
        UIApplication.shared.isIdleTimerDisabled = true
        errorSubscription = map.mapboxMap.onMapLoadingError.observe { event in
            print("CANONICAL_TILE_MAP_ERROR \(event.message)")
        }
        do {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory.appendingPathComponent("fixture.json")))
            guard fixture.targets.count >= 2, let manifest = fixture.tiles.diamondManifest(campaignId: fixture.bundle.campaignId) else { throw Failure.missingTargets }
            guard CanonicalTileHTTP.shared.register(fixture.tiles, file: directory.appendingPathComponent("campaign.pmtiles")) else { throw Failure.missingTargets }
            let first = fixture.targets[0], second = fixture.targets[1]
            let compactData = try Data(contentsOf: directory.appendingPathComponent("bundle-v3.json"))
            let compact = try BuildingLinkService.decodeCompactCampaignMapBundle(compactData, campaignId: fixture.bundle.campaignId)
            var rejectedWrongCampaign = false
            do {
                _ = try BuildingLinkService.decodeCompactCampaignMapBundle(compactData, campaignId: "wrong-campaign")
            } catch { rejectedWrongCampaign = true }
            guard rejectedWrongCampaign else { throw Failure.missingTargets }
            guard compact.schema == "tiles-v3", compact.campaignId == fixture.bundle.campaignId,
                  compact.records.buildings.contains(where: { $0.id == first.building }),
                  compact.records.addresses.contains(where: { $0.id == first.address }),
                  compact.tiles.geometryPack != nil else { throw Failure.missingTargets }
            report.append(["phase": "compact_field_records", "result": "PASS", "buildings": compact.records.buildings.count,
                "addresses": compact.records.addresses.count, "parcels": compact.records.parcels.count])
            let exactPack = try CanonicalGeometryPack(url: directory.appendingPathComponent("canonical-geometry.wgp"))
            let index = try CanonicalCompactFieldIndex(campaign: compact, pack: exactPack)
            let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("canonical-cache-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: cacheRoot) }
            let cache = CanonicalCompactCampaignStore(root: cacheRoot)
            let packURL = directory.appendingPathComponent("canonical-geometry.wgp")
            _ = try await cache.save(data: compactData, campaignId: compact.campaignId,
                userId: "test-user", workspaceId: "test-workspace", geometryURL: packURL)
            let cached = try await cache.load(campaignId: compact.campaignId, userId: "test-user",
                workspaceId: "test-workspace", geometryURL: packURL)
            let otherUser = try await cache.load(campaignId: compact.campaignId, userId: "other-user",
                workspaceId: "test-workspace", geometryURL: packURL)
            let otherWorkspace = try await cache.load(campaignId: compact.campaignId, userId: "test-user",
                workspaceId: "other-workspace", geometryURL: packURL)
            guard cached?.building(first.building) != nil, otherUser == nil, otherWorkspace == nil else { throw Failure.missingTargets }
            var rejectedMissingGeometry = false
            do {
                _ = try await cache.save(data: compactData, campaignId: compact.campaignId,
                    userId: "test-user", workspaceId: "test-workspace", geometryURL: cacheRoot.appendingPathComponent("missing.wgp"))
            } catch { rejectedMissingGeometry = true }
            guard rejectedMissingGeometry, try await cache.load(campaignId: compact.campaignId, userId: "test-user",
                workspaceId: "test-workspace", geometryURL: packURL)?.address(first.address) != nil else { throw Failure.missingTargets }
            report.append(["phase": "compact_offline_cache", "result": "PASS"])
            guard index.building(first.building) != nil, index.address(first.address) != nil,
                  index.addressIds(forBuilding: first.building).contains(first.address),
                  let buildingShape = try index.geometry(featureId: "building:\(first.building)"),
                  let addressShape = try index.geometry(featureId: "address:\(first.address)") else { throw Failure.missingTargets }
            guard case .polygon(let rings) = buildingShape, !rings.isEmpty,
                  case .point(let xy) = addressShape, xy.count >= 2,
                  abs(xy[0] - first.coordinate[0]) < 1e-10, abs(xy[1] - first.coordinate[1]) < 1e-10 else {
                throw Failure.missingTargets
            }
            report.append(["phase": "exact_binary_geometry", "result": "PASS", "records": exactPack.count])
            guard let exactBuilding = try index.exactBuildingFeature(id: first.building),
                  let originalBuilding = fixture.bundle.buildings.features.first(where: {
                      $0.properties.buildingIdentifierCandidates.contains(first.building) || $0.id == first.building
                  }),
                  exactBuilding.geometry.type == originalBuilding.geometry.type,
                  exactBuilding.geometry.asPolygon == originalBuilding.geometry.asPolygon,
                  exactBuilding.geometry.asMultiPolygon == originalBuilding.geometry.asMultiPolygon,
                  exactBuilding.properties.canonicalBuildingIdentifier == originalBuilding.properties.canonicalBuildingIdentifier else {
                throw Failure.missingTargets
            }
            report.append(["phase": "field_building_tap_geometry", "result": "PASS"])
            guard let compactAddress = index.addressFeature(id: first.address.uppercased()),
                  let originalAddress = fixture.bundle.addresses.features.first(where: {
                      ($0.properties.id ?? $0.id)?.lowercased() == first.address.lowercased()
                  }), compactAddress.geometry.asPoint == originalAddress.geometry.asPoint,
                  compactAddress.properties.formatted == originalAddress.properties.formatted,
                  compactAddress.properties.houseNumber == originalAddress.properties.houseNumber,
                  compactAddress.properties.streetName == originalAddress.properties.streetName else {
                throw Failure.missingTargets
            }
            report.append(["phase": "field_address_tap_metadata", "result": "PASS"])
            let snapshot = try index.fieldSnapshot()
            guard snapshot.buildings.features.count == compact.records.buildings.count,
                  snapshot.addresses.features.count == compact.records.addresses.count,
                  snapshot.parcels.features.count == compact.records.parcels.count,
                  snapshot.roads.features.count == compact.roadRecords.count,
                  let snapshotBuilding = snapshot.buildings.features.first(where: { $0.id == first.building }),
                  snapshotBuilding.geometry.asPolygon == exactBuilding.geometry.asPolygon,
                  snapshotBuilding.geometry.asMultiPolygon == exactBuilding.geometry.asMultiPolygon,
                  let snapshotAddress = snapshot.addresses.features.first(where: { $0.id == first.address }),
                  snapshotAddress.geometry.asPoint == compactAddress.geometry.asPoint else { throw Failure.missingTargets }
            report.append(["phase": "compact_field_snapshot", "result": "PASS", "buildings": snapshot.buildings.features.count,
                           "addresses": snapshot.addresses.features.count, "parcels": snapshot.parcels.features.count,
                           "roads": snapshot.roads.features.count])
            let oldTargets = CampaignTargetResolver.buildingTargets(from: fixture.bundle.buildings.features)
            let compactTargets = try CampaignTargetResolver.buildingTargets(from: compact.records.buildings, exactIndex: index)
            let oldById = Dictionary(uniqueKeysWithValues: oldTargets.map { ($0.id.lowercased(), $0) })
            guard compactTargets.count == oldTargets.count, compactTargets.allSatisfy({ target in
                guard let original = oldById[target.id.lowercased()] else { return false }
                return abs(original.coordinate.latitude - target.coordinate.latitude) < 1e-10 &&
                    abs(original.coordinate.longitude - target.coordinate.longitude) < 1e-10 &&
                    original.label == target.label && original.addressId == target.addressId &&
                    original.buildingId == target.buildingId && original.houseNumber == target.houseNumber &&
                    original.streetName == target.streetName
            }) else { throw Failure.missingTargets }
            let oldAddresses = CampaignTargetResolver.addressTargets(from: fixture.bundle.addresses.features)
            let compactAddresses = CampaignTargetResolver.addressTargets(from: compact.records.addresses)
            let oldAddressesById = Dictionary(uniqueKeysWithValues: oldAddresses.map { ($0.id, $0) })
            guard compactAddresses.count == oldAddresses.count, compactAddresses.allSatisfy({ target in
                guard let original = oldAddressesById[target.id] else { return false }
                return abs(original.coordinate.latitude - target.coordinate.latitude) < 1e-10 &&
                    abs(original.coordinate.longitude - target.coordinate.longitude) < 1e-10 &&
                    original.label == target.label && original.buildingId == target.buildingId &&
                    original.houseNumber == target.houseNumber && original.streetName == target.streetName
            }) else { throw Failure.missingTargets }
            report.append(["phase": "compact_session_targets", "result": "PASS", "homes": compactTargets.count,
                "addresses": compactAddresses.count])
            guard let linkedParcel = compact.records.parcels.first(where: {
                ([ $0.properties.addressId ].compactMap { $0 } + ($0.properties.addressIds ?? []))
                    .contains(where: { UUID(uuidString: $0) != nil })
            }), let linkedAddress = ([linkedParcel.properties.addressId].compactMap { $0 } +
                (linkedParcel.properties.addressIds ?? [])).compactMap(UUID.init(uuidString:)).first else {
                throw Failure.missingTargets
            }
            let resolvedParcels = try index.parcelAutoCompleteTargets(
                addressIdsByTargetId: ["test-target": [linkedAddress]], buildingIdsByTargetId: [:])
            let ambiguousParcels = try index.parcelAutoCompleteTargets(
                addressIdsByTargetId: ["test-target": [linkedAddress], "other-target": [linkedAddress]], buildingIdsByTargetId: [:])
            guard !resolvedParcels.isEmpty, ambiguousParcels.isEmpty else { throw Failure.missingTargets }
            report.append(["phase": "compact_parcel_target_mapping", "result": "PASS"])
            guard let originalParcel = fixture.bundle.parcels.features.first(where: { parcel in
                let id = [parcel.properties.parcelId, parcel.properties.externalId, parcel.id, parcel.properties.id]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                let normalized = id.map { UUID(uuidString: $0)?.uuidString.lowercased() ?? $0 }
                return normalized == linkedParcel.id
            }) else { throw Failure.missingTargets }
            let compactRings = CanonicalParcelFieldGeometry.rings(for: originalParcel, index: index)
            let existingRings = CanonicalParcelFieldGeometry.rings(for: originalParcel, index: nil)
            guard compactRings.count == existingRings.count,
                  zip(compactRings, existingRings).allSatisfy({ left, right in
                      left.count == right.count && zip(left, right).allSatisfy {
                          abs($0.latitude - $1.latitude) < 1e-10 && abs($0.longitude - $1.longitude) < 1e-10
                      }
                  }) else { throw Failure.missingTargets }
            report.append(["phase": "field_parcel_shape_parity", "result": "PASS"])
            map.mapboxMap.setCamera(to: CameraOptions(center: CLLocationCoordinate2D(latitude: (first.coordinate[1] + second.coordinate[1]) / 2,
                longitude: (first.coordinate[0] + second.coordinate[0]) / 2), zoom: 18, bearing: 0, pitch: 0))
            let buildingData = try JSONEncoder().encode(fixture.bundle.buildings)
            let addressData = try JSONEncoder().encode(fixture.bundle.addresses)
            var finalManager: MapLayerManager?
            // Verify the tiled path with a fresh style before checking scoped layers.
            for (round, tiled) in [true].enumerated() {
                message = "Run \(round + 1)/10: \(tiled ? "PMTiles" : "GeoJSON")"
                try await loadStyle(map)
                let manager = MapLayerManager(mapView: map)
                manager.setupBuildingsLayer(); manager.setupAddressesLayer(); manager.setupParcelsLayer()
                let started = CACurrentMediaTime()
                if tiled {
                    manager.setDiamondGeometryVisibility(buildings: true, addresses: false, addressNumbers: false, parcels: false)
                    manager.updateDiamondGeometry(manifest: manifest)
                } else {
                    manager.updateBuildings(buildingData)
                    manager.updateAddresses(addressData)
                    manager.setAddressExtrusionVisibility(isVisible: false)
                }
                let layer = tiled ? VectorTileDiamondGeometryProvider.buildingFillLayerId : MapLayerManager.buildingsLayerId
                try await waitForHit(map, layer: layer, target: first, isAddress: false, tiled: tiled)
                let elapsed = (CACurrentMediaTime() - started) * 1000
                report.append(["phase": "first_tappable", "renderer": tiled ? "pmtiles" : "geojson", "round": round, "milliseconds": elapsed])
                print("CANONICAL_TILE_BENCH renderer=\(tiled ? "pmtiles" : "geojson") firstTappableMs=\(elapsed)")
                finalManager = manager
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard let manager = finalManager else { throw Failure.missingTargets }
            // Exercise the same large-ID scope that the real campaign view can
            // apply after the local records arrive, not just an unfiltered tile.
            let scopePlan = try index.renderPlan(buildings: snapshot.buildings.features,
                                                 addresses: snapshot.addresses.features,
                                                 parcels: snapshot.parcels.features)
            print("CANONICAL_SCOPE_DIAGNOSTIC buildings=\(scopePlan.buildingIds.count) buildingEdits=\(scopePlan.buildingEdits.count) addresses=\(scopePlan.addressIds.count) addressEdits=\(scopePlan.addressEdits.count) parcels=\(scopePlan.parcelIds.count)")
            report.append(["phase": "scope_plan", "addresses": scopePlan.addressIds.count,
                           "targetPresent": scopePlan.addressIds.contains(first.address),
                           "addressEdits": scopePlan.addressEdits.count])
            manager.updateCanonicalTileScope(buildings: nil, addresses: [first.address], parcels: nil)
            manager.setDiamondGeometryVisibility(buildings: false, addresses: true, addressNumbers: false, parcels: false)
            manager.updateAddressModeZoomVisibility(isAddressMode: true)
            report.append(["phase": "scope_style", "filter": String(describing: map.mapboxMap.layerProperty(for: VectorTileDiamondGeometryProvider.addressCircleLayerId, property: "filter").value), "visibility": String(describing: map.mapboxMap.layerProperty(for: VectorTileDiamondGeometryProvider.addressCircleLayerId, property: "visibility").value), "target": first.address])
            try await waitForHit(map, layer: VectorTileDiamondGeometryProvider.addressCircleLayerId,
                                 target: first, isAddress: true, tiled: true)
            report.append(["phase": "single_address_scope", "result": "PASS"])
            guard !map.mapboxMap.layerExists(withId: VectorTileDiamondGeometryProvider.addressOverviewLayerId) else {
                throw Failure.wrongState("flat address overview layer")
            }
            for zoom in [14.0, 12.0] {
                map.mapboxMap.setCamera(to: CameraOptions(center: first.location(addressMode: true), zoom: zoom, pitch: 0))
                try await waitForHit(map, layer: VectorTileDiamondGeometryProvider.addressCircleLayerId,
                                     target: first, isAddress: true, tiled: true)
                report.append(["phase": "zoomed_out_cylinder", "zoom": zoom, "result": "PASS"])
            }
            map.mapboxMap.setCamera(to: CameraOptions(center: CLLocationCoordinate2D(latitude: (first.coordinate[1] + second.coordinate[1]) / 2,
                longitude: (first.coordinate[0] + second.coordinate[0]) / 2), zoom: 18, bearing: 0, pitch: 0))
            manager.updateCanonicalTileScope(buildings: nil, addresses: scopePlan.addressIds, parcels: nil)
            for addressMode in [false, true] {
                message = "Checking \(addressMode ? "address pin" : "individual home") colours"
                manager.setDiamondGeometryVisibility(buildings: !addressMode, addresses: addressMode, addressNumbers: false, parcels: false)
                manager.updateAddressModeZoomVisibility(isAddressMode: addressMode)
                let source = addressMode ? VectorTileDiamondGeometryProvider.addressSourceId : VectorTileDiamondGeometryProvider.buildingSourceId
                let sourceLayer = addressMode ? (manifest.sourceLayers?.addressCircles ?? "address_circles") : "buildings"
                let layer = addressMode ? VectorTileDiamondGeometryProvider.addressCircleLayerId : VectorTileDiamondGeometryProvider.buildingFillLayerId
                let id = addressMode ? first.address : first.building
                let neighbour = addressMode ? second.address : second.building
                manager.updateBuildingState(gersId: first.building, status: "not_visited", scansTotal: 0)
                manager.updateBuildingState(gersId: second.building, status: "not_visited", scansTotal: 0)
                manager.updateAddressState(addressId: first.address, status: "not_visited", scansTotal: 0)
                manager.updateAddressState(addressId: second.address, status: "not_visited", scansTotal: 0)
                try await waitForHit(map, layer: layer, target: first, isAddress: addressMode, tiled: true)
                if addressMode {
                    let hit = await withCheckedContinuation { continuation in
                        manager.getStrictAddressAt(point: map.mapboxMap.point(for: first.location(addressMode: true))) {
                            continuation.resume(returning: $0)
                        }
                    }
                    guard hit?.addressId.uuidString.lowercased() == first.address else { throw Failure.missingHit("native address handler") }
                    let flyer = await manager.flyerProximityAddress(at: first.location(addressMode: true), searchMeters: 8)
                    print("CANONICAL_TILE_FLYER expected=\(first.address) actual=\(flyer?.id.uuidString.lowercased() ?? "nil")")
                    guard flyer?.id.uuidString.lowercased() == first.address else { throw Failure.missingHit("flyer proximity address") }
                }
                try await Task.sleep(nanoseconds: 350_000_000)
                let baseline = try map.snapshot()
                let before = pixel(baseline, at: map.mapboxMap.point(for: first.location(addressMode: addressMode)))
                let neighbourBefore = pixel(baseline, at: map.mapboxMap.point(for: second.location(addressMode: addressMode)))
                for status in ["attempted", "talked", "lead", "appointment", "do_not_knock", "not_visited"] {
                    let started = CACurrentMediaTime()
                    if addressMode { manager.updateAddressState(addressId: id, status: status, scansTotal: 0) }
                    else { manager.updateBuildingState(gersId: id, status: status, scansTotal: 0) }
                    try await Task.sleep(nanoseconds: 250_000_000)
                    let state = try await featureState(map, source: source, layer: sourceLayer, id: id)
                    let neighbourState = try await featureState(map, source: source, layer: sourceLayer, id: neighbour)
                    guard state["status"] as? String == status else { throw Failure.wrongState(id) }
                    guard neighbourState["status"] as? String == "not_visited" else { throw Failure.wrongState(neighbour) }
                    let snapshot = try map.snapshot()
                    let sample = pixel(snapshot, at: map.mapboxMap.point(for: first.location(addressMode: addressMode)))
                    let neighbourSample = pixel(snapshot, at: map.mapboxMap.point(for: second.location(addressMode: addressMode)))
                    if status == "lead", distance(before, sample) < 20 { throw Failure.pixelUnchanged }
                    if distance(neighbourBefore, neighbourSample) > 15 { throw Failure.neighbourChanged }
                    try snapshot.pngData()?.write(to: directory.appendingPathComponent("\(sourceLayer)-\(status).png"))
                    report.append(["phase": "colour", "layer": sourceLayer, "status": status, "target": sample,
                        "neighbour": neighbourSample, "stateVerifiedAfterMs": (CACurrentMediaTime() - started) * 1000])
                }
                if addressMode { manager.updateAddressState(addressId: id, status: "lead", scansTotal: 1) }
                else { manager.updateBuildingState(gersId: id, status: "lead", scansTotal: 1) }
                try await Task.sleep(nanoseconds: 250_000_000)
                let qr = try await featureState(map, source: source, layer: sourceLayer, id: id)
                guard qr["scans_total"] as? Int == 1 else { throw Failure.wrongState("qr") }
                try map.snapshot().pngData()?.write(to: directory.appendingPathComponent("\(sourceLayer)-qr.png"))
            }
            if let building = fixture.bundle.buildings.features.first(where: { $0.properties.buildingIdentifierCandidates.contains(first.building) }),
               let neighbour = fixture.bundle.buildings.features.first(where: { $0.properties.buildingIdentifierCandidates.contains(second.building) }),
               let addressId = UUID(uuidString: first.address), let neighbourId = UUID(uuidString: second.address) {
                message = "Checking autorecord: proximity, dwell and duplicate protection"
                let scenarios = try await SessionManager.verifyCanonicalAutoRecord(building: building, addressId: addressId,
                    neighbourBuilding: neighbour, neighbourAddressId: neighbourId, coordinate: first.location(addressMode: false), exactGeometry: buildingShape)
                report.append(["phase": "autorecord", "scenarios": scenarios, "result": "PASS", "scope": "real dwell pipeline with binary shape, isolated demo state, no backend writes"])
            } else { throw Failure.missingTargets }
            try await verifyMapEdits(map, manager: manager, index: index, snapshot: snapshot, first: first)
            try JSONSerialization.data(withJSONObject: ["result": "PASS", "scope": "local rendering and state, no production mutations", "measurements": report], options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
            message = "PASS: tiles, map edits, undo, pins, neighbours and QR"
            print("CANONICAL_TILE_VERIFICATION_PASS")
        } catch {
            try? map.snapshot().pngData()?.write(to: directory.appendingPathComponent("failure.png"))
            message = "FAIL: \(String(describing: error))"
            try? JSONSerialization.data(withJSONObject: ["result": "FAIL", "error": String(describing: error), "measurements": report], options: [.prettyPrinted])
                .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
            print("CANONICAL_TILE_VERIFICATION_FAIL \(String(describing: error))")
        }
    }

    private func verifyMapEdits(_ map: MapView, manager: MapLayerManager, index: CanonicalCompactFieldIndex,
                                snapshot: CanonicalCompactFieldSnapshot, first: Target) async throws {
        message = "Checking PMTiles moves, removal, offline reopen and undo"
        let base = CampaignMapEditSnapshot(buildings: snapshot.buildings.features, addresses: snapshot.addresses.features, parcels: snapshot.parcels.features)
        guard let building = base.buildings.first(where: { $0.properties.buildingIdentifierCandidates.contains(first.building) }),
              let movedGeometry = CampaignMapEdits.translated(building.geometry, latitude: 0, longitude: 0.00035) else { throw Failure.missingTargets }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("map-edit-render-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var remote = CampaignMapEditState()
        var applied: Set<String> = []
        let transport: CampaignMapEditStore.Transport = { _, request in
            guard let request else { return (remote, 200) }
            if applied.contains(request.clientMutationId) { return (remote, 200) }
            guard request.baseRevision == remote.revision else { return (remote, 409) }
            remote = remote.applying(request.changes); remote.revision += 1
            applied.insert(request.clientMutationId)
            return (remote, 200)
        }
        let store = CampaignMapEditStore(root: root, scopeProvider: { "verification:\($0)" }, transport: transport, observeNetwork: false)
        let campaign = index.campaign.campaignId
        func render(_ state: CampaignMapEditState) throws -> (CampaignMapEditSnapshot, CanonicalTileRenderPlan) {
            let corrected = CampaignMapEdits.snapshot(buildings: base.buildings, addresses: base.addresses, parcels: base.parcels, state: state)
            let plan = try index.renderPlan(buildings: corrected.buildings, addresses: corrected.addresses, parcels: corrected.parcels, editedItems: Set(state.features.keys))
            manager.updateCanonicalTileScope(buildings: plan.buildingIds, addresses: plan.addressIds, parcels: plan.parcelIds)
            manager.updateBuildings(try JSONEncoder().encode(BuildingFeatureCollection(type: "FeatureCollection", features: plan.buildingEdits)))
            manager.updateAddresses(try JSONEncoder().encode(AddressFeatureCollection(type: "FeatureCollection", features: plan.addressEdits)))
            manager.updateParcels(try JSONEncoder().encode(ParcelFeatureCollection(type: "FeatureCollection", features: plan.parcelEdits)))
            manager.setDiamondGeometryVisibility(buildings: true, addresses: true, addressNumbers: false, parcels: true)
            manager.setAddressExtrusionVisibility(isVisible: true)
            try map.mapboxMap.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            try map.mapboxMap.updateLayer(withId: MapLayerManager.parcelsFillLayerId, type: FillLayer.self) { $0.visibility = .constant(.visible) }
            try map.mapboxMap.updateLayer(withId: MapLayerManager.parcelsLineLayerId, type: LineLayer.self) { $0.visibility = .constant(.visible) }
            return (corrected, plan)
        }
        let move = try CampaignMapEditPlanner.movement(CampaignMapEdits.buildingItem(building), geometry: movedGeometry,
            deltaLatitude: 0, deltaLongitude: 0.00035, moveLinked: true, snapshot: base, state: .init(), sourceRevision: index.campaign.tiles.geometryRevision)
        try store.commit(campaign, title: move.title, changes: move.changes, startSync: false)
        let (moved, plan) = try render(store.state(for: campaign))
        guard !plan.buildingIds.contains(first.building), plan.buildingEdits.contains(where: { $0.properties.buildingIdentifierCandidates.contains(first.building) }),
              moved.addresses.count == base.addresses.count else { throw Failure.wrongState("move tile suppression") }
        let movedTarget = Target(address: first.address, building: first.building,
            coordinate: [first.coordinate[0] + 0.00035, first.coordinate[1]], buildingCoordinate: [first.buildingCoordinate[0] + 0.00035, first.buildingCoordinate[1]])
        map.mapboxMap.setCamera(to: CameraOptions(center: movedTarget.location(addressMode: false), zoom: 19, bearing: 0, pitch: 0))
        try await waitForHit(map, layer: MapLayerManager.buildingsLayerId, target: movedTarget, isAddress: false, tiled: false)
        try await waitForNoEditFeature(map, layer: VectorTileDiamondGeometryProvider.buildingFillLayerId,
            id: first.building, coordinate: first.location(addressMode: false))
        try map.snapshot().pngData()?.write(to: directory.appendingPathComponent("map-edit-moved.png"))
        report.append(["phase": "map_edit_moved_overlay_hit", "result": "PASS", "tile_original_suppressed": true])
        var selected: Set<CampaignMapItem> = [CampaignMapEdits.buildingItem(building)]
        if let parcel = base.parcels.first(where: { ($0.properties.addressIds ?? []).contains(first.address) || $0.properties.addressId == first.address }) {
            selected.insert(CampaignMapEdits.parcelItem(parcel))
        }
        let removal = try CampaignMapEditPlanner.deletion(selected, snapshot: moved, state: store.state(for: campaign))
        try store.commit(campaign, title: removal.title, changes: removal.changes, startSync: false)
        let reopened = CampaignMapEditStore(root: root, scopeProvider: { "verification:\($0)" }, transport: transport, observeNetwork: false)
        let (removed, removedPlan) = try render(reopened.state(for: campaign))
        guard !removed.buildings.contains(where: { $0.properties.buildingIdentifierCandidates.contains(first.building) }),
              !removedPlan.buildingIds.contains(first.building),
              removed.addresses.count == base.addresses.count else { throw Failure.wrongState("removal address preservation") }
        try await waitForNoEditFeature(map, layer: MapLayerManager.buildingsLayerId,
            id: first.building, coordinate: movedTarget.location(addressMode: false))
        await reopened.synchronize(campaign)
        guard reopened.pendingCount(campaign) == 0, remote.revision == 2 else { throw Failure.wrongState("edit replay") }
        report.append(["phase": "map_edit_remove_reopen_sync", "result": "PASS", "addresses_preserved": removed.addresses.count, "selected_items": selected.count])
        try reopened.undo(campaign, startSync: false)
        await reopened.synchronize(campaign)
        let (restoredMoved, _) = try render(reopened.state(for: campaign))
        guard restoredMoved.buildings.count == base.buildings.count else { throw Failure.wrongState("undo removal") }
        try reopened.undo(campaign, startSync: false)
        await reopened.synchronize(campaign)
        let (_, restoredPlan) = try render(reopened.state(for: campaign))
        guard remote.features.isEmpty, reopened.state(for: campaign).features.isEmpty, restoredPlan.buildingIds.contains(first.building) else { throw Failure.wrongState("undo move") }
        map.mapboxMap.setCamera(to: CameraOptions(center: first.location(addressMode: false), zoom: 19, bearing: 0, pitch: 0))
        try await waitForHit(map, layer: VectorTileDiamondGeometryProvider.buildingFillLayerId, target: first, isAddress: false, tiled: true)
        try map.snapshot().pngData()?.write(to: directory.appendingPathComponent("map-edit-undone.png"))
        report.append(["phase": "map_edit_undo_restores_tiles", "result": "PASS", "server_revision": remote.revision])
    }

    private func waitForNoEditFeature(_ map: MapView, layer: String, id: String, coordinate: CLLocationCoordinate2D) async throws {
        let deadline = CACurrentMediaTime() + 4
        while CACurrentMediaTime() < deadline {
            let point = map.mapboxMap.point(for: coordinate)
            let hits: [QueriedRenderedFeature] = try await withCheckedThrowingContinuation { continuation in
                map.mapboxMap.queryRenderedFeatures(with: CGRect(x:point.x-4,y:point.y-4,width:8,height:8),
                    options: RenderedQueryOptions(layerIds:[layer],filter:nil)) { continuation.resume(with:$0) }
            }
            if !hits.contains(where: { hit in
                let properties = hit.queriedFeature.feature.properties
                return ["canonical_id","id","gers_id","building_id"].contains { properties?[$0]??.string == id }
            }) { return }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw Failure.wrongState("removed feature still rendered in \(layer)")
    }

    private func loadStyle(_ map: MapView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            map.mapboxMap.loadStyle(Self.style, reloadPolicy: .always) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    private func waitForHit(_ map: MapView, layer: String, target: Target, isAddress: Bool, tiled: Bool) async throws {
        let deadline = CACurrentMediaTime() + 5
        while CACurrentMediaTime() < deadline {
            if map.mapboxMap.layerExists(withId: layer) {
                let p = map.mapboxMap.point(for: target.location(addressMode: isAddress))
                let features: [QueriedRenderedFeature] = try await withCheckedThrowingContinuation { continuation in
                    map.mapboxMap.queryRenderedFeatures(with: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8), options: RenderedQueryOptions(layerIds: [layer], filter: nil)) { continuation.resume(with: $0) }
                }
                let id = isAddress ? target.address : target.building
                if features.contains(where: { feature in
                    let object = feature.queriedFeature.feature
                    if tiled { return object.properties?["canonical_id"]??.string == id }
                    return object.properties?["id"]??.string == id || object.properties?["gers_id"]??.string == id || object.properties?["building_id"]??.string == id
                }) { return }
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw Failure.timeout(layer)
    }
    private func featureState(_ map: MapView, source: String, layer: String, id: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            map.mapboxMap.getFeatureState(sourceId: source, sourceLayerId: layer, featureId: id) { continuation.resume(with: $0) }
        }
    }
    private func pixel(_ image: UIImage, at point: CGPoint) -> [Int] {
        guard let imageRef = image.cgImage else { return [] }
        var rgba = [UInt8](repeating: 0, count: imageRef.width * imageRef.height * 4)
        let context = CGContext(data: &rgba, width: imageRef.width, height: imageRef.height, bitsPerComponent: 8, bytesPerRow: imageRef.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(imageRef, in: CGRect(x: 0, y: 0, width: imageRef.width, height: imageRef.height))
        let x = max(0, min(imageRef.width - 1, Int(point.x * image.scale)))
        let y = max(0, min(imageRef.height - 1, Int(point.y * image.scale)))
        let index = (y * imageRef.width + x) * 4
        return (0..<3).map { Int(rgba[index + $0]) }
    }
    private func distance(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).map { abs($0 - $1) }.reduce(0, +) }
}

#endif
