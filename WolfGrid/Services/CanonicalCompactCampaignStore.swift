import Foundation
import CryptoKit

/// Stores compact field metadata separately from the immutable, checksummed
/// WKB package. A failed replacement never removes the last good cache.
actor CanonicalCompactCampaignStore {
    enum CacheError: Error { case invalidScope, wrongCampaign, invalidGeometry }
    static let shared = CanonicalCompactCampaignStore()
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanonicalCompactCampaigns", isDirectory: true)
    }

    func save(data: Data, campaignId: String, userId: String, workspaceId: String?, geometryURL: URL) throws -> CanonicalCompactFieldIndex {
        let index = try validatedIndex(data: data, campaignId: campaignId, geometryURL: geometryURL)
        let destination = try file(campaignId: campaignId, userId: userId, workspaceId: workspaceId)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return index
    }

    func load(campaignId: String, userId: String, workspaceId: String?, geometryURL: URL? = nil) throws -> CanonicalCompactFieldIndex? {
        let destination = try file(campaignId: campaignId, userId: userId, workspaceId: workspaceId)
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return try validatedIndex(data: Data(contentsOf: destination, options: .mappedIfSafe),
            campaignId: campaignId, geometryURL: geometryURL)
    }

    private func file(campaignId: String, userId: String, workspaceId: String?) throws -> URL {
        guard !campaignId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CacheError.invalidScope }
        let scope = try JSONEncoder().encode([userId.lowercased(), workspaceId?.lowercased() ?? "", campaignId.lowercased()])
        let name = SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(name).json")
    }

    private func validatedIndex(data: Data, campaignId: String, geometryURL: URL?) throws -> CanonicalCompactFieldIndex {
        let campaign = try JSONDecoder().decode(CanonicalCompactCampaign.self, from: data)
        guard campaign.campaignId.caseInsensitiveCompare(campaignId) == .orderedSame else { throw CacheError.wrongCampaign }
        guard let expected = campaign.tiles.geometryPack else { throw CacheError.invalidGeometry }
        let geometryURL = try geometryURL ?? CanonicalTilePackageStore.exactGeometryURL(for: campaign.tiles)
        let bytes = try Data(contentsOf: geometryURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard bytes.count == expected.byteLength, digest == expected.sha256.lowercased() else { throw CacheError.invalidGeometry }
        return try CanonicalCompactFieldIndex(campaign: campaign, pack: CanonicalGeometryPack(url: geometryURL))
    }
}
