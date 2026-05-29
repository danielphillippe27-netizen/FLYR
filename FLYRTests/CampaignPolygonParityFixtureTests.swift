import XCTest
@testable import FLYR

final class CampaignPolygonParityFixtureTests: XCTestCase {
    func testCanonicalParityPolygonComputesExpectedBbox() throws {
        let polygonJSON = """
        {
          "type": "Polygon",
          "coordinates": [[
            [-78.7842254687073, 43.92552044236356],
            [-78.77887337137338, 43.926841389352035],
            [-78.77749783233911, 43.92380917196115],
            [-78.78284159307286, 43.92254219970988],
            [-78.7842254687073, 43.92552044236356]
          ]]
        }
        """

        let polygon = try JSONDecoder().decode(GeoJSONPolygon.self, from: Data(polygonJSON.utf8))
        let bbox = try XCTUnwrap(CampaignsAPI.bbox(for: polygon))

        XCTAssertEqual(bbox.count, 4)
        XCTAssertEqual(bbox[0], -78.7842254687073, accuracy: 0.0000001)
        XCTAssertEqual(bbox[1], 43.92254219970988, accuracy: 0.0000001)
        XCTAssertEqual(bbox[2], -78.77749783233911, accuracy: 0.0000001)
        XCTAssertEqual(bbox[3], 43.926841389352035, accuracy: 0.0000001)
    }

    func testCanonicalParityPolygonUsesLongitudeLatitudeOrdering() throws {
        let polygon = GeoJSONPolygon(
            type: "Polygon",
            coordinates: [[
                [-78.7842254687073, 43.92552044236356],
                [-78.77887337137338, 43.926841389352035],
                [-78.77749783233911, 43.92380917196115],
                [-78.78284159307286, 43.92254219970988],
                [-78.7842254687073, 43.92552044236356]
            ]]
        )

        let first = try XCTUnwrap(polygon.coordinates.first?.first)
        let last = try XCTUnwrap(polygon.coordinates.first?.last)

        XCTAssertEqual(first[0], -78.7842254687073, accuracy: 0.0000001)
        XCTAssertEqual(first[1], 43.92552044236356, accuracy: 0.0000001)
        XCTAssertEqual(first, last)
    }
}
