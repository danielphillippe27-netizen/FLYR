import XCTest
import CryptoKit
@testable import WolfGrid

final class CanonicalOfflinePackageTests: XCTestCase {
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
