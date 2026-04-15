import XCTest
@testable import FLYR

final class CampaignTargetResolverTests: XCTestCase {
    func testFlyerTargetsPreferAddressPointsForMultiAddressBuildings() throws {
        let addressA = UUID().uuidString.lowercased()
        let addressB = UUID().uuidString.lowercased()

        let buildings = try decodeBuildings("""
        [
          {
            "type": "Feature",
            "id": "building-1",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [-79.3800, 43.6500],
                [-79.3800, 43.6501],
                [-79.3801, 43.6501],
                [-79.3801, 43.6500],
                [-79.3800, 43.6500]
              ]]
            },
            "properties": {
              "gers_id": "building-1",
              "address_id": "\(addressA)",
              "address_text": "10 Main St",
              "units_count": 2,
              "address_count": 2
            }
          }
        ]
        """)

        let addresses = try decodeAddresses("""
        [
          {
            "type": "Feature",
            "id": "\(addressA)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.38001, 43.65001]
            },
            "properties": {
              "id": "\(addressA)",
              "building_gers_id": "building-1",
              "house_number": "10",
              "street_name": "Main St",
              "formatted": "10 Main St"
            }
          },
          {
            "type": "Feature",
            "id": "\(addressB)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.38002, 43.65002]
            },
            "properties": {
              "id": "\(addressB)",
              "building_gers_id": "building-1",
              "house_number": "12",
              "street_name": "Main St",
              "formatted": "12 Main St"
            }
          }
        ]
        """)

        let targets = CampaignTargetResolver.flyerTargets(buildings: buildings, addresses: addresses)

        XCTAssertEqual(Set(targets.map(\.id)), Set([addressA, addressB]))
        XCTAssertFalse(targets.contains(where: { $0.id == "building-1" }))
    }

    func testFlyerTargetsAddSingleAddressBuildingFallbackWhenAddressPointMissing() throws {
        let addressA = UUID().uuidString.lowercased()
        let addressB = UUID().uuidString.lowercased()

        let buildings = try decodeBuildings("""
        [
          {
            "type": "Feature",
            "id": "building-1",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [-79.3800, 43.6500],
                [-79.3800, 43.6501],
                [-79.3801, 43.6501],
                [-79.3801, 43.6500],
                [-79.3800, 43.6500]
              ]]
            },
            "properties": {
              "gers_id": "building-1",
              "address_id": "\(addressA)",
              "address_text": "10 Main St",
              "units_count": 1,
              "address_count": 1
            }
          },
          {
            "type": "Feature",
            "id": "building-2",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [-79.3810, 43.6510],
                [-79.3810, 43.6511],
                [-79.3811, 43.6511],
                [-79.3811, 43.6510],
                [-79.3810, 43.6510]
              ]]
            },
            "properties": {
              "gers_id": "building-2",
              "address_id": "\(addressB)",
              "address_text": "20 Main St",
              "units_count": 1,
              "address_count": 1
            }
          }
        ]
        """)

        let addresses = try decodeAddresses("""
        [
          {
            "type": "Feature",
            "id": "\(addressA)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.38001, 43.65001]
            },
            "properties": {
              "id": "\(addressA)",
              "building_gers_id": "building-1",
              "house_number": "10",
              "street_name": "Main St",
              "formatted": "10 Main St"
            }
          }
        ]
        """)

        let targets = CampaignTargetResolver.flyerTargets(buildings: buildings, addresses: addresses)

        XCTAssertEqual(Set(targets.map(\.id)), Set([addressA, addressB]))
    }

    func testPreferredSessionTargetsStayBuildingFirstForDoorKnocking() throws {
        let addressA = UUID().uuidString.lowercased()

        let buildings = try decodeBuildings("""
        [
          {
            "type": "Feature",
            "id": "building-1",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [-79.3800, 43.6500],
                [-79.3800, 43.6501],
                [-79.3801, 43.6501],
                [-79.3801, 43.6500],
                [-79.3800, 43.6500]
              ]]
            },
            "properties": {
              "gers_id": "building-1",
              "address_id": "\(addressA)",
              "address_text": "10 Main St",
              "units_count": 1,
              "address_count": 1
            }
          }
        ]
        """)

        let addresses = try decodeAddresses("""
        [
          {
            "type": "Feature",
            "id": "\(addressA)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.38001, 43.65001]
            },
            "properties": {
              "id": "\(addressA)",
              "building_gers_id": "building-1",
              "house_number": "10",
              "street_name": "Main St",
              "formatted": "10 Main St"
            }
          }
        ]
        """)

        let targets = CampaignTargetResolver.preferredSessionTargets(buildings: buildings, addresses: addresses)

        XCTAssertEqual(targets.map(\.id), ["building-1"])
    }

    func testPreferredSessionTargetsPreferGoldBuildingIdWhenPresent() throws {
        let goldBuildingId = UUID().uuidString.lowercased()

        let buildings = try decodeBuildings("""
        [
          {
            "type": "Feature",
            "id": "legacy-gers",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [-79.3800, 43.6500],
                [-79.3800, 43.6501],
                [-79.3801, 43.6501],
                [-79.3801, 43.6500],
                [-79.3800, 43.6500]
              ]]
            },
            "properties": {
              "id": "legacy-gers",
              "building_id": "\(goldBuildingId)",
              "gers_id": "legacy-gers",
              "address_text": "10 Main St",
              "units_count": 1,
              "address_count": 1
            }
          }
        ]
        """)

        let targets = CampaignTargetResolver.preferredSessionTargets(buildings: buildings, addresses: [])

        XCTAssertEqual(targets.map(\.id), [goldBuildingId])
        XCTAssertEqual(targets.first?.buildingId, goldBuildingId)
    }

    private func decodeBuildings(_ json: String) throws -> [BuildingFeature] {
        try JSONDecoder().decode([BuildingFeature].self, from: Data(json.utf8))
    }

    private func decodeAddresses(_ json: String) throws -> [AddressFeature] {
        try JSONDecoder().decode([AddressFeature].self, from: Data(json.utf8))
    }
}
