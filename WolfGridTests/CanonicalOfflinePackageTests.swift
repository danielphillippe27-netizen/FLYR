import XCTest
import CryptoKit
@testable import WolfGrid

final class CanonicalOfflinePackageTests: XCTestCase {
    func testIncrementalAddressOverlayPreservesOtherPinsAndGeometryScope() throws {
        func address(_ id: UUID, longitude: Double) throws -> AddressFeature {
            let object: [String: Any] = ["type": "Feature", "id": id.uuidString,
                "geometry": ["type": "Point", "coordinates": [longitude, 43.9]],
                "properties": ["id": id.uuidString, "building_gers_id": "house", "parcel_id": "parcel"]]
            return try JSONDecoder().decode(AddressFeature.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let first = UUID(), second = UUID()
        var plan = CanonicalTileRenderPlan()
        plan.buildingIds = ["house", "other-house"]
        plan.parcelIds = ["parcel", "other-parcel"]
        plan.addressIds = [first.uuidString.lowercased(), "untouched-address"]
        plan.upsertAddressOverlay(try address(first, longitude: -78.8))
        plan.upsertAddressOverlay(try address(second, longitude: -78.7))
        plan.upsertAddressOverlay(try address(first, longitude: -78.6))
        XCTAssertEqual(plan.addressIds, ["untouched-address"])
        XCTAssertEqual(plan.addressEdits.count, 2, "Replacing an overlay must not duplicate its pin")
        XCTAssertEqual(plan.addressEdits.last?.geometry.asPoint?.first, -78.6)
        XCTAssertEqual(plan.addressEdits.first?.properties.id, second.uuidString)
        XCTAssertEqual(plan.addressEdits.last?.properties.parcelId, "parcel")
        XCTAssertEqual(plan.buildingIds, ["house", "other-house"])
        XCTAssertEqual(plan.parcelIds, ["parcel", "other-parcel"])
        XCTAssertTrue(plan.buildingEdits.isEmpty)
        XCTAssertTrue(plan.parcelEdits.isEmpty)
    }

    func testBinaryGeometryReadsBothByteOrdersAndRejectsTruncation() throws {
        let shape = CanonicalWKBGeometry.polygon([[[1, 2], [3, 4], [5, 6], [1, 2]]])
        let bytes = try CanonicalWKBWriter.encode(shape)
        var reader = CanonicalWKBReader(bytes)
        XCTAssertEqual(try reader.read(), shape)
        var truncated = CanonicalWKBReader(Data(bytes.dropLast()))
        XCTAssertThrowsError(try truncated.read())
        let bigEndianPoint = Data([0, 0, 0, 0, 1, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0, 0x40, 0, 0, 0, 0, 0, 0, 0])
        var bigEndianReader = CanonicalWKBReader(bigEndianPoint)
        XCTAssertEqual(try bigEndianReader.read(), .point([1, 2]))
    }

    func testParcelContainmentRespectsHolesAndMultipolygons() {
        let outer = [[0.0, 0.0], [10, 0], [10, 10], [0, 10], [0, 0]]
        let hole = [[3.0, 3.0], [7, 3], [7, 7], [3, 7], [3, 3]]
        let polygon = CanonicalWKBGeometry.polygon([outer, hole])
        XCTAssertTrue(CanonicalParcelFieldGeometry.contains([1, 1], in: polygon))
        XCTAssertFalse(CanonicalParcelFieldGeometry.contains([5, 5], in: polygon))
        XCTAssertFalse(CanonicalParcelFieldGeometry.contains([11, 5], in: polygon))
        let second = CanonicalWKBGeometry.polygon([[[20, 20], [25, 20], [25, 25], [20, 25], [20, 20]]])
        XCTAssertTrue(CanonicalParcelFieldGeometry.contains([22, 22], in: .multiPolygon([polygon, second])))
        XCTAssertFalse(CanonicalParcelFieldGeometry.contains([15, 15], in: .multiPolygon([polygon, second])))
    }
    func testCampaignSizedCylinderLayerHasSafeFallbackForOlderArchives() throws {
        func layer(_ name: String) -> CanonicalCampaignTiles.Layer {
            CanonicalCampaignTiles.Layer(sourceLayer: name, minzoom: 10, maxzoom: 18, count: 1)
        }
        func manifest(_ layers: [String: CanonicalCampaignTiles.Layer]) throws -> DiamondManifest {
            let tiles = CanonicalCampaignTiles(geometryRevision: String(repeating: "a", count: 64),
                tileURLTemplate: "https://example.invalid/{z}/{x}/{y}", archiveURL: "https://example.invalid/a",
                sha256: String(repeating: "b", count: 64), byteLength: 1, bounds: [0, 0, 1, 1], layers: layers, geometryPack: nil)
            return try XCTUnwrap(tiles.diamondManifest(campaignId: "test"))
        }
        let standard = layer("address_circles")
        let compact = layer("address_circles_compact")
        let ios = layer("address_circles_ios")
        XCTAssertEqual(try manifest(["address_circles": standard, "address_circles_compact": compact, "address_circles_ios": ios]).sourceLayers?.addressCircles, "address_circles_ios")
        XCTAssertEqual(try manifest(["address_circles": standard, "address_circles_compact": compact]).sourceLayers?.addressCircles, "address_circles_compact")
        XCTAssertEqual(try manifest(["address_circles": standard]).sourceLayers?.addressCircles, "address_circles")
    }

    func testReadinessRequiresCurrentVerifiedArchiveAndGeometry() async throws {
        var archive = Data(repeating: 0, count: 128)
        archive.replaceSubrange(0..<7, with: Data("PMTiles".utf8))
        archive[7] = 3; archive[8] = 127; archive[16] = 1
        archive[97] = 1; archive[98] = 1; archive[99] = 1
        let geometry = Data("WGP1".utf8) + Data(repeating: 0, count: 4)
        func digest(_ bytes: Data) -> String {
            SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let revision = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + String(repeating: "0", count: 32)
        let pack = CanonicalCampaignTiles.GeometryPack(url: "https://example.invalid/geometry", sha256: digest(geometry), byteLength: geometry.count, count: 0)
        let tiles = CanonicalCampaignTiles(geometryRevision: revision, tileURLTemplate: "https://example.invalid/{z}/{x}/{y}", archiveURL: "https://example.invalid/archive", sha256: digest(archive), byteLength: archive.count, bounds: [0, 0, 1, 1], layers: [:], geometryPack: pack)
        let archiveURL = try CanonicalTilePackageStore.archiveURL(for: tiles)
        let geometryURL = try CanonicalTilePackageStore.exactGeometryURL(for: tiles)
        defer { try? FileManager.default.removeItem(at: archiveURL); try? FileManager.default.removeItem(at: geometryURL) }
        let store = CanonicalTilePackageStore.shared
        let initiallyReady = await store.hasVerifiedPackage(tiles)
        XCTAssertFalse(initiallyReady)
        try archive.write(to: archiveURL)
        let missingGeometryReady = await store.hasVerifiedPackage(tiles)
        XCTAssertFalse(missingGeometryReady)
        try geometry.write(to: geometryURL)
        let verifiedReady = await store.hasVerifiedPackage(tiles)
        XCTAssertTrue(verifiedReady)
        try Data(repeating: 0, count: geometry.count).write(to: geometryURL)
        let corruptGeometryReady = await store.hasVerifiedPackage(tiles)
        XCTAssertFalse(corruptGeometryReady)
    }
}
