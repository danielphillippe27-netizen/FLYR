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

    func testBuildingLabelCombinesStreetAliasWhenFormattedIsOnlyHouseNumber() throws {
        let buildings = try decodeBuildings("""
        [
          {
            "type": "Feature",
            "id": "chapel-building",
            "geometry": {
              "type": "Polygon",
              "coordinates": [[
                [144.9900, -37.8500],
                [144.9900, -37.8499],
                [144.9901, -37.8499],
                [144.9901, -37.8500],
                [144.9900, -37.8500]
              ]]
            },
            "properties": {
              "gers_id": "chapel-building",
              "formatted": "122",
              "house_number": "122",
              "street": "Chapel St",
              "units_count": 1,
              "address_count": 1
            }
          }
        ]
        """)

        let targets = CampaignTargetResolver.preferredSessionTargets(buildings: buildings, addresses: [])

        XCTAssertEqual(targets.first?.label, "122 Chapel St")
        XCTAssertEqual(targets.first?.houseNumber, "122")
        XCTAssertEqual(targets.first?.streetName, "Chapel St")
    }

    func testAddressFeatureDisplayDedupeCollapsesSameMiltonAddress() throws {
        let duplicateA = UUID().uuidString.lowercased()
        let duplicateB = UUID().uuidString.lowercased()
        let nextHouse = UUID().uuidString.lowercased()

        let addresses = try decodeAddresses("""
        [
          {
            "type": "Feature",
            "id": "\(duplicateA)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.86000, 43.52000]
            },
            "properties": {
              "id": "\(duplicateA)",
              "house_number": "1102",
              "street_name": "Bonin Cres",
              "locality": "Milton",
              "formatted": "1102 Bonin Cres, Milton"
            }
          },
          {
            "type": "Feature",
            "id": "\(duplicateB)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.86002, 43.52002]
            },
            "properties": {
              "id": "\(duplicateB)",
              "building_gers_id": "building-1102",
              "house_number": "1102",
              "street_name": "Bonin Crescent",
              "locality": "Milton",
              "formatted": "1102 Bonin Crescent, Milton"
            }
          },
          {
            "type": "Feature",
            "id": "\(nextHouse)",
            "geometry": {
              "type": "Point",
              "coordinates": [-79.86100, 43.52100]
            },
            "properties": {
              "id": "\(nextHouse)",
              "house_number": "1104",
              "street_name": "Bonin Crescent",
              "locality": "Milton",
              "formatted": "1104 Bonin Crescent, Milton"
            }
          }
        ]
        """)

        let deduped = CampaignTargetResolver.deduplicatedAddressFeaturesForClientDisplay(addresses)

        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped.first?.properties.id, duplicateB)
        XCTAssertEqual(Set(deduped.compactMap { $0.properties.id }), Set([duplicateB, nextHouse]))
    }

    private func decodeBuildings(_ json: String) throws -> [BuildingFeature] {
        try JSONDecoder().decode([BuildingFeature].self, from: Data(json.utf8))
    }

    private func decodeAddresses(_ json: String) throws -> [AddressFeature] {
        try JSONDecoder().decode([AddressFeature].self, from: Data(json.utf8))
    }
}
