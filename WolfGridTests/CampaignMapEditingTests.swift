import XCTest
import CoreLocation
@testable import WolfGrid

@MainActor
final class CampaignMapEditingTests: XCTestCase {
    private let home = "00000000-0000-0000-0000-000000000001"
    private let unit = "00000000-0000-0000-0000-000000000002"
    private let other = "00000000-0000-0000-0000-000000000003"
    private func shape(_ x: Double, _ y: Double, width: Double = 2) -> MapFeatureGeoJSONGeometry {
        .init(type: "Polygon", coordinates: .init(polygon: [[[x,y],[x+width,y],[x+width,y+width],[x,y+width],[x,y]]]))
    }
    private func building(_ id: String, x: Double, addressIDs: [String] = []) throws -> BuildingFeature {
        let data = try JSONSerialization.data(withJSONObject: ["type":"Feature", "id":id,
            "geometry": ["type":"Polygon", "coordinates": [[[x,1],[x+2,1],[x+2,3],[x,3],[x,1]]]],
            "properties": ["id":id,"gers_id":id,"height":8,"address_ids":addressIDs,"address_count":addressIDs.count,"address_text":id]])
        return try JSONDecoder().decode(BuildingFeature.self, from: data)
    }
    private func address(_ id: String, x: Double, building: String?, parcel: String?) -> AddressFeature {
        .init(id: id, geometry: .init(type: "Point", coordinates: .init(point: [x,2])),
            properties: .init(id: id, buildingGersId: building, houseNumber: "12", streetName: "Main St", postalCode: "L1A 1A1",
                formatted: "12 Main St", source: "municipal", parcelId: parcel, hasBuildingLink: building != nil, hasParcelLink: parcel != nil))
    }
    private func fixture() throws -> CampaignMapEditSnapshot {
        .init(buildings: [try building("roof-a", x: 1, addressIDs: [home, unit]), try building("roof-b", x: 21)],
            addresses: [address(home, x: 2, building: "roof-a", parcel: "lot-a"), address(unit, x: 2.5, building: "roof-a", parcel: "lot-a"), address(other, x: 25, building: nil, parcel: "lot-b")],
            parcels: [ParcelFeature(id: "lot-a", geometry: shape(0,0,width:10), properties: .init(id:"lot-a",parcelId:"lot-a",externalId:nil,source:"municipal",areaSqm:100,addressIds:[home,unit])),
                      ParcelFeature(id: "lot-b", geometry: shape(20,0,width:10), properties: .init(id:"lot-b",parcelId:"lot-b",externalId:nil,source:"municipal",areaSqm:100,addressIds:[other]))])
    }
    private func effective(_ snapshot: CampaignMapEditSnapshot, _ state: CampaignMapEditState) -> CampaignMapEditSnapshot {
        CampaignMapEdits.snapshot(buildings: snapshot.buildings, addresses: snapshot.addresses, parcels: snapshot.parcels, state: state)
    }
    func testBuildingRemovalPreservesAddressesMetadataAndParcelLinks() throws {
        let original = try fixture()
        let command = try CampaignMapEditPlanner.deletion([.init(.building,"roof-a")], snapshot: original, state: .init())
        let result = effective(original, CampaignMapEditState().applying(command.changes))
        XCTAssertEqual(result.buildings.count, 1)
        XCTAssertEqual(result.addresses.count, original.addresses.count)
        let address = try XCTUnwrap(result.addresses.first { $0.id == home })
        XCTAssertNil(address.properties.buildingGersId)
        XCTAssertEqual(address.properties.parcelId, "lot-a")
        XCTAssertEqual(address.properties.postalCode, "L1A 1A1")
        XCTAssertEqual(address.geometry.nativeGeometry, original.addresses[0].geometry.nativeGeometry)
        XCTAssertEqual(original.buildings.count, 2, "Corrections must not mutate the immutable source snapshot")
    }
    func testUnrelatedCorrectionsPreserveLinksStoredOnAddressRecords() throws {
        let original = CampaignMapEditSnapshot(buildings:[try building("roof-a",x:1)],
            addresses:[address(home,x:2,building:"roof-a",parcel:"lot-a")],parcels:[])
        let result = effective(original,CampaignMapEditState(features:["parcel:another-lot":.init(hidden:true)]))
        XCTAssertEqual(result.buildings.first?.properties.addressUUIDs,[UUID(uuidString:home)!])
        XCTAssertEqual(result.addresses.first?.properties.buildingGersId,"roof-a")
    }
    func testParcelRemovalKeepsBuildingsAndAddressBuildingLinks() throws {
        let original = try fixture()
        let command = try CampaignMapEditPlanner.deletion([.init(.parcel,"lot-a")], snapshot: original, state: .init())
        let result = effective(original, CampaignMapEditState().applying(command.changes))
        XCTAssertEqual(result.buildings.count, 2)
        XCTAssertEqual(result.parcels.count, 1)
        XCTAssertNil(result.addresses[0].properties.parcelId)
        XCTAssertEqual(result.addresses[0].properties.buildingGersId, "roof-a")
    }
    func testMixedRemovalUpdatesBothLinksInOneCommand() throws {
        let original = try fixture()
        let command = try CampaignMapEditPlanner.deletion([.init(.building,"roof-a"), .init(.parcel,"lot-a")], snapshot: original, state: .init())
        let state = CampaignMapEditState().applying(command.changes)
        XCTAssertEqual(Set(command.changes.map { $0.item.id }).count, command.changes.count)
        XCTAssertTrue(state.features["address:\(home)"]?.buildingLinkSet == true)
        XCTAssertTrue(state.features["address:\(home)"]?.parcelLinkSet == true)
        XCTAssertNil(state.features["address:\(home)"]?.buildingId)
        XCTAssertNil(state.features["address:\(home)"]?.parcelId)
    }
    func testParcelLinkPreservesExistingBuildingAndAddressPosition() throws {
        let item = CampaignMapItem(.address, "address-1")
        let geometry = MapFeatureGeoJSONGeometry(type: "Point", coordinates: .init(point: [-78.7, 43.9]))
        let original = CampaignMapEditValue(geometry: geometry, buildingLinkSet: true, buildingId: "building-1")
        let state = CampaignMapEditState(features: [item.id: original])
        let change = CampaignMapEditPlanner.addressParcelLink(
            addressId: "address-1", parcelId: "PARCEL-1", state: state, sourceRevision: "revision"
        )
        XCTAssertEqual(change.value?.geometry?.nativeGeometry, geometry.nativeGeometry)
        XCTAssertEqual(change.value?.buildingId, "building-1")
        XCTAssertEqual(change.value?.buildingLinkSet, true)
        XCTAssertEqual(change.value?.parcelLinkSet, true)
        XCTAssertEqual(change.value?.parcelId, "parcel-1")
    }

    func testParcelPlacementMovesAddressAndPreservesExistingBuildingLink() throws {
        let item = CampaignMapItem(.address, home)
        let state = CampaignMapEditState(features: [item.id: .init(buildingLinkSet: true, buildingId: "roof-a")])
        let change = CampaignMapEditPlanner.addressParcelLink(addressId: home, parcelId: "lot-b",
            coordinate: .init(latitude: 2, longitude: 22), state: state, sourceRevision: "v1")
        XCTAssertEqual(change.value?.geometry?.asPoint, [22, 2])
        XCTAssertEqual(change.value?.buildingId, "roof-a")
        XCTAssertEqual(change.value?.parcelId, "lot-b")
    }

    func testParcelBuildingPlacementRequiresOneContainedBuilding() throws {
        let snapshot = try fixture()
        let parcel = snapshot.parcels[1]
        let roof = try XCTUnwrap(CampaignMapEditPlanner.uniqueBuilding(on: parcel, among: snapshot.buildings))
        XCTAssertEqual(roof.id, "roof-b")
        let center = try XCTUnwrap(CampaignMapEditPlanner.center(roof.geometry))
        XCTAssertEqual(center.longitude, 22, accuracy: 0.0001)
        XCTAssertEqual(center.latitude, 2, accuracy: 0.0001)
        let secondRoof = try building("roof-c", x: 25)
        XCTAssertNil(CampaignMapEditPlanner.uniqueBuilding(on: parcel, among: snapshot.buildings + [secondRoof]))
    }

    func testBuildingPlacementReplacesParcelAndSurvivesReload() throws {
        let original = try fixture()
        let change = CampaignMapEditPlanner.addressPlacement(addressId: home,
            coordinate: .init(latitude: 2, longitude: 22), buildingId: "roof-b", parcelId: "lot-b",
            state: .init(), sourceRevision: "v1")
        let saved = CampaignMapEditState().applying([change])
        let restored = try JSONDecoder().decode(CampaignMapEditState.self, from: JSONEncoder().encode(saved))
        let result = effective(original, restored)
        XCTAssertEqual(result.addresses[0].properties.parcelId, "lot-b")
        XCTAssertEqual(result.addresses[0].properties.buildingGersId, "roof-b")
        XCTAssertFalse(result.parcels[0].properties.addressIds?.contains(home) ?? false)
        XCTAssertTrue(result.parcels[0].properties.addressIds?.contains(unit) ?? false)
        XCTAssertTrue(result.parcels[1].properties.addressIds?.contains(home) ?? false)
        let unlink = CampaignMapEditPlanner.addressPlacement(addressId: home,
            coordinate: .init(latitude: 50, longitude: 50), buildingId: nil, parcelId: nil,
            state: restored, sourceRevision: "v1")
        let unlinked = effective(original, restored.applying([unlink]))
        XCTAssertNil(unlinked.addresses[0].properties.parcelId)
        XCTAssertNil(unlinked.addresses[0].properties.buildingGersId)
        XCTAssertFalse(unlinked.parcels.contains { $0.properties.addressIds?.contains(home) == true })
    }

    func testAddressDropLinksSingleBuildingAndParcelAtomically() throws {
        let original = try fixture()
        let proposal = try CampaignMapEditPlanner.movement(.init(.address,home), geometry: .init(type:"Point",coordinates:.init(point:[25,2])),
            deltaLatitude:0,deltaLongitude:23,moveLinked:false,snapshot:original,state:.init(),sourceRevision:"v1")
        let value = try XCTUnwrap(proposal.changes.first?.value)
        XCTAssertEqual(value.buildingId, "roof-b")
        XCTAssertEqual(value.parcelId, "lot-b")
        XCTAssertTrue(proposal.choices.isEmpty)
        let result = effective(original, CampaignMapEditState().applying(proposal.changes))
        XCTAssertFalse(result.buildings[0].properties.addressUUIDs.contains(UUID(uuidString: home)!))
        XCTAssertTrue(result.buildings[1].properties.addressUUIDs.contains(UUID(uuidString: home)!))
    }
    func testAmbiguousBuildingsRequireChoiceAndUnlinkedChoiceIsDurable() throws {
        let fixture = try fixture()
        let original = CampaignMapEditSnapshot(buildings: fixture.buildings + [try building("garage",x:27)], addresses:fixture.addresses,parcels:fixture.parcels)
        let proposal = try CampaignMapEditPlanner.movement(.init(.address,home),geometry:.init(type:"Point",coordinates:.init(point:[25,2])),
            deltaLatitude:0,deltaLongitude:23,moveLinked:false,snapshot:original,state:.init(),sourceRevision:nil)
        XCTAssertEqual(proposal.choices.count, 2)
        XCTAssertNil(proposal.changes.first?.value?.buildingId)
        XCTAssertTrue(proposal.changes.first?.value?.buildingLinkSet == true)
        let selected = proposal.choosing([try XCTUnwrap(proposal.choices.first { $0.buildingID == "garage" })])
        XCTAssertEqual(selected.changes.first?.value?.buildingId, "garage")
    }
    func testDropInsideOneFootprintResolvesMultipleBuildingsOnParcel() throws {
        let fixture = try fixture()
        let original = CampaignMapEditSnapshot(buildings:fixture.buildings + [try building("garage",x:27)],addresses:fixture.addresses,parcels:fixture.parcels)
        let proposal = try CampaignMapEditPlanner.movement(.init(.address,home),geometry:.init(type:"Point",coordinates:.init(point:[22,2])),
            deltaLatitude:0,deltaLongitude:20,moveLinked:false,snapshot:original,state:.init(),sourceRevision:nil)
        XCTAssertTrue(proposal.choices.isEmpty)
        XCTAssertEqual(proposal.changes.first?.value?.buildingId, "roof-b")
    }
    func testChoosingALinkPreservesAnExistingAddressCorrection() throws {
        let original = try fixture()
        let item = CampaignMapItem(.address,other)
        let correctedPoint = MapFeatureGeoJSONGeometry(type:"Point",coordinates:.init(point:[26,2]))
        let state = CampaignMapEditState(features:[item.id:.init(geometry:correctedPoint,parcelLinkSet:true,parcelId:"lot-b")])
        var proposal = CampaignMapEditProposal(title:"Move building",changes:[.init(.init(.building,"roof-b"),value:.init(geometry:original.buildings[1].geometry))],
            parcelID:"lot-b",message:"Choose address")
        proposal.baseState = state
        let linked = proposal.choosing([.init(addressID:other,buildingID:"roof-b",title:"12 Main St")])
        let value = try XCTUnwrap(linked.changes.first { $0.item == item }?.value)
        XCTAssertEqual(value.geometry?.asPoint,[26,2])
        XCTAssertEqual(value.buildingId,"roof-b")
        XCTAssertEqual(value.parcelId,"lot-b")
    }
    func testBuildingGroupMovePreservesUnitIDsAndMovesAllLinkedAddresses() throws {
        let original = try fixture()
        let moved = try XCTUnwrap(CampaignMapEdits.translated(original.buildings[0].geometry,latitude:0,longitude:20))
        let proposal = try CampaignMapEditPlanner.movement(.init(.building,"roof-a"),geometry:moved,deltaLatitude:0,deltaLongitude:20,
            moveLinked:true,snapshot:original,state:.init(),sourceRevision:nil)
        let result = effective(original, CampaignMapEditState().applying(proposal.changes))
        XCTAssertEqual(result.addresses[0].geometry.asPoint, [22,2])
        XCTAssertEqual(result.addresses[1].geometry.asPoint, [22.5,2])
        XCTAssertEqual(result.addresses[0].properties.buildingGersId, "roof-a")
        XCTAssertEqual(result.addresses[0].properties.parcelId, "lot-b")
        XCTAssertEqual(result.addresses[2].geometry.asPoint, [25,2])
    }
    func testParcelGroupMoveAndParcelOnlyMove() throws {
        let original = try fixture()
        let moved = try XCTUnwrap(CampaignMapEdits.translated(original.parcels[0].geometry,latitude:10,longitude:0))
        for includeLinked in [true,false] {
            let proposal = try CampaignMapEditPlanner.movement(.init(.parcel,"lot-a"),geometry:moved,deltaLatitude:10,deltaLongitude:0,
                moveLinked:includeLinked,snapshot:original,state:.init(),sourceRevision:nil)
            let result = effective(original, CampaignMapEditState().applying(proposal.changes))
            XCTAssertEqual(result.addresses[0].geometry.asPoint, includeLinked ? [2,12] : [2,2])
            XCTAssertEqual(result.buildings[0].geometry.nativeGeometry, includeLinked ? CampaignMapEdits.translated(original.buildings[0].geometry,latitude:10,longitude:0)?.nativeGeometry : original.buildings[0].geometry.nativeGeometry)
            XCTAssertEqual(result.addresses[2].geometry.asPoint, [25,2])
        }
    }
    func testParcelGroupMoveIncludesBuildingAddressPlottedOutsideParcel() throws {
        let fixture = try fixture()
        let parcel = ParcelFeature(id:"lot-a",geometry:fixture.parcels[0].geometry,
            properties:.init(id:"lot-a",parcelId:"lot-a",externalId:nil,source:nil,areaSqm:nil))
        let curbAddress = address(home,x:12,building:"roof-a",parcel:nil)
        let original = CampaignMapEditSnapshot(buildings:[fixture.buildings[0]],addresses:[curbAddress],parcels:[parcel])
        let moved = try XCTUnwrap(CampaignMapEdits.translated(parcel.geometry,latitude:10,longitude:0))
        let proposal = try CampaignMapEditPlanner.movement(.init(.parcel,"lot-a"),geometry:moved,deltaLatitude:10,deltaLongitude:0,
            moveLinked:true,snapshot:original,state:.init(),sourceRevision:nil)
        let corrected = effective(original,CampaignMapEditState().applying(proposal.changes))
        XCTAssertEqual(corrected.addresses.first?.geometry.asPoint,[12,12])
        XCTAssertEqual(corrected.addresses.first?.properties.buildingGersId,"roof-a")
        XCTAssertEqual(corrected.addresses.first?.properties.parcelId,"lot-a")
    }
    func testIntentionalUnlinkCannotBeReplacedByAutomaticMatching() throws {
        let original = try fixture()
        let state = CampaignMapEditState().applying(CampaignMapEditPlanner.unlink(original.addresses[2],state:.init()).changes)
        let current = effective(original,state)
        let proposal = try CampaignMapEditPlanner.movement(.init(.building,"roof-b"),geometry:current.buildings[1].geometry,
            deltaLatitude:0,deltaLongitude:0,moveLinked:false,snapshot:current,state:state,sourceRevision:nil)
        XCTAssertFalse(proposal.changes.contains { $0.id == other })
    }
    func testTranslatedPolygonKeepsHolesAndMultiPolygonParts() throws {
        let geometry = MapFeatureGeoJSONGeometry(type:"MultiPolygon",coordinates:.init(multiPolygon:[
            [[[0,0],[5,0],[5,5],[0,5],[0,0]],[[1,1],[2,1],[2,2],[1,2],[1,1]]],
            [[[10,0],[11,0],[11,1],[10,1],[10,0]]]
        ]))
        let moved = try XCTUnwrap(CampaignMapEdits.translated(geometry,latitude:2,longitude:3))
        XCTAssertEqual(moved.asMultiPolygon?.count,2)
        XCTAssertEqual(moved.asMultiPolygon?.first?.count,2)
        XCTAssertTrue(CampaignMapEditPlanner.contains(moved,.init(latitude:2.5,longitude:3.5)))
        XCTAssertFalse(CampaignMapEditPlanner.contains(moved,.init(latitude:3.5,longitude:4.5)))
    }
    func testNearEdgeSnapMovesInsideOnlyOneUnambiguousParcel() {
        let parcel = ParcelFeature(id:"lot",geometry:shape(0,0,width:0.001),properties:.init(id:"lot",parcelId:"lot",externalId:nil,source:nil,areaSqm:nil))
        let near = CLLocationCoordinate2D(latitude:0.0005,longitude:-0.000005)
        let snapped = CampaignMapEditPlanner.snapCoordinate(near,parcels:[parcel],toleranceMeters:1)
        XCTAssertTrue(CampaignMapEditPlanner.contains(parcel.geometry,snapped))
        let overlapping = ParcelFeature(id:"overlap",geometry:parcel.geometry,properties:.init(id:"overlap",parcelId:"overlap",externalId:nil,source:nil,areaSqm:nil))
        let ambiguous = CampaignMapEditPlanner.snapCoordinate(near,parcels:[parcel,overlapping],toleranceMeters:1)
        XCTAssertEqual(ambiguous.longitude,near.longitude)
        XCTAssertEqual(ambiguous.latitude,near.latitude)
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("map-edits-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return root
    }
    func testOfflineEditAndUndoSurviveReopenAndAccountIsolation() throws {
        let root = try root()
        var account = "one"
        let store = CampaignMapEditStore(root:root,scopeProvider:{ "\(account):\($0)" },observeNetwork:false)
        let change = CampaignMapEditChange(.init(.building,"roof"),value:.init(hidden:true))
        try store.commit("campaign",title:"Remove",changes:[change],startSync:false)
        let reopened = CampaignMapEditStore(root:root,scopeProvider:{ "\(account):\($0)" },observeNetwork:false)
        XCTAssertEqual(reopened.pendingCount("campaign"),1)
        XCTAssertTrue(reopened.state(for:"campaign").features["building:roof"]?.hidden == true)
        try reopened.undo("campaign",startSync:false)
        let afterUndo = CampaignMapEditStore(root:root,scopeProvider:{ "\(account):\($0)" },observeNetwork:false)
        XCTAssertNil(afterUndo.state(for:"campaign").features["building:roof"])
        XCTAssertEqual(afterUndo.pendingCount("campaign"),2)
        account = "two"
        XCTAssertTrue(afterUndo.state(for:"campaign").features.isEmpty)
        XCTAssertEqual(afterUndo.pendingCount("campaign"),0)
    }
    func testDiskFailureDoesNotPublishAnUnsavedEdit() throws {
        let root = try root().appendingPathComponent("file")
        try Data("not a directory".utf8).write(to:root)
        let store = CampaignMapEditStore(root:root,scopeProvider:{$0},observeNetwork:false)
        XCTAssertThrowsError(try store.commit("campaign",title:"Remove",changes:[.init(.init(.building,"roof"),value:.init(hidden:true))],startSync:false))
        XCTAssertTrue(store.state(for:"campaign").features.isEmpty)
        XCTAssertEqual(store.pendingCount("campaign"),0)
    }
    func testInvalidGeometryIsRejectedBeforeItCanEnterTheQueue() throws {
        let store = CampaignMapEditStore(root:try root(),scopeProvider:{$0},observeNetwork:false)
        let change = CampaignMapEditChange(.init(.address,home),value:.init(geometry:shape(0,0)))
        XCTAssertThrowsError(try store.commit("campaign",title:"Move",changes:[change],startSync:false))
        XCTAssertEqual(store.pendingCount("campaign"),0)
    }
    func testCreationUndoHidesNewHouseAndFallbackBuildingWithoutDeletingSourceData() throws {
        let store = CampaignMapEditStore(root:try root(),scopeProvider:{$0},observeNetwork:false)
        try store.recordCreation("campaign",items:[.init(.address,home),.init(.building,"fallback_\(home)")])
        XCTAssertTrue(store.canUndo("campaign"))
        XCTAssertEqual(store.pendingCount("campaign"),0)
        try store.undo("campaign",startSync:false)
        XCTAssertTrue(store.state(for:"campaign").features["address:\(home)"]?.hidden == true)
        XCTAssertTrue(store.state(for:"campaign").features["building:fallback_\(home)"]?.hidden == true)
        XCTAssertEqual(store.pendingCount("campaign"),1)
    }
    func testLargeBuildingRemovalDoesNotDropUnitsToFitBatchLimit() throws {
        let addresses = (0..<600).map { index in address(String(format:"00000000-0000-0000-0001-%012d",index),x:2,building:"roof",parcel:"lot") }
        let original = CampaignMapEditSnapshot(buildings:[try building("roof",x:1,addressIDs:addresses.compactMap(\.id))],addresses:addresses,parcels:[])
        let proposal = try CampaignMapEditPlanner.deletion([.init(.building,"roof")],snapshot:original,state:.init())
        XCTAssertLessThanOrEqual(proposal.changes.count,500)
        let corrected = effective(original,CampaignMapEditState().applying(proposal.changes))
        XCTAssertEqual(corrected.addresses.count,600)
        XCTAssertTrue(corrected.buildings.isEmpty)
        XCTAssertTrue(corrected.addresses.allSatisfy { $0.properties.buildingGersId == nil })
    }
    func testBuildingCoveringParcelHoleCannotAutoLinkToThatParcel() throws {
        let building = try building("roof",x:1)
        let parcel = ParcelFeature(id:"lot",geometry:.init(type:"Polygon",coordinates:.init(polygon:[
            [[0,0],[10,0],[10,10],[0,10],[0,0]], [[1.2,1.2],[1.4,1.2],[1.4,1.4],[1.2,1.4],[1.2,1.2]]
        ])),properties:.init(id:"lot",parcelId:"lot",externalId:nil,source:nil,areaSqm:nil))
        XCTAssertFalse(CampaignMapEditPlanner.buildingFits(building,parcel:parcel))
    }
    private final class Remote {
        var state = CampaignMapEditState()
        var applied: [String: CampaignMapEditRequest] = [:]
        var loseNextResponse = false
        func send(_ campaign: String, _ request: CampaignMapEditRequest?) async throws -> (CampaignMapEditState,Int) {
            guard let request else { return (state,200) }
            if applied[request.clientMutationId] != nil { return (state,200) }
            guard request.baseRevision == state.revision else { return (state,409) }
            state = state.applying(request.changes); state.revision += 1
            applied[request.clientMutationId] = request
            if loseNextResponse { loseNextResponse = false; throw URLError(.networkConnectionLost) }
            return (state,200)
        }
    }
    func testSyncAcknowledgementKeepsGeometryCacheGeneration() async throws {
        let remote = Remote()
        let store = CampaignMapEditStore(root: try root(), scopeProvider: { $0 }, transport: remote.send, observeNetwork: false)
        try store.commit("campaign", title: "Remove", changes: [.init(.init(.building, "roof"), value: .init(hidden: true))], startSync: false)
        let afterEdit = store.geometryGeneration
        await store.synchronize("campaign")
        XCTAssertEqual(store.pendingCount("campaign"), 0)
        XCTAssertEqual(store.geometryGeneration, afterEdit)
        try store.undo("campaign", startSync: false)
        XCTAssertGreaterThan(store.geometryGeneration, afterEdit)
    }
    func testSyncRetriesACommittedMutationWithoutDuplicatingIt() async throws {
        let remote = Remote(); remote.loseNextResponse = true
        let store = CampaignMapEditStore(root:try root(),scopeProvider:{$0},transport:remote.send,observeNetwork:false)
        try store.commit("campaign",title:"Remove",changes:[.init(.init(.building,"roof"),value:.init(hidden:true))],startSync:false)
        await store.synchronize("campaign")
        XCTAssertEqual(store.pendingCount("campaign"),1)
        await store.synchronize("campaign")
        XCTAssertEqual(store.pendingCount("campaign"),0)
        XCTAssertEqual(remote.state.revision,1)
        try store.undo("campaign",startSync:false)
        await store.synchronize("campaign")
        XCTAssertTrue(remote.state.features.isEmpty)
        XCTAssertEqual(remote.state.revision,2)
    }
    func testPendingEditsResumeWithoutReopeningTheCampaign() async throws {
        let directory = try root()
        let remote = Remote()
        let store = CampaignMapEditStore(root:directory,scopeProvider:{"account:\($0)"},transport:remote.send,observeNetwork:false)
        try store.commit("campaign",title:"Remove",changes:[.init(.init(.building,"roof"),value:.init(hidden:true))],startSync:false)
        let restarted = CampaignMapEditStore(root:directory,scopeProvider:{"account:\($0)"},transport:remote.send,observeNetwork:false)
        await restarted.resumePending()
        XCTAssertEqual(remote.state.revision,1)
        XCTAssertTrue(remote.state.features["building:roof"]?.hidden == true)
        XCTAssertEqual(restarted.pendingCount("campaign"),0)
    }
    func testPMTilesPlanSuppressesEditedGeometryAndUndoRestoresOriginalIDs() throws {
        let directory = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("CanonicalTileVerification")
        let metadata = directory.appendingPathComponent("bundle-v3.json")
        guard FileManager.default.fileExists(atPath:metadata.path) else { throw XCTSkip("Install the canonical verification fixture for rendered-tile integration tests.") }
        let campaign = try JSONDecoder().decode(CanonicalCompactCampaign.self,from:Data(contentsOf:metadata))
        let index = try CanonicalCompactFieldIndex(campaign:campaign,pack:CanonicalGeometryPack(url:directory.appendingPathComponent("canonical-geometry.wgp")))
        let field = try index.fieldSnapshot()
        let snapshot = CampaignMapEditSnapshot(buildings:field.buildings.features,addresses:field.addresses.features,parcels:field.parcels.features)
        let building = try XCTUnwrap(snapshot.buildings.first)
        let parcel = try XCTUnwrap(snapshot.parcels.first)
        let buildingItem = CampaignMapEdits.buildingItem(building), parcelItem = CampaignMapEdits.parcelItem(parcel)
        let changes: [CampaignMapEditChange] = [
            .init(buildingItem,value:.init(geometry:try XCTUnwrap(CampaignMapEdits.translated(building.geometry,latitude:0,longitude:0.0001)))),
            .init(parcelItem,value:.init(geometry:try XCTUnwrap(CampaignMapEdits.translated(parcel.geometry,latitude:0,longitude:0.0001))))
        ]
        let state = CampaignMapEditState().applying(changes)
        let corrected = effective(snapshot,state)
        let plan = try index.renderPlan(buildings:corrected.buildings,addresses:corrected.addresses,parcels:corrected.parcels,editedItems:Set(state.features.keys))
        XCTAssertTrue(plan.buildingEdits.contains { CampaignMapEdits.buildingItem($0) == buildingItem })
        XCTAssertTrue(plan.parcelEdits.contains { CampaignMapEdits.parcelItem($0) == parcelItem })
        XCTAssertFalse(plan.parcelIds.contains(parcelItem.featureID))
        let removed = effective(snapshot,CampaignMapEditState().applying(try CampaignMapEditPlanner.deletion([buildingItem],snapshot:snapshot,state:.init()).changes))
        XCTAssertEqual(removed.addresses.count,snapshot.addresses.count)
        let undone = try index.renderPlan(buildings:snapshot.buildings,addresses:snapshot.addresses,parcels:snapshot.parcels)
        XCTAssertEqual(undone.buildingIds.count,campaign.records.buildings.count)
        XCTAssertEqual(undone.parcelIds.count,campaign.records.parcels.count)
        XCTAssertTrue(undone.buildingEdits.isEmpty)
        XCTAssertTrue(undone.parcelEdits.isEmpty)
    }
    func testDisjointTeammateChangesRebaseWhileSameItemChangesRequireReview() async throws {
        let remote = Remote()
        let store = CampaignMapEditStore(root:try root(),scopeProvider:{$0},transport:remote.send,observeNetwork:false)
        try store.commit("campaign",title:"Remove",changes:[.init(.init(.building,"roof"),value:.init(hidden:true))],startSync:false)
        remote.state = .init(revision:1,features:["parcel:other":.init(hidden:true)])
        await store.synchronize("campaign")
        XCTAssertFalse(store.hasConflict("campaign"))
        XCTAssertEqual(remote.state.features.count,2)
        try store.commit("campaign",title:"Move",changes:[.init(.init(.building,"roof"),value:.init(hidden:false))],startSync:false)
        remote.state.features["building:roof"] = .init(hidden:true,sourceRevision:"teammate")
        remote.state.revision += 1
        await store.synchronize("campaign")
        XCTAssertTrue(store.hasConflict("campaign"))
        XCTAssertEqual(store.pendingCount("campaign"),1)
        try store.resolveConflict("campaign",keepMine:false)
        XCTAssertEqual(store.pendingCount("campaign"),0)
        XCTAssertEqual(store.state(for:"campaign").features["building:roof"]?.sourceRevision,"teammate")
    }
    func testGeometryAndRelationshipsRestoreTogetherWhenSourcePackageRefreshes() throws {
        let original = try fixture()
        let state = CampaignMapEditState(features:["address:\(home)":.init(geometry:.init(type:"Point",coordinates:.init(point:[25,2])),buildingLinkSet:true,buildingId:"roof-b",parcelLinkSet:true,parcelId:"lot-b",sourceRevision:"older-package")])
        let result = effective(original,state)
        XCTAssertEqual(result.addresses[0].geometry.asPoint,[25,2])
        XCTAssertEqual(result.addresses[0].properties.buildingGersId,"roof-b")
        XCTAssertEqual(result.addresses[0].properties.parcelId,"lot-b")
        // An override for an ID absent from the new package never creates a phantom home.
        let missingSource = CampaignMapEditSnapshot(buildings:original.buildings,addresses:Array(original.addresses.dropFirst()),parcels:original.parcels)
        XCTAssertEqual(effective(missingSource,state).addresses.count,2)
    }
}
