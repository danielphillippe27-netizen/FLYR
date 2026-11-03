import XCTest
import Combine
import CoreLocation
@testable import WolfGrid

@MainActor
final class FarmLiveAddressSuggestionsTests: XCTestCase {
    private func geometry(_ x: Double = -78.8, _ y: Double = 43.9, width: Double = 0.001) -> MapFeatureGeoJSONGeometry {
        .init(type: "Polygon", coordinates: .init(polygon: [[[x,y],[x+width,y],[x+width,y+width],[x,y+width],[x,y]]]))
    }
    private func parcel(_ id: String = "parcel-a", linked: Bool = false) -> ParcelFeature {
        .init(id: id, geometry: geometry(), properties: .init(id: id, parcelId: id, externalId: nil,
            source: "municipal", areaSqm: 300, addressIds: linked ? ["existing"] : []))
    }
    private func building(_ id: String = "roof-a", linked: Bool = false, type: String = "residential") throws -> BuildingFeature {
        let data = try JSONSerialization.data(withJSONObject: ["type":"Feature", "id":id,
            "geometry": ["type":"Polygon", "coordinates": [[[-78.7998,43.9002],[-78.7996,43.9002],[-78.7996,43.9004],[-78.7998,43.9004],[-78.7998,43.9002]]]],
            "properties": ["id":id,"gers_id":id,"height":8,"building_type":type,"area_sqm":120,
                           "address_ids":linked ? ["existing"] : [],"address_count":linked ? 1 : 0]])
        return try JSONDecoder().decode(BuildingFeature.self, from: data)
    }
    private func target() -> FarmLiveAddressTarget {
        .init(id:"parcel:parcel-a", parcelId:"parcel-a", buildingId:nil, geometry:geometry(),
              coordinate:.init(latitude:43.9005,longitude:-78.7995))
    }
    private func payload(accuracy: String = "rooftop", longitude: Double = -78.7995, number: String = "12") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["features":[["geometry":["type":"Point","coordinates":[longitude,43.9005]],
            "properties":["coordinates":["accuracy":accuracy], "context":["address":["address_number":number,"street_name":"Main Street"],
            "region":["region_code":"ON"],"country":["country_code":"CA"]]]]]])
    }
    func testMatchingRequiresUniqueFullCivicAddress() {
        func identity(_ number: String, _ street: String) -> String? {
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(houseNumber: number, streetName: street)
        }
        let first = UUID(), second = UUID()
        let boulevard3A = identity("3A", "Sunicrest Boulevard")
        let court3 = identity("3", "Sunicrest Court")
        let courtCRT = identity("3", "Sunicrest CRT")
        let boulevard3 = identity("3", "Sunicrest Blvd")
        XCTAssertEqual(court3, courtCRT)
        XCTAssertNotEqual(court3, boulevard3)
        XCTAssertNotEqual(boulevard3A, boulevard3)
        XCTAssertTrue(FarmLiveAddressNumberMatcher.uniquePairs(
            targets: [("3a-roof", boulevard3A)], addresses: [(first, courtCRT)]).isEmpty)
        let pairs = FarmLiveAddressNumberMatcher.uniquePairs(
            targets: [("3a-roof", boulevard3A), ("court-roof", court3)],
            addresses: [(first, courtCRT), (second, boulevard3A)])
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs.first(where: { $0.0 == "3a-roof" })?.1, second)
        XCTAssertTrue(FarmLiveAddressNumberMatcher.uniquePairs(
            targets: [("court-roof", court3)], addresses: [(first, courtCRT), (second, court3)]).isEmpty)
        XCTAssertTrue(FarmLiveAddressNumberMatcher.uniquePairs(
            targets: [("roof", nil)], addresses: [(first, nil)]).isEmpty)
    }

    func testLocalStreetSpellingNeedsIndependentVerificationBeforeMatching() throws {
        let id = UUID()
        let source = AddressFeature(id: id.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7994, 43.9004])),
            properties: .init(id: id.uuidString, houseNumber: "214", streetName: "Mains St", postalCode: "33803"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload(number: "214")) as? [String: Any])
        var features = try XCTUnwrap(json["features"] as? [[String: Any]])
        var properties = try XCTUnwrap(features[0]["properties"] as? [String: Any])
        var context = try XCTUnwrap(properties["context"] as? [String: Any])
        context["postcode"] = ["name": "33803"]
        properties["context"] = context; features[0]["properties"] = properties; json["features"] = features
        let data = try JSONSerialization.data(withJSONObject: json)
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: data, target: target()))
        let candidates = [(target(), candidate)]
        let index = FarmLiveMatchIndex(addresses: [source], buildings: [])
        XCTAssertTrue(index.shortlist(candidates).isEmpty, "Plural street names must not match without geographic verification")
        XCTAssertEqual(index.streetAliasChecks(candidates).map { $0.entry.id }, [id])
        let verified = index.acceptingStreetAliases([id: "Main Street"])
        let matches = verified.placements(candidates: candidates, visibleEntries: verified.shortlist(candidates))
        XCTAssertEqual(matches.map(\.addressID), [id])
        XCTAssertEqual(verified.renderFeatures(for: matches).first?.properties.streetName, "Mains St",
            "Temporary street context must not rewrite native civic fields")
        let roadData = Data("""
            {"features":[{"properties":{"tilequery":{"distance":2}}},
            {"properties":{"name":"E Park St","tilequery":{"distance":3.6}}},
            {"properties":{"name":"S Tennessee Ave","tilequery":{"distance":13}}}]}
            """.utf8)
        XCTAssertEqual(try FarmLiveStreetAliasVerifier.verifiedRoadName(data: roadData, candidateStreet: "East Park Street"), "E Park St")
        XCTAssertNil(try FarmLiveStreetAliasVerifier.verifiedRoadName(data: roadData, candidateStreet: "South Tennessee Avenue"))
        let intersection = Data("""
            {"features":[{"properties":{"name":"E Park St","tilequery":{"distance":3}}},
            {"properties":{"name":"S Tennessee Ave","tilequery":{"distance":4}}}]}
            """.utf8)
        XCTAssertNil(try FarmLiveStreetAliasVerifier.verifiedRoadName(data: intersection, candidateStreet: "East Park Street"))
        XCTAssertTrue(FarmLiveMatchIndex.needsLocalStreetVerification("east parks street", "east park street"))
        XCTAssertFalse(FarmLiveMatchIndex.needsLocalStreetVerification("east parks street", "west park street"))
        XCTAssertFalse(FarmLiveMatchIndex.needsLocalStreetVerification("east park road", "east park street"))
        let duplicate = AddressFeature(id: UUID().uuidString, geometry: source.geometry, properties: .init(
            id: UUID().uuidString, houseNumber: "214", streetName: "Mains St", postalCode: "33803"))
        XCTAssertTrue(FarmLiveMatchIndex(addresses: [source, duplicate], buildings: []).streetAliasChecks(candidates).isEmpty)
        let far = AddressFeature(id: id.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-79.8, 44.9])), properties: source.properties)
        XCTAssertTrue(FarmLiveMatchIndex(addresses: [far], buildings: []).streetAliasChecks(candidates).isEmpty)
    }
    func testIndependentNearbyLookupDoesNotDelayCompletedProperty() {
        let ready = target()
        let near = FarmLiveAddressTarget(id: "near", parcelId: "near", buildingId: nil,
            geometry: geometry(), coordinate: .init(latitude: 43.9006, longitude: -78.7995))
        let far = FarmLiveAddressTarget(id: "far", parcelId: "far", buildingId: nil,
            geometry: geometry(), coordinate: .init(latitude: 43.91, longitude: -78.7995))
        XCTAssertEqual(FarmLiveAddressNumberMatcher.readyTargets([ready], pending: [near]), [ready.id])
        XCTAssertEqual(FarmLiveAddressNumberMatcher.readyTargets([ready], pending: [far]), [ready.id])
    }
    func testSharedRoofWaitsForPendingSibling() {
        let a = FarmLiveAddressTarget(id: "a", parcelId: "a", buildingId: "shared", geometry: geometry(), coordinate: target().coordinate)
        let b = FarmLiveAddressTarget(id: "b", parcelId: "b", buildingId: "shared", geometry: geometry(), coordinate: target().coordinate)
        XCTAssertTrue(FarmLiveAddressNumberMatcher.readyTargets([a], pending: [b]).isEmpty)
        XCTAssertEqual(FarmLiveAddressNumberMatcher.readyTargets([a, b], pending: []), ["a", "b"])
    }

    private func repairAddress(_ id: UUID, number: String = "12", roof: String? = nil, parcel: String? = nil) -> AddressFeature {
        AddressFeature(id: id.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7, 43.95])),
            properties: .init(id: id.uuidString, buildingGersId: roof, houseNumber: number, streetName: "Main Street",
                parcelId: parcel))
    }

    private func autoEvidence(_ id: UUID, locked: Bool? = false, confirmed: Bool? = false) -> FarmLiveLinkEvidence {
        .init(addressID: id.uuidString, linkSource: "auto", userConfirmed: confirmed, locked: locked)
    }

    func testStaleAutomaticLinkIsReviewableButUnknownLockedAndManualAreProtected() throws {
        let id = UUID()
        let stale = repairAddress(id, roof: "old-roof")
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let candidates = [(target(), candidate)]
        XCTAssertTrue(FarmLiveMatchIndex(addresses: [stale], buildings: []).shortlist(candidates).isEmpty)
        for evidence in [autoEvidence(id, locked: true), autoEvidence(id, confirmed: true), autoEvidence(id, locked: nil)] {
            XCTAssertTrue(FarmLiveMatchIndex(addresses: [stale], buildings: [], evidence: [evidence]).shortlist(candidates).isEmpty)
        }
        let index = FarmLiveMatchIndex(addresses: [stale], buildings: [], evidence: [autoEvidence(id)])
        XCTAssertEqual(index.placements(candidates: candidates, visibleEntries: index.shortlist(candidates)).count, 1)
        var edits = CampaignMapEditState()
        edits.features[CampaignMapEdits.addressItem(stale).id] = .init(buildingLinkSet: true, buildingId: "saved-roof")
        XCTAssertTrue(FarmLiveMatchIndex(addresses: [stale], buildings: [], edits: edits, evidence: [autoEvidence(id)]).shortlist(candidates).isEmpty)
    }

    func testSnapshotAdvancePreservesUnrelatedPropertiesAndSharedRoofOccupants() throws {
        let moving = UUID(), staying = UUID(), other = UUID()
        let original = repairAddress(moving, roof: "old-roof", parcel: "old-parcel")
        let sibling = repairAddress(staying, number: "14", roof: "roof-a", parcel: "parcel-a")
        let unrelated = repairAddress(other, number: "16", roof: "unrelated", parcel: "unrelated")
        let buildings = try [building("old-roof"), building(), building("unrelated")]
        let parcels = [parcel("old-parcel"), parcel(), parcel("unrelated")]
        let addresses = [original, sibling, unrelated]
        let placement = FarmLiveMatchIndex.Placement(addressID: moving,
            target: .init(id: "new", parcelId: "parcel-a", buildingId: "roof-a", geometry: geometry(), coordinate: target().coordinate),
            coordinate: target().coordinate)
        let index = FarmLiveMatchIndex(addresses: [original], buildings: [], evidence: [autoEvidence(moving)])
        let replacements = index.renderFeatures(for: [placement])
        let result = FarmLiveMatchIndex.advancingSnapshot(buildings: buildings, addresses: addresses,
            parcels: parcels, replacements: replacements)
        let change = CampaignMapEditPlanner.addressPlacement(addressId: moving.uuidString,
            coordinate: placement.coordinate, buildingId: "roof-a", parcelId: "parcel-a", state: .init(), sourceRevision: nil)
        let full = CampaignMapEdits.snapshot(buildings: Array(buildings.prefix(2)), addresses: addresses,
            parcels: Array(parcels.prefix(2)), state: CampaignMapEditState().applying([change]))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(Array(result.buildings.prefix(2))), try encoder.encode(full.buildings))
        XCTAssertEqual(try encoder.encode(Array(result.parcels.prefix(2))), try encoder.encode(full.parcels))
        XCTAssertEqual(try encoder.encode(result.addresses), try encoder.encode(full.addresses))
        XCTAssertEqual(try encoder.encode(result.buildings[2]), try encoder.encode(buildings[2]))
        XCTAssertEqual(try encoder.encode(result.parcels[2]), try encoder.encode(parcels[2]))
        XCTAssertEqual(Set(result.buildings[1].properties.addressIds.map { $0.lowercased() }),
            Set([moving, staying].map { $0.uuidString.lowercased() }))
    }

    func testOccupiedParcelWaitsForVerifiedRelocationChain() throws {
        let first = UUID(), second = UUID()
        let a = repairAddress(first), b = repairAddress(second, number: "14", parcel: "parcel-a")
        let firstTarget = target()
        let secondTarget = FarmLiveAddressTarget(id: "parcel:b", parcelId: "b", buildingId: nil, geometry: geometry(), coordinate: target().coordinate)
        let firstCandidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: firstTarget))
        let secondCandidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(number: "14"), target: secondTarget))
        let index = FarmLiveMatchIndex(addresses: [a, b], buildings: [], evidence: [autoEvidence(second)])
        let partial = [(firstTarget, firstCandidate)]
        XCTAssertTrue(index.placements(candidates: partial, visibleEntries: index.shortlist(partial)).isEmpty)
        let complete = partial + [(secondTarget, secondCandidate)]
        XCTAssertEqual(index.placements(candidates: complete, visibleEntries: index.shortlist(complete)).count, 2)
        XCTAssertTrue(index.placements(candidates: complete, visibleEntries: index.shortlist(complete), readyTargetIDs: [firstTarget.id]).isEmpty)
        let protected = FarmLiveMatchIndex(addresses: [a, b], buildings: [])
        XCTAssertTrue(protected.placements(candidates: complete, visibleEntries: protected.shortlist(complete)).isEmpty)
    }

    func testParcelOnlyCorrectionCanFillHouseOnlyOnSavedParcel() throws {
        let id = UUID(), address = repairAddress(id, roof: "stale-roof")
        var edits = CampaignMapEditState()
        edits.features[CampaignMapEdits.addressItem(address).id] = .init(parcelLinkSet: true, parcelId: "parcel-a")
        let roof = try building()
        let index = FarmLiveMatchIndex(addresses: [address], buildings: [roof], edits: edits, parcels: [parcel()])
        let own = FarmLiveAddressTarget(id: "parcel:parcel-a", parcelId: "parcel-a", buildingId: "roof-a", geometry: geometry(), coordinate: target().coordinate)
        let other = FarmLiveAddressTarget(id: "parcel:b", parcelId: "b", buildingId: "roof-a", geometry: geometry(), coordinate: target().coordinate)
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: own))
        let ownCandidates = [(own, candidate)], otherCandidates = [(other, candidate)]
        XCTAssertEqual(index.placements(candidates: ownCandidates, visibleEntries: index.shortlist(ownCandidates)).count, 1)
        XCTAssertTrue(index.placements(candidates: otherCandidates, visibleEntries: index.shortlist(otherCandidates)).isEmpty)
    }

    func testParcelSaveExplicitlyClearsInheritedBuilding() {
        let change = CampaignMapEditPlanner.addressParcelLink(addressId: UUID().uuidString, parcelId: "new-parcel", coordinate: target().coordinate, state: .init(), sourceRevision: nil)
        XCTAssertEqual(change.value?.buildingLinkSet, true)
        XCTAssertNil(change.value?.buildingId)
    }

    func testMearnsActualParcelsRepair43And35TogetherAndChoose47House() throws {
        struct Fixture: Decodable { let parcels: [ParcelFeature]; let buildings: [BuildingFeature] }
        let data = Data(#"{"buildings":[{"type":"Feature","id":"durham_buildings:223385","geometry":{"type":"Polygon","coordinates":[[[-78.67118328809738,43.915366601638226],[-78.6711685359478,43.91532216171598],[-78.67109477519989,43.915334720827786],[-78.67110952734947,43.915379160740656],[-78.67118328809738,43.915366601638226]]]},"properties":{"gers_id":"durham_buildings:223385","height_m":5.5,"scans_total":0,"min_height":0,"height":5.5,"address_count":0,"area_sqm":30.34,"units_count":1,"is_townhome":false,"id":"durham_buildings:223385","canonical_building_id":"durham_buildings:223385","address_ids":[],"building_id":"durham_buildings:223385","source":"durham_buildings","scans_today":0,"status":"not_visited","is_linked":false,"feature_status":"matched","feature_type":"matched_house"}},{"type":"Feature","id":"durham_buildings:223403","geometry":{"type":"Polygon","coordinates":[[[-78.67128252983093,43.91528255219211],[-78.67125704884529,43.91522168872598],[-78.67126643657684,43.91521975655144],[-78.67123022675514,43.91513184254316],[-78.67112562060356,43.91515406257949],[-78.67112025618553,43.91514343560664],[-78.67106929421425,43.91515406257949],[-78.67110148072243,43.91523231568485],[-78.67107599973679,43.915238112207106],[-78.67109075188637,43.91527578958781],[-78.67110684514046,43.915271925242195],[-78.67112562060356,43.91531636520193],[-78.67128252983093,43.91528255219211]]]},"properties":{"gers_id":"durham_buildings:223403","height_m":5.5,"scans_total":0,"min_height":0,"height":5.5,"address_count":0,"area_sqm":239.66,"units_count":1,"is_townhome":false,"id":"durham_buildings:223403","canonical_building_id":"durham_buildings:223403","address_ids":[],"building_id":"durham_buildings:223403","source":"durham_buildings","scans_today":0,"status":"not_visited","is_linked":false,"feature_status":"matched","feature_type":"matched_house"}},{"type":"Feature","id":"durham_buildings:223770","geometry":{"type":"Polygon","coordinates":[[[-78.67106258869171,43.91468647397821],[-78.67099955677986,43.914546389901034],[-78.67089092731476,43.914571508449484],[-78.67093116044998,43.91465942328557],[-78.6709526181221,43.91465459280343],[-78.67097675800323,43.91470579589404],[-78.67106258869171,43.91468647397821]]]},"properties":{"gers_id":"durham_buildings:223770","height_m":5.5,"scans_total":0,"min_height":0,"height":5.5,"address_count":0,"area_sqm":138.08,"units_count":1,"is_townhome":false,"id":"durham_buildings:223770","canonical_building_id":"durham_buildings:223770","address_ids":[],"building_id":"durham_buildings:223770","source":"durham_buildings","scans_today":0,"status":"not_visited","is_linked":false,"feature_status":"matched","feature_type":"matched_house"}},{"type":"Feature","id":"durham_buildings:223846","geometry":{"type":"Polygon","coordinates":[[[-78.67119267582893,43.91498499687705],[-78.67114707827568,43.914876794575406],[-78.67101162672043,43.914906743446465],[-78.67105722427368,43.915014945693656],[-78.67119267582893,43.91498499687705]]]},"properties":{"gers_id":"durham_buildings:223846","scans_today":0,"match_method":"point_on_surface","area_sqm":143.6,"house_number":"35","address_text":"35 Mearns AVE, BOWMANVILLE ON L1C6N6","address_id":"16523c10-aa3e-5833-a42f-2107518f63f3","address_ids":["16523c10-aa3e-5833-a42f-2107518f63f3"],"is_townhome":false,"is_linked":true,"building_id":"durham_buildings:223846","street_name":"Mearns AVE","min_height":0,"units_count":1,"id":"durham_buildings:223846","canonical_building_id":"durham_buildings:223846","status":"not_visited","address_count":1,"feature_status":"matched","source":"durham_buildings","feature_type":"matched_house","height_m":5.5,"height":5.5,"scans_total":0,"confidence":0.9}},{"type":"Feature","id":"durham_buildings:224238","geometry":{"type":"Polygon","coordinates":[[[-78.67123827338219,43.91509223289259],[-78.67119267582893,43.91498499687705],[-78.67105722427368,43.915014945693656],[-78.67106258869171,43.91502460659899],[-78.67103308439255,43.915031369231826],[-78.67104917764664,43.91507001283318],[-78.67103174328804,43.91507291110227],[-78.67103210857945,43.91507379622439],[-78.67103174328804,43.91507387719193],[-78.67104649543762,43.915108656409444],[-78.67109477519989,43.915098029428464],[-78.67110416293144,43.91512218165522],[-78.67123827338219,43.91509223289259]]]},"properties":{"gers_id":"durham_buildings:224238","height_m":5.5,"scans_total":0,"min_height":0,"height":5.5,"address_count":0,"area_sqm":169.1,"units_count":1,"is_townhome":false,"id":"durham_buildings:224238","canonical_building_id":"durham_buildings:224238","address_ids":[],"building_id":"durham_buildings:224238","source":"durham_buildings","scans_today":0,"status":"not_visited","is_linked":false,"feature_status":"matched","feature_type":"matched_house"}}],"parcels":[{"type":"Feature","id":"266310102","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.670944571,43.915477701],[-78.67086947,43.915187876],[-78.671309352,43.915087402],[-78.671438098,43.915384957],[-78.670944571,43.915477701]]]]},"properties":{"id":"4fa94ece-ec88-4b69-abc4-20b04294a1a1","parcel_id":"266310102","external_id":"266310102","source":"bedrock_pmtiles","area_sqm":1311.12,"address_ids":[]}},{"type":"Feature","id":"266310103","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.67086947,43.915187876],[-78.670837283,43.915068081],[-78.671261072,43.914971472],[-78.671309352,43.915087402],[-78.67086947,43.915187876]]]]},"properties":{"id":"29f10603-3724-4761-be0e-1c65638fc182","parcel_id":"266310103","external_id":"266310103","source":"bedrock_pmtiles","area_sqm":489.61,"address_ids":[]}},{"type":"Feature","id":"266310104","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.670837283,43.915068081],[-78.670810461,43.914948285],[-78.671207428,43.914855541],[-78.671261072,43.914971472],[-78.670837283,43.915068081]]]]},"properties":{"id":"b02bd3b1-7193-401a-9172-9f72337048ef","parcel_id":"266310104","external_id":"266310104","source":"bedrock_pmtiles","area_sqm":465.66,"address_ids":[]}},{"type":"Feature","id":"266310106","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.670762181,43.91476666],[-78.670713902,43.914588898],[-78.671057224,43.91451161],[-78.671132326,43.914685508],[-78.670762181,43.91476666]]]]},"properties":{"id":"576bda09-f420-44b2-a5a8-e875e8767cc8","parcel_id":"266310106","external_id":"266310106","source":"bedrock_pmtiles","area_sqm":603.4,"address_ids":[]}}]}"#.utf8)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let id35 = UUID(uuidString: "16523c10-aa3e-5833-a42f-2107518f63f3")!
        let id43 = UUID(uuidString: "2245239e-b197-5da4-a68f-db9d29906109")!
        let a35 = AddressFeature(id: id35.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.6712852120399,43.9149878951503])),
            properties: .init(id: id35.uuidString, buildingGersId: "durham_buildings:223846", houseNumber: "35", streetName: "Mearns Avenue"))
        let a43 = AddressFeature(id: id43.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.6719182133675,43.9164428104907])),
            properties: .init(id: id43.uuidString, buildingGersId: "durham_buildings:223432", houseNumber: "43", streetName: "Mearns Avenue"))
        var edits = CampaignMapEditState()
        edits.features[CampaignMapEdits.addressItem(a43).id] = .init(parcelLinkSet: true, parcelId: "b02bd3b1-7193-401a-9172-9f72337048ef")
        let index = FarmLiveMatchIndex(addresses: [a35, a43], buildings: fixture.buildings, edits: edits,
            evidence: [autoEvidence(id35)], parcels: fixture.parcels)
        let targets = FarmLiveAddressGeometry.targets(parcels: fixture.parcels, buildings: fixture.buildings,
            addresses: [a35, a43], reviewableAddressIDs: index.lookupAddressIDs,
            repairableAddressIDs: index.reviewableAddressIDs, repairParcelIDs: index.repairParcelIDs)
        let t35 = try XCTUnwrap(targets.first { $0.parcelId == "266310106" })
        let t43 = try XCTUnwrap(targets.first { $0.parcelId == "266310104" })
        XCTAssertEqual(t35.buildingId, "durham_buildings:223770")
        XCTAssertEqual(t43.buildingId, "durham_buildings:223846")
        XCTAssertEqual(targets.first { $0.parcelId == "266310102" }?.buildingId, "durham_buildings:223403")
        func candidate(_ number: String, _ target: FarmLiveAddressTarget) throws -> BuildingAddressCandidate {
            let data = try JSONSerialization.data(withJSONObject: ["features": [["geometry": ["coordinates": [target.coordinate.longitude, target.coordinate.latitude]],
                "properties": ["coordinates": ["accuracy": "parcel"], "context": ["address": ["address_number": number, "street_name": "Mearns Avenue"]]]]]])
            return try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: data, target: target))
        }
        let partial = [(t43, try candidate("43", t43))]
        XCTAssertTrue(index.placements(candidates: partial, visibleEntries: index.shortlist(partial)).isEmpty)
        let complete = partial + [(t35, try candidate("35", t35))]
        let placements = index.placements(candidates: complete, visibleEntries: index.shortlist(complete))
        XCTAssertEqual(Set(placements.map(\.addressID)), [id35, id43])
        for placement in placements {
            let roof = try XCTUnwrap(fixture.buildings.first { $0.properties.canonicalBuildingIdentifier == placement.target.buildingId })
            XCTAssertTrue(CampaignMapEditPlanner.contains(roof.geometry, placement.coordinate))
            XCTAssertTrue(CampaignMapEditPlanner.contains(placement.target.geometry, placement.coordinate))
        }
    }

    func testAlreadyLinkedAutomaticHomeDoesNotGenerateTemporaryNumber() throws {
        let id = UUID()
        let address = repairAddress(id, roof: "roof-a", parcel: "parcel-a")
        let index = FarmLiveMatchIndex(addresses: [address], buildings: [try building()], evidence: [autoEvidence(id)], parcels: [parcel()])
        XCTAssertTrue(index.reviewableAddressIDs.contains(id.uuidString.lowercased()))
        XCTAssertFalse(index.lookupAddressIDs.contains(id.uuidString.lowercased()))
        XCTAssertTrue(FarmLiveAddressGeometry.targets(parcels: [parcel()], buildings: [try building()], addresses: [address],
            reviewableAddressIDs: index.lookupAddressIDs, repairableAddressIDs: index.reviewableAddressIDs,
            repairParcelIDs: index.repairParcelIDs).isEmpty)
        // Even a building-only base link suppresses a second number on that house.
        let roofOnly = repairAddress(id, roof: "roof-a")
        let roofIndex = FarmLiveMatchIndex(addresses: [roofOnly], buildings: [try building()], evidence: [autoEvidence(id)])
        XCTAssertTrue(FarmLiveAddressGeometry.targets(parcels: [parcel()], buildings: [try building()], addresses: [roofOnly],
            reviewableAddressIDs: roofIndex.lookupAddressIDs, repairableAddressIDs: roofIndex.reviewableAddressIDs,
            repairParcelIDs: roofIndex.repairParcelIDs).isEmpty)
    }

    func testMatchWorkKeyIgnoresOrderingButTracksEvidenceAndReadiness() {
        let a = FarmLiveMatchWork.key(sourceRevision: "source", completionRevision: 2, candidateIDs: ["a", "b"], readyIDs: ["a"])
        XCTAssertEqual(a, FarmLiveMatchWork.key(sourceRevision: "source", completionRevision: 2, candidateIDs: ["b", "a"], readyIDs: ["a"]))
        XCTAssertNotEqual(a, FarmLiveMatchWork.key(sourceRevision: "source", completionRevision: 3, candidateIDs: ["a", "b"], readyIDs: ["a"]))
        XCTAssertNotEqual(a, FarmLiveMatchWork.key(sourceRevision: "source", completionRevision: 2, candidateIDs: ["a", "b"], readyIDs: ["a", "b"]))
        XCTAssertNotEqual(a, FarmLiveMatchWork.key(sourceRevision: "edit", completionRevision: 2, candidateIDs: ["a", "b"], readyIDs: ["a"]))
    }

    func testRenderedMatchMovesExistingRecordAndRetainsCivicIdentity() throws {
        let id = UUID()
        let address = repairAddress(id, roof: "old")
        let index = FarmLiveMatchIndex(addresses: [address], buildings: [], evidence: [autoEvidence(id)])
        let placement = FarmLiveMatchIndex.Placement(addressID: id, target: target(), coordinate: target().coordinate)
        let features = index.renderFeatures(for: [placement])
        let feature = try XCTUnwrap(features.first)
        XCTAssertEqual(features.count, 1)
        XCTAssertEqual(feature.properties.id, id.uuidString)
        XCTAssertEqual(feature.properties.houseNumber, "12")
        XCTAssertEqual(feature.properties.streetName, "Main Street")
        XCTAssertEqual(feature.properties.parcelId, "parcel-a")
        XCTAssertNil(feature.properties.buildingGersId)
        XCTAssertEqual(feature.geometry.asPoint, [-78.7995, 43.9005])
        XCTAssertEqual(index.previousBuildingIDs(for: [placement]), ["old"])
    }

    func testTappedTemporaryNumberReusesStreetAddressWithoutChangingSource() throws {
        let id = UUID()
        let streetPin = repairAddress(id, number: "26")
        let roofTarget = FarmLiveAddressTarget(id: "parcel:parcel-a", parcelId: "parcel-a", buildingId: "roof-a",
            geometry: geometry(), coordinate: target().coordinate)
        // Foreground matching renders a single existing record, independent of the farm index.
        let index = FarmLiveMatchIndex(addresses: [streetPin], buildings: [])
        let placement = FarmLiveMatchIndex.Placement(addressID: id, target: roofTarget, coordinate: roofTarget.coordinate)
        let rendered = try XCTUnwrap(index.renderFeatures(for: [placement]).first)
        XCTAssertEqual(rendered.properties.id, streetPin.properties.id)
        XCTAssertEqual(rendered.properties.houseNumber, "26")
        XCTAssertEqual(rendered.properties.buildingGersId, "roof-a")
        XCTAssertEqual(rendered.properties.parcelId, "parcel-a")
        XCTAssertEqual(rendered.geometry.asPoint, [-78.7995, 43.9005])
        XCTAssertEqual(streetPin.geometry.asPoint, [-78.7, 43.95], "Undo must retain the imported street position")
        XCTAssertTrue(index.applying([placement]).lookupAddressIDs.isEmpty)
    }

    func testNearestPickerCanRenderConfirmedSavedAddressWithoutEnablingAutomaticRelinking() throws {
        let id = UUID()
        let saved = repairAddress(id, number: "26", roof: "old-roof", parcel: "old-parcel")
        let unrelated = repairAddress(UUID(), number: "28")
        let index = FarmLiveMatchIndex(addresses: [saved, unrelated], buildings: [])
        let roofTarget = FarmLiveAddressTarget(id: "parcel:parcel-a", parcelId: "parcel-a", buildingId: "roof-a",
            geometry: geometry(), coordinate: target().coordinate)
        let placement = FarmLiveMatchIndex.Placement(addressID: id, target: roofTarget, coordinate: roofTarget.coordinate)
        XCTAssertFalse(index.reviewableAddressIDs.contains(id.uuidString.lowercased()))
        XCTAssertTrue(index.renderFeatures(for: [placement]).isEmpty)
        let rendered = index.renderFeatures(for: [placement], confirmedAddresses: [saved, unrelated])
        XCTAssertEqual(rendered.count, 1)
        let feature = try XCTUnwrap(rendered.first)
        XCTAssertEqual(feature.properties.id, saved.properties.id)
        XCTAssertEqual(feature.properties.houseNumber, "26")
        XCTAssertEqual(feature.properties.buildingGersId, "roof-a")
        XCTAssertEqual(feature.properties.parcelId, "parcel-a")
        XCTAssertEqual(feature.geometry.asPoint, [-78.7995, 43.9005])
        XCTAssertEqual(saved.properties.buildingGersId, "old-roof")
        XCTAssertEqual(saved.properties.parcelId, "old-parcel")
        XCTAssertEqual(saved.geometry.asPoint, [-78.7, 43.95])
        XCTAssertFalse(index.reviewableAddressIDs.contains(id.uuidString.lowercased()), "Rendering a manual choice must not loosen automatic eligibility")
    }

    func testParcelTapIndexUsesCorrectedOwnersAndNormalizesTileAliases() {
        let moved = UUID(), neighbour = UUID()
        let before = MapLayerManager.parcelTapAddressIndex([
            moved.uuidString: ["old-lot"], neighbour.uuidString: ["other-lot"]])
        let after = MapLayerManager.parcelTapAddressIndex([
            moved.uuidString: ["PARCEL:new-lot", "campaign-lot"], neighbour.uuidString: ["other-lot"]])
        XCTAssertEqual(before["old-lot"], [moved])
        XCTAssertNil(after["old-lot"])
        XCTAssertEqual(after["new-lot"], [moved])
        XCTAssertEqual(after["campaign-lot"], [moved])
        XCTAssertEqual(after["other-lot"], [neighbour])
        XCTAssertTrue(MapLayerManager.parcelTapAddressIndex([:]).isEmpty)
    }

    func testParcelStateReplayIncludesOnlyChangedLotsAndRemainingSharedOwners() {
        let previous = ["a": ["old", "alias-old"], "b": ["shared"], "c": ["untouched"]]
        let next = ["a": ["shared"], "b": ["shared"], "c": ["untouched"]]
        XCTAssertEqual(MapLayerManager.changedParcelLinkIDs(previous: previous, next: next), ["old", "alias-old", "shared"])
        XCTAssertTrue(MapLayerManager.changedParcelLinkIDs(previous: next, next: next).isEmpty)
        var farm = Dictionary(uniqueKeysWithValues: (0..<14_000).map { ("address-\($0)", ["parcel-\($0)"]) })
        let old = farm
        farm["address-7"] = ["new"]
        XCTAssertEqual(MapLayerManager.changedParcelLinkIDs(previous: old, next: farm), ["parcel-7", "new"])
    }

    func testCanonicalReplacementFilterScalesWithCorrectionsInsteadOfFarmSize() throws {
        let expression = VectorTileDiamondGeometryProvider.canonicalAddressIdentityFilter(included: nil, excluded: ["replaced-1", "replaced-2"])
        let data = try JSONEncoder().encode(expression)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(encoded.contains("replaced-1"))
        XCTAssertTrue(encoded.contains("replaced-2"))
        XCTAssertTrue(encoded.contains("canonical_id"))
        XCTAssertLessThan(data.count, 200)
        let scoped = try JSONEncoder().encode(VectorTileDiamondGeometryProvider.canonicalAddressIdentityFilter(included: ["allowed"], excluded: ["replaced"]))
        XCTAssertTrue(String(decoding: scoped, as: UTF8.self).contains("allowed"))
        XCTAssertFalse(String(decoding: scoped, as: UTF8.self).contains("replaced"))
    }

    func testStephensGulchActualOrphansMatchAcrossStreetCoordinates() throws {
        struct Fixture: Decodable { let addresses: [AddressFeature]; let parcels: [ParcelFeature]; let buildings: [BuildingFeature] }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(#"{"addresses":[{"type":"Feature","id":"23bb0bde-6cfd-58d6-ae78-6fc26e28aae7","geometry":{"type":"Point","coordinates":[-78.681099415,43.9291945]},"properties":{"id":"23bb0bde-6cfd-58d6-ae78-6fc26e28aae7","source":"bedrock_ca","gers_id":"bedrock_ca:nar:1a3e24ab-3a5e-4d20-9a26-7d59a181d477","locality":"BOWMANVILLE","formatted":"14 Stephens Gulch DR, BOWMANVILLE ON L1C5L5","postal_code":"L1C5L5","street_name":"Stephens Gulch DR","house_number":"14","building_gers_id":null,"house_number_label":"14","label_priority":14,"has_building_link":false,"has_parcel_link":false,"label_visibility_mode":"hidden","origin":"bedrock_ca","provisional":false,"feature_id":"address:23bb0bde-6cfd-58d6-ae78-6fc26e28aae7","canonical_id":"23bb0bde-6cfd-58d6-ae78-6fc26e28aae7","row_id":"23bb0bde-6cfd-58d6-ae78-6fc26e28aae7","address_id":"23bb0bde-6cfd-58d6-ae78-6fc26e28aae7"}},{"type":"Feature","id":"4a34966a-515d-50a7-a6be-a1d5968714e7","geometry":{"type":"Point","coordinates":[-78.681248277,43.929675497]},"properties":{"id":"4a34966a-515d-50a7-a6be-a1d5968714e7","source":"bedrock_ca","gers_id":"bedrock_ca:nar:55fdd444-841b-489d-9e08-571a2f5ed466","locality":"BOWMANVILLE","formatted":"30 Stephens Gulch DR, BOWMANVILLE ON L1C5L5","postal_code":"L1C5L5","street_name":"Stephens Gulch DR","house_number":"30","building_gers_id":null,"house_number_label":"30","label_priority":30,"has_building_link":false,"has_parcel_link":false,"label_visibility_mode":"hidden","origin":"bedrock_ca","provisional":false,"feature_id":"address:4a34966a-515d-50a7-a6be-a1d5968714e7","canonical_id":"4a34966a-515d-50a7-a6be-a1d5968714e7","row_id":"4a34966a-515d-50a7-a6be-a1d5968714e7","address_id":"4a34966a-515d-50a7-a6be-a1d5968714e7"}},{"type":"Feature","id":"829ad9b1-912d-5e06-a1ce-40277c1ad712","geometry":{"type":"Point","coordinates":[-78.681248277,43.929713165]},"properties":{"id":"829ad9b1-912d-5e06-a1ce-40277c1ad712","source":"bedrock_ca","gers_id":"bedrock_ca:nar:a86beae2-62f3-49e7-a017-cc7fb534d161","locality":"BOWMANVILLE","formatted":"34 Stephens Gulch DR, BOWMANVILLE ON L1C5L5","postal_code":"L1C5L5","street_name":"Stephens Gulch DR","house_number":"34","building_gers_id":null,"house_number_label":"34","label_priority":34,"has_building_link":false,"has_parcel_link":false,"label_visibility_mode":"hidden","origin":"bedrock_ca","provisional":false,"feature_id":"address:829ad9b1-912d-5e06-a1ce-40277c1ad712","canonical_id":"829ad9b1-912d-5e06-a1ce-40277c1ad712","row_id":"829ad9b1-912d-5e06-a1ce-40277c1ad712","address_id":"829ad9b1-912d-5e06-a1ce-40277c1ad712"}},{"type":"Feature","id":"e6c27c5d-11ae-5b96-a08d-0904338ad595","geometry":{"type":"Point","coordinates":[-78.681248277,43.929539311]},"properties":{"id":"e6c27c5d-11ae-5b96-a08d-0904338ad595","source":"bedrock_ca","gers_id":"bedrock_ca:nar:46f3e68a-3234-45d4-bf51-38dcdbe6db4d","locality":"BOWMANVILLE","formatted":"26 Stephens Gulch DR, BOWMANVILLE ON L1C5L5","postal_code":"L1C5L5","street_name":"Stephens Gulch DR","house_number":"26","building_gers_id":null,"house_number_label":"26","label_priority":26,"has_building_link":false,"has_parcel_link":false,"label_visibility_mode":"hidden","origin":"bedrock_ca","provisional":false,"feature_id":"address:e6c27c5d-11ae-5b96-a08d-0904338ad595","canonical_id":"e6c27c5d-11ae-5b96-a08d-0904338ad595","row_id":"e6c27c5d-11ae-5b96-a08d-0904338ad595","address_id":"e6c27c5d-11ae-5b96-a08d-0904338ad595"}},{"type":"Feature","id":"ee4098dc-7968-560e-a915-c670b31642fc","geometry":{"type":"Point","coordinates":[-78.681248277,43.92940216]},"properties":{"id":"ee4098dc-7968-560e-a915-c670b31642fc","source":"bedrock_ca","gers_id":"bedrock_ca:nar:a53fc811-dbe1-473b-9cba-7b07137d54c9","locality":"BOWMANVILLE","formatted":"18 Stephens Gulch DR, BOWMANVILLE ON L1C5L5","postal_code":"L1C5L5","street_name":"Stephens Gulch DR","house_number":"18","building_gers_id":null,"house_number_label":"18","label_priority":18,"has_building_link":false,"has_parcel_link":false,"label_visibility_mode":"hidden","origin":"bedrock_ca","provisional":false,"feature_id":"address:ee4098dc-7968-560e-a915-c670b31642fc","canonical_id":"ee4098dc-7968-560e-a915-c670b31642fc","row_id":"ee4098dc-7968-560e-a915-c670b31642fc","address_id":"ee4098dc-7968-560e-a915-c670b31642fc"}}],"parcels":[{"type":"Feature","id":"266191018","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.681260347,43.929287223],[-78.681212068,43.929233134],[-78.681153059,43.929190637],[-78.681550026,43.92895883],[-78.681614399,43.929024508],[-78.681668043,43.929144275],[-78.681260347,43.929287223]]]]},"properties":{"parcel_id":"266191018","area_sqm":708.14,"address_ids":[],"source":"bedrock_pmtiles","id":"a1597d97-41c3-4f23-84a2-4e0271e63655","external_id":"266191018"}},{"type":"Feature","id":"266191019","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.681319356,43.929399262],[-78.681260347,43.929287223],[-78.681668043,43.929144275],[-78.681748509,43.929325857],[-78.681319356,43.929399262]]]]},"properties":{"parcel_id":"266191019","area_sqm":615.4,"address_ids":[],"source":"bedrock_pmtiles","id":"0c721cd5-5dcd-4b72-8e8b-bd032fd2e821","external_id":"266191019"}},{"type":"Feature","id":"266191021","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.681904078,43.929689019],[-78.681437373,43.929631067],[-78.68142128,43.92957698],[-78.681383729,43.929526755],[-78.681807518,43.929461077],[-78.681904078,43.929689019]]]]},"properties":{"parcel_id":"266191021","area_sqm":657.09,"address_ids":[],"source":"bedrock_pmtiles","id":"525e4682-538c-401d-8909-42084bc8c469","external_id":"266191021"}},{"type":"Feature","id":"266191022","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.681984544,43.930052178],[-78.681399822,43.929731516],[-78.681432009,43.929677428],[-78.681437373,43.929631067],[-78.681904078,43.929689019],[-78.682059646,43.930032861],[-78.681984544,43.930052178]]]]},"properties":{"parcel_id":"266191022","area_sqm":1174.29,"address_ids":[],"source":"bedrock_pmtiles","id":"c3355721-def7-4c9b-b8d4-805c2ffa50b6","external_id":"266191022"}},{"type":"Feature","id":"266191023","geometry":{"type":"MultiPolygon","coordinates":[[[[-78.681625128,43.930141036],[-78.681287169,43.929820374],[-78.681313992,43.92979333],[-78.681362271,43.929766287],[-78.681399822,43.929731516],[-78.681984544,43.930052178],[-78.681625128,43.930141036]]]]},"properties":{"parcel_id":"266191023","area_sqm":1041.06,"address_ids":[],"source":"bedrock_pmtiles","id":"4fabdd2f-f342-4842-9850-84b6efe73837","external_id":"266191023"}}],"buildings":[{"type":"Feature","id":"durham_buildings:167483","geometry":{"type":"Polygon","coordinates":[[[-78.68171095848083,43.929522891679284],[-78.68153393268585,43.92952192582422],[-78.68153393268585,43.92960981857041],[-78.68171095848083,43.92960981857041],[-78.68171095848083,43.929522891679284]]]},"properties":{"units_count":1,"height":5.5,"scans_total":0,"scans_today":0,"is_linked":false,"height_m":5.5,"building_id":"durham_buildings:167483","gers_id":"durham_buildings:167483","canonical_building_id":"durham_buildings:167483","feature_status":"matched","status":"not_visited","feature_type":"matched_house","min_height":0,"id":"durham_buildings:167483","area_sqm":137.96,"address_ids":[],"is_townhome":false,"source":"durham_buildings","address_count":0}},{"type":"Feature","id":"durham_buildings:167503","geometry":{"type":"Polygon","coordinates":[[[-78.68171364068985,43.92971895993162],[-78.68152186274529,43.92966970146597],[-78.68149504065514,43.929723789190774],[-78.68153795599937,43.929734413559515],[-78.68152320384979,43.929764354952084],[-78.68152361444633,43.929764460562],[-78.68152320384979,43.92976532080323],[-78.68167340755463,43.92980298898476],[-78.68171364068985,43.92971895993162]]]},"properties":{"units_count":1,"height":5.5,"scans_total":0,"scans_today":0,"is_linked":false,"height_m":5.5,"building_id":"durham_buildings:167503","gers_id":"durham_buildings:167503","canonical_building_id":"durham_buildings:167503","feature_status":"matched","status":"not_visited","feature_type":"matched_house","min_height":0,"id":"durham_buildings:167503","area_sqm":148.71,"address_ids":[],"is_townhome":false,"source":"durham_buildings","address_count":0}},{"type":"Feature","id":"durham_buildings:167521","geometry":{"type":"Polygon","coordinates":[[[-78.68159830570221,43.9298918471647],[-78.68147358298302,43.92980298898476],[-78.68144273757935,43.92982423769203],[-78.68142127990723,43.9298087840875],[-78.68136495351791,43.92985031564061],[-78.68146419525146,43.929919856780856],[-78.68143066763878,43.92994400299111],[-78.68145614862442,43.92996235410433],[-78.6814896762371,43.92993820790153],[-78.68151247501373,43.92995462732051],[-78.68159830570221,43.9298918471647]]]},"properties":{"units_count":1,"height":5.5,"scans_total":0,"scans_today":0,"is_linked":false,"height_m":5.5,"building_id":"durham_buildings:167521","gers_id":"durham_buildings:167521","canonical_building_id":"durham_buildings:167521","feature_status":"matched","status":"not_visited","feature_type":"matched_house","min_height":0,"id":"durham_buildings:167521","area_sqm":164.33,"address_ids":[],"is_townhome":false,"source":"durham_buildings","address_count":0}},{"type":"Feature","id":"durham_buildings:167894","geometry":{"type":"Polygon","coordinates":[[[-78.68162378668785,43.92930364217841],[-78.68158623576164,43.929222509999676],[-78.68133947253227,43.92928142742619],[-78.68137702345848,43.92936255952458],[-78.68162378668785,43.92930364217841]]]},"properties":{"units_count":1,"height":5.5,"scans_total":0,"scans_today":0,"is_linked":false,"height_m":5.5,"building_id":"durham_buildings:167894","gers_id":"durham_buildings:167894","canonical_building_id":"durham_buildings:167894","feature_status":"matched","status":"not_visited","feature_type":"matched_house","min_height":0,"id":"durham_buildings:167894","area_sqm":197.06,"address_ids":[],"is_townhome":false,"source":"durham_buildings","address_count":0}},{"type":"Feature","id":"durham_buildings:260068","geometry":{"type":"Polygon","coordinates":[[[-78.68151783943176,43.92914041184898],[-78.6814534664154,43.929071835659784],[-78.68140786886215,43.929095016352306],[-78.68140384554863,43.92909115290419],[-78.68125230073929,43.92916649009737],[-78.68129789829254,43.929213817259665],[-78.68131935596466,43.92920319279793],[-78.6813434958458,43.92922830515897],[-78.68151783943176,43.92914041184898]]]},"properties":{"units_count":1,"height":5.5,"scans_total":0,"scans_today":0,"is_linked":false,"height_m":5.5,"building_id":"durham_buildings:260068","gers_id":"durham_buildings:260068","canonical_building_id":"durham_buildings:260068","feature_status":"matched","status":"not_visited","feature_type":"matched_house","min_height":0,"id":"durham_buildings:260068","area_sqm":178.18,"address_ids":[],"is_townhome":false,"source":"durham_buildings","address_count":0}}]}"#.utf8))
        let index = FarmLiveMatchIndex(addresses: fixture.addresses, buildings: fixture.buildings, parcels: fixture.parcels)
        XCTAssertEqual(index.lookupAddressIDs.count, 5)
        let targets = FarmLiveAddressGeometry.targets(parcels: fixture.parcels, buildings: fixture.buildings,
            addresses: fixture.addresses, reviewableAddressIDs: index.lookupAddressIDs)
        XCTAssertEqual(targets.count, 5)
        let numbers = ["266191018": "14", "266191019": "18", "266191021": "26", "266191022": "30", "266191023": "34"]
        var candidates: [(FarmLiveAddressTarget, BuildingAddressCandidate)] = []
        for target in targets {
            let number = try XCTUnwrap(target.parcelId.flatMap { numbers[$0] })
            let data = try JSONSerialization.data(withJSONObject: ["features": [["geometry": ["coordinates": [target.coordinate.longitude, target.coordinate.latitude]],
                "properties": ["coordinates": ["accuracy": "rooftop"], "context": ["address": ["address_number": number, "street_name": "Stephens Gulch Drive"], "postcode": ["name": "L1C 5L5"]]]]]])
            let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: data, target: target))
            candidates.append((target, candidate))
        }
        XCTAssertEqual(index.shortlist(candidates).count, 5)
        XCTAssertEqual(index.placements(candidates: candidates, visibleEntries: index.shortlist(candidates)).count, 5)
    }

    func testPreparedViewSnapshotAdvancesWithoutRecomputingOrKeepingStaleDerivedValues() {
        let cache = SessionMapGeometryCache()
        let _: [Int] = cache.value(for: "addresses", key: "old") { [1] }
        let _: [Int] = cache.value(for: "targets", key: "old") { [99] }
        XCTAssertTrue(cache.advance(from: "old", to: "new", replacements: ["addresses": [2, 3]]))
        let addresses: [Int] = cache.value(for: "addresses", key: "new") { XCTFail("Committed arrays must already be prepared"); return [] }
        XCTAssertEqual(addresses, [2, 3])
        let targets: [Int] = cache.value(for: "targets", key: "new") { [4] }
        XCTAssertEqual(targets, [4], "Old derived targets must be invalidated")
        XCTAssertFalse(cache.advance(from: "old", to: "stale", replacements: ["addresses": [9]]))
        let stillCurrent: [Int]? = cache.cachedValue(for: "addresses", key: "new")
        XCTAssertEqual(stillCurrent, [2, 3])
    }

    func testPreparationPaddingScalesToVisibleArea() {
        let viewport = [-78.8, 43.9, -78.799, 43.901]
        let bounds = FarmLiveMatchWork.preparationBounds(viewport: viewport)
        XCTAssertTrue(FarmLiveAddressGeometry.covers(bounds, viewport: viewport))
        XCTAssertLessThan(bounds[2] - bounds[0], 0.002)
        XCTAssertLessThan(bounds[3] - bounds[1], 0.002)
    }

    func testIncrementalCommitRemovesResolvedOrphanAndProtectsNewOwnership() throws {
        let first = UUID(), second = UUID()
        let index = FarmLiveMatchIndex(addresses: [repairAddress(first), repairAddress(second, number: "14")], buildings: [])
        let firstCandidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let firstCandidates = [(target(), firstCandidate)]
        let planned = index.placements(candidates: firstCandidates, visibleEntries: index.shortlist(firstCandidates))
        XCTAssertEqual(planned.count, 1)
        let advanced = index.applying(planned)
        XCTAssertTrue(advanced.shortlist(firstCandidates).isEmpty)
        XCTAssertFalse(advanced.reviewableAddressIDs.contains(first.uuidString.lowercased()))
        XCTAssertTrue(advanced.reviewableAddressIDs.contains(second.uuidString.lowercased()))
        let secondCandidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(number: "14"), target: target()))
        let secondCandidates = [(target(), secondCandidate)]
        XCTAssertEqual(advanced.shortlist(secondCandidates).count, 1)
        XCTAssertTrue(advanced.placements(candidates: secondCandidates, visibleEntries: advanced.shortlist(secondCandidates)).isEmpty)
        XCTAssertTrue(advanced.applying(planned).shortlist(firstCandidates).isEmpty)
    }

    func testPreparedAreaReusedUntilViewportLeavesIt() {
        XCTAssertTrue(FarmLiveAddressGeometry.covers([-79, 43, -78, 44], viewport: [-78.9, 43.1, -78.1, 43.9]))
        XCTAssertTrue(FarmLiveAddressGeometry.covers([-79, 43, -78, 44], viewport: [-79, 43, -78, 44]))
        XCTAssertFalse(FarmLiveAddressGeometry.covers([-79, 43, -78, 44], viewport: [-79.01, 43.1, -78.1, 43.9]))
        XCTAssertFalse(FarmLiveAddressGeometry.covers([], viewport: [-79, 43, -78, 44]))
    }

    func testPreparedShapeMatchesExactContainmentForHolesAndMultiplePolygons() throws {
        let shapes = [
            MapFeatureGeoJSONGeometry(type: "Polygon", coordinates: .init(polygon: [
                [[0,0],[4,0],[4,4],[0,4],[0,0]], [[1,1],[3,1],[3,3],[1,3],[1,1]]])),
            MapFeatureGeoJSONGeometry(type: "MultiPolygon", coordinates: .init(multiPolygon: [
                [[[0,0],[1,0],[1,1],[0,1],[0,0]]], [[[3,3],[4,3],[4,4],[3,4],[3,3]]]]))
        ]
        for shape in shapes {
            let prepared = try XCTUnwrap(FarmLiveAddressGeometry.PreparedShape(shape))
            for x in stride(from: -0.5, through: 4.5, by: 0.25) {
                for y in stride(from: -0.5, through: 4.5, by: 0.25) {
                    let point = CLLocationCoordinate2D(latitude: y, longitude: x)
                    XCTAssertEqual(prepared.contains(point), CampaignMapEditPlanner.contains(shape, point))
                }
            }
            XCTAssertTrue(prepared.contains(try XCTUnwrap(prepared.interiorPoint)))
        }
    }

    func testGroupedDisplayDeduplicationPreservesDistinctNumbers() throws {
        let first = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(number: "71"), target: target()))
        let second = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(number: "75"), target: target()))
        XCTAssertEqual(FarmLiveSuggestionDisplay.uniqueIDs([("c", second), ("b", first), ("a", first)]), ["a", "c"])
        // Presentation deduplication must not remove evidence from the matcher.
        XCTAssertTrue(FarmLiveAddressNumberMatcher.uniquePairs(targets: [("a", "71"), ("b", "71")], addresses: [(UUID(), "71")]).isEmpty)
    }

    func testIndexedMatchingPreservesAmbiguityAndExcludesLinkedAddresses() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let firstID = UUID(), secondID = UUID()
        func address(_ id: UUID, linked: Bool = false) -> AddressFeature {
            let feature = AddressFeature(id: id.uuidString,
                geometry: .init(type: "Point", coordinates: .init(point: [-78.7995, 43.9005])),
                properties: .init(id: id.uuidString, houseNumber: "12", streetName: "Main Street", hasParcelLink: linked))
            return feature
        }
        let candidates = [(target(), candidate)]
        let ambiguous = FarmLiveMatchIndex(addresses: [address(firstID), address(secondID)], buildings: [])
        let entries = ambiguous.shortlist(candidates)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(ambiguous.placements(candidates: candidates, visibleEntries: entries).isEmpty)
        let unique = FarmLiveMatchIndex(addresses: [address(firstID), address(secondID, linked: true)], buildings: [])
        let matches = unique.placements(candidates: candidates, visibleEntries: unique.shortlist(candidates))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.addressID, firstID)
        XCTAssertEqual(matches.first?.target.parcelId, "parcel-a")
    }

    func testNearbyAddressMatchesEvenWhenItsPointIsOffscreen() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let id = UUID()
        let address = AddressFeature(id: id.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.80005, 43.9005])),
            properties: .init(id: id.uuidString, houseNumber: "12", streetName: "Main Street"))
        let index = FarmLiveMatchIndex(addresses: [address], buildings: [])
        let candidates = [(target(), candidate)]
        let entries = index.shortlist(candidates)
        XCTAssertEqual(index.placements(candidates: candidates, visibleEntries: entries).first?.addressID, id)
    }

    func testOrphanLookupUsesWholeFarmAndRespectsSavedLinks() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let id = UUID()
        let address = AddressFeature(id: id.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7, 43.95])),
            properties: .init(id: id.uuidString, houseNumber: "12", streetName: "Main Street"))
        let candidates = [(target(), candidate)]
        let index = FarmLiveMatchIndex(addresses: [address], buildings: [])
        XCTAssertEqual(index.placements(candidates: candidates, visibleEntries: index.shortlist(candidates)).first?.addressID, id)

        var edits = CampaignMapEditState()
        edits.features[CampaignMapEdits.addressItem(address).id] = CampaignMapEditValue(buildingLinkSet: true, buildingId: "already-linked")
        let linked = FarmLiveMatchIndex(addresses: [address], buildings: [], edits: edits)
        XCTAssertTrue(linked.shortlist(candidates).isEmpty)

        let duplicate = AddressFeature(id: UUID().uuidString, geometry: address.geometry,
            properties: .init(houseNumber: "12", streetName: "Main Street"))
        let ambiguous = FarmLiveMatchIndex(addresses: [address, duplicate], buildings: [])
        XCTAssertTrue(ambiguous.placements(candidates: candidates, visibleEntries: ambiguous.shortlist(candidates)).isEmpty)
    }

    func testIndexedMatchingRejectsAmbiguousTemporaryTargets() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let original = target()
        let second = FarmLiveAddressTarget(id: "other", parcelId: "other", buildingId: nil,
            geometry: original.geometry, coordinate: original.coordinate)
        let address = AddressFeature(id: UUID().uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7995, 43.9005])),
            properties: .init(houseNumber: "12", streetName: "Main Street"))
        let index = FarmLiveMatchIndex(addresses: [address], buildings: [])
        let candidates = [(original, candidate), (second, candidate)]
        let entries = index.shortlist(candidates)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(index.placements(candidates: candidates, visibleEntries: entries).isEmpty)
    }

    func testIndexedMatchingWithFourteenThousandAddresses() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let addresses = (1...14_000).map { number in
            AddressFeature(id: UUID().uuidString,
                geometry: .init(type: "Point", coordinates: .init(point: [-78.7995, 43.9005])),
                properties: .init(houseNumber: String(number), streetName: "Main Street"))
        }
        let index = FarmLiveMatchIndex(addresses: addresses, buildings: [])
        let candidates = [(target(), candidate)]
        let start = Date()
        for _ in 0..<100 {
            let entries = index.shortlist(candidates)
            XCTAssertEqual(entries.count, 1)
            let matches = index.placements(candidates: candidates, visibleEntries: entries)
            XCTAssertEqual(matches.count, 1)
            XCTAssertEqual(matches.first?.addressID.uuidString, addresses[11].id)
        }
        print("FARM_INDEX 14000 addresses, 100 matches: \(Date().timeIntervalSince(start) * 1000) ms")
    }

    func testStreetPointCanUseUniqueNearestPropertyButNeverNeighbourOrTie() throws {
        let lot = parcel()
        let streetPayload = try payload(longitude: -78.80005)
        let context = FarmLiveAddressAssociation(parcels: [lot], buildings: [])
        XCTAssertNotNil(try FarmLiveAddressGeometry.candidate(data: streetPayload, target: target(), association: context))
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data: streetPayload, target: target()))
        func neighbour(_ x: Double) -> ParcelFeature {
            .init(id: "neighbour", geometry: geometry(x, 43.9),
                  properties: .init(id: "neighbour", parcelId: "neighbour", externalId: nil,
                                   source: "municipal", areaSqm: 300, addressIds: ["linked-home"]))
        }
        let tied = FarmLiveAddressAssociation(parcels: [lot, neighbour(-78.8011)], buildings: [])
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data: streetPayload, target: target(), association: tied))
        let insideNeighbour = FarmLiveAddressAssociation(parcels: [lot, neighbour(-78.801)], buildings: [])
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data: streetPayload, target: target(), association: insideNeighbour))
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data: payload(longitude: -78.8005), target: target(), association: context))
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data: streetPayload, target: target(),
            association: FarmLiveAddressAssociation(parcels: [], buildings: [])))
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data: payload(accuracy: "interpolated", longitude: -78.80005), target: target(), association: context))
    }

    func testStreetDirectionAliasesPreserveDifferentStreetsAndHouseSuffixes() {
        func identity(_ number: String, _ street: String) -> String? {
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(houseNumber: number, streetName: street)
        }
        XCTAssertEqual(identity("416", "W Scugog Ln"), identity("416", "West Scugog Lane"))
        XCTAssertNotEqual(identity("416", "W Scugog Ln"), identity("416", "E Scugog Ln"))
        XCTAssertNotEqual(identity("416", "W Scugog Ln"), identity("416A", "W Scugog Ln"))
        XCTAssertNotEqual(identity("3", "Sunicrest Court"), identity("3", "Sunicrest Boulevard"))
    }

    func testViewportScopeIncludesOverlappingAndEnclosingRoofs() {
        let bounds = [-78.7998, 43.9002, -78.7996, 43.9004]
        XCTAssertTrue(FarmLiveAddressGeometry.intersects(geometry(), bounds: bounds))
        XCTAssertTrue(FarmLiveAddressGeometry.intersects(geometry(-78.7997, 43.9003, width: 0.001), bounds: bounds))
        XCTAssertFalse(FarmLiveAddressGeometry.intersects(geometry(-79, 44), bounds: bounds))
        XCTAssertFalse(FarmLiveAddressGeometry.intersects(geometry(), bounds: []))
    }
    func testTownhouseBatchIncludesOnlyDistinctParcelsOnSameBuilding() {
        func item(_ id: String, _ parcel: String?, _ roof: String?) -> FarmLiveAddressTarget {
            .init(id: id, parcelId: parcel, buildingId: roof, geometry: geometry(), coordinate: target().coordinate)
        }
        let selected = item("selected", "lot-1", "roof-a")
        let sibling = item("sibling", "lot-2", "ROOF-A")
        let result = FarmLiveAddressGeometry.townhouseSiblings(of: selected, targets: [
            selected, sibling, sibling, item("same-lot", "LOT-1", "roof-a"),
            item("neighbor", "lot-3", "roof-b"), item("roof-only", nil, "roof-a")])
        XCTAssertEqual(result.map(\.id), ["sibling"])
    }
    func testBuildingOnlyOrUnidentifiedRoofDoesNotTriggerRowSave() {
        let base = target()
        XCTAssertTrue(FarmLiveAddressGeometry.townhouseSiblings(of: base, targets: [base]).isEmpty)
        let roofOnly = FarmLiveAddressTarget(id: "roof", parcelId: nil, buildingId: "roof-a",
            geometry: geometry(), coordinate: base.coordinate)
        XCTAssertTrue(FarmLiveAddressGeometry.townhouseSiblings(of: roofOnly, targets: [base]).isEmpty)
    }
    func testParcelAndRoofProduceOneLookup() throws {
        let targets = FarmLiveAddressGeometry.targets(parcels:[parcel()],buildings:[try building()],addresses:[])
        XCTAssertEqual(targets.count,1); XCTAssertEqual(targets.first?.parcelId,"parcel-a")
        XCTAssertEqual(targets.first?.buildingId,"roof-a")
    }
    func testSharedTownhouseRoofLinksParcelEvenWhenRoofCenterIsOutsideLot() throws {
        let original = try building()
        let roof = BuildingFeature(id: original.id, geometry: geometry(-78.7996, 43.9, width: 0.002), properties: original.properties)
        let targets = FarmLiveAddressGeometry.targets(parcels: [parcel()], buildings: [roof], addresses: [])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.buildingId, "roof-a")
        XCTAssertEqual(targets.first?.parcelId, "parcel-a")
        XCTAssertEqual(try XCTUnwrap(targets.first).coordinate.longitude, -78.7995, accuracy: 0.0000001)
    }
    func testOffCenterRoofAnchorsSuggestionWithoutDuplicatingParcel() throws {
        let lot = parcel()
        let targets = FarmLiveAddressGeometry.targets(parcels: [lot, lot], buildings: [try building()], addresses: [])
        XCTAssertEqual(targets.count, 1)
        let point = try XCTUnwrap(targets.first?.coordinate)
        XCTAssertEqual(point.longitude, -78.7997, accuracy: 0.0000001)
        XCTAssertEqual(point.latitude, 43.9003, accuracy: 0.0000001)
    }
    func testBuildingOnlyUsesBuildingInteriorCenter() throws {
        let roof = try building()
        let targets = FarmLiveAddressGeometry.targets(parcels: [], buildings: [roof, roof], addresses: [])
        XCTAssertEqual(targets.count, 1)
        let point = try XCTUnwrap(targets.first?.coordinate)
        XCTAssertEqual(point.longitude, -78.7997, accuracy: 0.0000001)
        XCTAssertEqual(point.latitude, 43.9003, accuracy: 0.0000001)
    }
    func testBuildingFallbackAndAccessoryExclusion() throws {
        XCTAssertEqual(FarmLiveAddressGeometry.targets(parcels:[],buildings:[try building()],addresses:[]).count,1)
        XCTAssertTrue(FarmLiveAddressGeometry.targets(parcels:[],buildings:[try building(type:"garage")],addresses:[]).isEmpty)
    }
    func testOrphanPinInsideParcelDoesNotSuppressLookup() {
        let address = AddressFeature(id:"saved",geometry:.init(type:"Point",coordinates:.init(point:[-78.7995,43.9005])),
            properties:.init(id:"saved",houseNumber:"12",streetName:"Main Street"))
        XCTAssertEqual(FarmLiveAddressGeometry.targets(parcels:[parcel()],buildings:[],addresses:[address]).count, 1)
    }
    func testLinkedParcelOrLinkedRoofSuppressesBothTargets() throws {
        XCTAssertTrue(FarmLiveAddressGeometry.targets(parcels:[parcel(linked:true)],buildings:[try building()],addresses:[]).isEmpty)
        XCTAssertTrue(FarmLiveAddressGeometry.targets(parcels:[parcel()],buildings:[try building(linked:true)],addresses:[]).isEmpty)
    }
    func testPendingGeometryStopStillReceivesSuggestionsWithoutInventingCivicIdentity() throws {
        let id = UUID()
        let stop = AddressFeature(id: id.uuidString, geometry: .init(type: "Point", coordinates: .init(point: [-78.7997, 43.9003])),
            properties: .init(id: id.uuidString, gersId: "synthetic:geometry-target:parcel:parcel-a",
                buildingGersId: "roof-a", formatted: "Address pending", parcelId: "parcel-a",
                hasBuildingLink: true, hasParcelLink: true))
        let index = FarmLiveMatchIndex(addresses: [stop], buildings: [try building()], parcels: [parcel()])
        XCTAssertTrue(FarmLiveMatchIndex.isPendingGeometryStop(stop))
        XCTAssertTrue(index.lookupAddressIDs.contains(id.uuidString.lowercased()))
        let targets = FarmLiveAddressGeometry.targets(parcels: [parcel()], buildings: [try building()],
            addresses: [stop], reviewableAddressIDs: index.lookupAddressIDs)
        XCTAssertEqual(targets.count, 1, "Placeholder ownership must not suppress live Mapbox lookups")
        XCTAssertEqual(targets.first?.showsTemporaryPin, false, "Use the existing stop's marker; add only the temporary number")
        let emptyLot = FarmLiveAddressGeometry.targets(parcels: [parcel()], buildings: [try building()], addresses: [])
        XCTAssertEqual(emptyLot.first?.showsTemporaryPin, true, "An unowned lot still needs its temporary marker")
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        XCTAssertTrue(index.shortlist([(target(), candidate)]).isEmpty, "A pending stop is not a known civic address")
    }

    func testPendingGeometryStopOnlyYieldsAfterUnusedStopCheck() throws {
        let pendingID = UUID(), nativeID = UUID()
        let pending = AddressFeature(id: pendingID.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7997, 43.9003])),
            properties: .init(id: pendingID.uuidString, gersId: "synthetic:geometry-target:parcel:parcel-a",
                buildingGersId: "roof-a", formatted: "Address pending", parcelId: "parcel-a",
                hasBuildingLink: true, hasParcelLink: true))
        let native = AddressFeature(id: nativeID.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7, 43.95])),
            properties: .init(id: nativeID.uuidString, houseNumber: "12", streetName: "Main Street"))
        let index = FarmLiveMatchIndex(addresses: [pending, native], buildings: [try building()], parcels: [parcel()])
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data: payload(), target: target()))
        let house = FarmLiveAddressTarget(id: "parcel:parcel-a", parcelId: "parcel-a", buildingId: "roof-a",
            geometry: geometry(), coordinate: target().coordinate)
        let candidates = [(house, candidate)]
        XCTAssertEqual(index.shortlist(candidates).map(\.id), [nativeID])
        XCTAssertTrue(index.placements(candidates: candidates, visibleEntries: index.shortlist(candidates)).isEmpty,
            "A temporary result must not displace another stop's identity or history")

        let unused = FarmLiveMatchIndex(addresses: [pending, native], buildings: [try building()],
            parcels: [parcel()], unusedGeometryStopIDs: [pendingID])
        let placements = unused.placements(candidates: candidates, visibleEntries: unused.shortlist(candidates))
        let placement = try XCTUnwrap(placements.first)
        XCTAssertEqual(placement.addressID, nativeID)
        XCTAssertEqual(placement.supersededAddressIDs, [pendingID])
        XCTAssertTrue(unused.applying(placements).lookupAddressIDs.isDisjoint(with: [pendingID.uuidString.lowercased()]))
        let replacements = unused.renderFeatures(for: placements)
        let snapshot = FarmLiveMatchIndex.advancingSnapshot(buildings: [try building()], addresses: [native],
            parcels: [parcel()], replacements: replacements)
        XCTAssertEqual(snapshot.addresses.count, 1)
        XCTAssertEqual(Set(snapshot.buildings[0].properties.addressIds.map { $0.lowercased() }), [nativeID.uuidString.lowercased()])

        var edits = CampaignMapEditState()
        edits.features[CampaignMapItem(.address, pendingID.uuidString).id] = .init(geometry: pending.geometry)
        let manuallyEdited = FarmLiveMatchIndex(addresses: [pending, native], buildings: [try building()],
            edits: edits, parcels: [parcel()], unusedGeometryStopIDs: [pendingID])
        XCTAssertTrue(manuallyEdited.placements(candidates: candidates, visibleEntries: manuallyEdited.shortlist(candidates)).isEmpty)
        let evidence = try JSONDecoder().decode([FarmLiveLinkEvidence].self, from: Data("""
            [{"address_id":"\(pendingID.uuidString)","link_source":"auto","user_confirmed":false,"locked":true}]
            """.utf8))
        let locked = FarmLiveMatchIndex(addresses: [pending, native], buildings: [try building()],
            evidence: evidence, parcels: [parcel()], unusedGeometryStopIDs: [pendingID])
        XCTAssertTrue(locked.placements(candidates: candidates, visibleEntries: locked.shortlist(candidates)).isEmpty)
    }

    func testConfirmedGeometryStopKeepsItsExistingAddressProtection() throws {
        let id = UUID()
        let stop = AddressFeature(id: id.uuidString, geometry: .init(type: "Point", coordinates: .init(point: [-78.7997, 43.9003])),
            properties: .init(id: id.uuidString, gersId: "synthetic:geometry-target:building:roof-a",
                buildingGersId: "roof-a", houseNumber: "12", streetName: "Main Street",
                formatted: "12 Main Street", parcelId: "parcel-a", hasBuildingLink: true, hasParcelLink: true))
        XCTAssertFalse(FarmLiveMatchIndex.isPendingGeometryStop(stop))
        let index = FarmLiveMatchIndex(addresses: [stop], buildings: [try building()], parcels: [parcel()])
        XCTAssertTrue(index.lookupAddressIDs.isEmpty)
        XCTAssertTrue(FarmLiveAddressGeometry.targets(parcels: [parcel()], buildings: [try building()],
            addresses: [stop], reviewableAddressIDs: index.lookupAddressIDs).isEmpty)
    }

    func testUnusedPlaceholderOnAlreadyLinkedHomeDoesNotBecomeSecondUnit() throws {
        let pendingID = UUID(), nativeID = UUID()
        let pending = AddressFeature(id: pendingID.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [-78.7997, 43.9003])),
            properties: .init(id: pendingID.uuidString, gersId: "synthetic:geometry-target:parcel:parcel-a",
                buildingGersId: "roof-a", formatted: "Address pending", parcelId: "parcel-a",
                hasBuildingLink: true, hasParcelLink: true))
        let native = AddressFeature(id: nativeID.uuidString, geometry: pending.geometry,
            properties: .init(id: nativeID.uuidString, buildingGersId: "roof-a", houseNumber: "318",
                streetName: "Miramar Road", hasBuildingLink: true))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(building())) as? [String: Any])
        var properties = try XCTUnwrap(json["properties"] as? [String: Any])
        properties["address_ids"] = [pendingID.uuidString, nativeID.uuidString]
        properties["address_count"] = 2; properties["unit_count"] = 2
        properties["is_townhome"] = true; properties["is_multi_unit"] = true
        json["properties"] = properties
        let roof = try JSONDecoder().decode(BuildingFeature.self, from: JSONSerialization.data(withJSONObject: json))
        let index = FarmLiveMatchIndex(addresses: [pending, native], buildings: [roof],
            evidence: [autoEvidence(pendingID), autoEvidence(nativeID)], parcels: [parcel()], unusedGeometryStopIDs: [pendingID])
        XCTAssertEqual(index.existingLinkCandidates.count, 1, "The existing civic link needs no Mapbox lookup")
        let placements = index.placements(candidates: index.existingLinkCandidates,
            visibleEntries: index.shortlist(index.existingLinkCandidates))
        XCTAssertEqual(placements.map(\.addressID), [nativeID])
        XCTAssertEqual(placements.first?.supersededAddressIDs, [pendingID])
        let snapshot = FarmLiveMatchIndex.advancingSnapshot(buildings: [roof], addresses: [pending, native],
            parcels: [parcel()], replacements: index.renderFeatures(for: placements), hiddenAddressIDs: [pendingID])
        XCTAssertEqual(snapshot.addresses.count, 1)
        XCTAssertEqual(snapshot.buildings.first?.properties.addressCount, 1)
        XCTAssertEqual(snapshot.buildings.first?.properties.isTownhome, false)
        let protected = FarmLiveMatchIndex(addresses: [pending, native], buildings: [roof],
            evidence: [autoEvidence(pendingID), autoEvidence(nativeID)], parcels: [parcel()])
        XCTAssertTrue(protected.existingLinkCandidates.isEmpty, "Do not merge a stop without a fresh activity check")
    }

    func testParcelLookupUsesRoofInteriorInsteadOfEmptyLotCenter() throws {
        let lot = parcel()
        let roof = try building()
        let targets = FarmLiveAddressGeometry.targets(parcels: [lot], buildings: [roof], addresses: [])
        let selected = try XCTUnwrap(targets.first)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(selected.buildingId, roof.properties.canonicalBuildingIdentifier)
        let lookup = try XCTUnwrap(selected.lookupCoordinate)
        XCTAssertTrue(CampaignMapEditPlanner.contains(lot.geometry, lookup))
        XCTAssertTrue(CampaignMapEditPlanner.contains(roof.geometry, lookup))
        let lotCenter = try XCTUnwrap(FarmLiveAddressGeometry.interiorPoint(lot.geometry))
        XCTAssertFalse(CampaignMapEditPlanner.contains(roof.geometry, lotCenter), "Fixture yard centre must be outside the roof")
        XCTAssertEqual(selected.coordinate.latitude, lookup.latitude)
        XCTAssertEqual(selected.coordinate.longitude, lookup.longitude)
    }

    func testParcelOnlyFarmProducesTarget() {
        XCTAssertEqual(FarmLiveAddressGeometry.targets(parcels:[parcel()],buildings:[],addresses:[]).count,1)
    }
    func testConcaveGeometryGetsInteriorAnchor() throws {
        let g = MapFeatureGeoJSONGeometry(type:"Polygon",coordinates:.init(polygon:[[[0,0],[3,0],[3,1],[1,1],[1,3],[0,3],[0,0]]]))
        let point = try XCTUnwrap(FarmLiveAddressGeometry.interiorPoint(g))
        XCTAssertTrue(CampaignMapEditPlanner.contains(g,point))
    }
    func testHoleIsNotUsedForAnchor() throws {
        let g = MapFeatureGeoJSONGeometry(type:"Polygon",coordinates:.init(polygon:[[[0,0],[4,0],[4,4],[0,4],[0,0]],[[1,1],[3,1],[3,3],[1,3],[1,1]]]))
        let point = try XCTUnwrap(FarmLiveAddressGeometry.interiorPoint(g))
        XCTAssertTrue(CampaignMapEditPlanner.contains(g,point))
    }
    func testRejectsNeighbourWeakAndMissingHouseNumber() throws {
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data:payload(longitude:-78.7),target:target()))
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data:payload(accuracy:"approximate"),target:target()))
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data:payload(number:""),target:target()))
    }
    func testPointAccuracyInsidePropertyRemainsAnUnverifiedSuggestion() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data:payload(accuracy:"point"),target:target()))
        XCTAssertTrue(candidate.requiresConfirmation)
        XCTAssertEqual(candidate.score,0.6)
        XCTAssertNil(try FarmLiveAddressGeometry.candidate(data:payload(accuracy:"point",longitude:-78.7),target:target()))
    }
    func testAcceptedCandidateUsesOurGeometryAndRequiresConfirmation() throws {
        let candidate = try XCTUnwrap(FarmLiveAddressGeometry.candidate(data:payload(),target:target()))
        XCTAssertEqual(candidate.houseNumber,"12"); XCTAssertTrue(candidate.requiresConfirmation)
        XCTAssertEqual(candidate.coordinate.latitude,target().coordinate.latitude)
        XCTAssertTrue(candidate.isReverseGeocode)
    }
    func testLargeFarmPreparationUsesSpatialIndex() {
        let parcels = (0..<2000).map { index in
            ParcelFeature(id: "lot-\(index)", geometry: geometry(-78.8 + Double(index % 50) * 0.0015,
                43.9 + Double(index / 50) * 0.0015), properties: .init(id: "lot-\(index)", parcelId: nil,
                externalId: nil, source: "municipal", areaSqm: 300))
        }
        let start = Date()
        let targets = FarmLiveAddressGeometry.targets(parcels: parcels, buildings: [], addresses: [])
        XCTAssertEqual(targets.count, 2000)
        let elapsed = Date().timeIntervalSince(start)
        print("Live farm target preparation: 2000 parcels in \(elapsed) seconds")
        XCTAssertLessThan(elapsed, 5)
    }

    func testLookupQueriesRoofPointWhileSuggestionKeepsParcelAnchor() async throws {
        let query = CLLocationCoordinate2D(latitude: 43.9003, longitude: -78.7997)
        let base = target()
        let property = FarmLiveAddressTarget(id: base.id, parcelId: base.parcelId, buildingId: base.buildingId,
            geometry: base.geometry, coordinate: base.coordinate, lookupCoordinate: query)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FarmSuggestionURLProtocol.self]
        var requestedPoint: CLLocationCoordinate2D?
        FarmSuggestionURLProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            requestedPoint = CLLocationCoordinate2D(
                latitude: Double(items.first { $0.name == "latitude" }?.value ?? "")!,
                longitude: Double(items.first { $0.name == "longitude" }?.value ?? "")!)
            return try! self.payload()
        }
        let service = FarmLiveAddressSuggestions(session: URLSession(configuration: configuration))
        defer { service.close() }
        let resolved = await service.resolve(property)
        let result = try XCTUnwrap(resolved)
        XCTAssertEqual(try XCTUnwrap(requestedPoint).latitude, query.latitude)
        XCTAssertEqual(try XCTUnwrap(requestedPoint).longitude, query.longitude)
        XCTAssertEqual(result.coordinate.latitude, base.coordinate.latitude)
        XCTAssertEqual(result.coordinate.longitude, base.coordinate.longitude)
    }

    func testSessionCoalescesLookupsAndClearRemovesResults() async throws {
        let data = try payload()
        FarmSuggestionURLProtocol.handler = { request in
            let components = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
            XCTAssertEqual(components.queryItems?.first(where:{$0.name == "permanent"})?.value,"false")
            return data
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FarmSuggestionURLProtocol.self]
        let service = FarmLiveAddressSuggestions(session:URLSession(configuration:configuration))
        var completions = 0
        var viewInvalidations = 0
        service.onCompletion = { completions += 1 }
        let subscription = service.objectWillChange.sink { viewInvalidations += 1 }
        defer { subscription.cancel() }
        service.showStatus("Checking suggestions")
        async let first = service.resolve(target())
        async let second = service.resolve(target())
        let values = await (first,second)
        XCTAssertNotNil(values.0); XCTAssertNotNil(values.1); XCTAssertEqual(service.requestCount,1)
        _ = await service.resolve(target())
        XCTAssertEqual(service.requestCount,1)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(viewInvalidations, 0, "Lookup work must not invalidate the root map view")
        service.close()
        XCTAssertNil(service.candidate(for:target().id))
    }
}

private final class FarmSuggestionURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> Data)?
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let data = Self.handler?(request), let url = request.url else { return }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
