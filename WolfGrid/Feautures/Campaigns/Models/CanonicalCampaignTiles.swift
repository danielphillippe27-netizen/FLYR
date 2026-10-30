import Foundation

/// Versioned tiles are built from the finalized canonical bundle, never from a
/// regional archive. The canonical bundle remains available to field tools.
struct CanonicalCampaignTiles: Codable, Sendable {
    struct GeometryPack: Codable, Sendable {
        let url: String
        let sha256: String
        let byteLength: Int
        let count: Int
        enum CodingKeys: String, CodingKey { case url, sha256, count, byteLength = "byte_length" }
    }
    struct Layer: Codable, Sendable {
        let sourceLayer: String
        let minzoom: Int
        let maxzoom: Int
        let count: Int
        enum CodingKeys: String, CodingKey { case sourceLayer = "source_layer", minzoom, maxzoom, count }
    }
    let geometryRevision: String
    let tileURLTemplate: String
    let archiveURL: String
    let sha256: String
    let byteLength: Int
    let bounds: [Double]
    let layers: [String: Layer]
    let geometryPack: GeometryPack?
    enum CodingKeys: String, CodingKey {
        case geometryRevision = "geometry_revision", tileURLTemplate = "tile_url_template"
        case archiveURL = "archive_url", byteLength = "byte_length", sha256, bounds, layers
        case geometryPack = "geometry_pack"
    }

    func diamondManifest(campaignId: String) -> DiamondManifest? {
        guard geometryRevision.count == 64, bounds.count == 4, !tileURLTemplate.isEmpty else { return nil }
        // Prefer campaign-sized markers; existing archives can use the
        // smaller compact layer until their next rebuild.
        let circleLayer = layers["address_circles_ios"]?.sourceLayer
            ?? layers["address_circles_compact"]?.sourceLayer
            ?? layers["address_circles"]?.sourceLayer
            ?? "address_circles"
        // Each native source has a separate source layer. canonical_id is the
        // unprefixed stable ID already used by the field-state and tap handlers.
        let object: [String: Any] = [
            "campaign_id": campaignId, "diamond_mode": true,
            "geometry_provider": "pmtiles_zxy", "geometry_version": 2,
            "geometry_etag": geometryRevision, "buildings_render_mode": "vector_tiles",
            "vector_tile_url_template": tileURLTemplate,
            "address_vector_tile_url_template": tileURLTemplate,
            "parcel_vector_tile_url_template": tileURLTemplate,
            "source_layers": ["buildings": "buildings", "addresses": "addresses", "address_circles": circleLayer, "parcels": "parcels"],
            "promote_ids": ["buildings": "canonical_id", "addresses": "canonical_id", "address_circles": "canonical_id", "parcels": "canonical_id"],
            "address_source_layer": "addresses", "address_promote_id": "canonical_id",
            "parcel_source_layer": "parcels", "parcel_promote_id": "canonical_id",
            "minzoom": 10, "maxzoom": 18, "address_minzoom": 10, "address_maxzoom": 18,
            "parcel_minzoom": 10, "parcel_maxzoom": 18, "bounds": bounds,
            "supports_feature_state": true, "supports_differential_state_sync": true, "supports_rep_scope": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(DiamondManifest.self, from: data)
    }
}

extension CanonicalCampaignMapBundle {
    var tileMetadataCountsJSON: String? {
        let encoder = JSONEncoder()
        var object = counts.flatMap { try? encoder.encode($0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let tiles, let bytes = try? encoder.encode(tiles), let node = try? JSONSerialization.jsonObject(with: bytes) {
            object["canonical_tiles"] = node
        }
        if let canonicalSignature { object["canonical_signature"] = canonicalSignature }
        if let storageFormat { object["canonical_schema"] = storageFormat }
        return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension CachedCampaignMapBundleMetadata {
    var usesCompactTiles: Bool {
        guard let data = countsJSON?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["canonical_schema"] as? String == "tiles-v3"
    }

    var canonicalSignature: String? {
        guard let data = countsJSON?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["canonical_signature"] as? String
    }

    var canonicalTiles: CanonicalCampaignTiles? {
        guard let data = countsJSON?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let node = object["canonical_tiles"], let bytes = try? JSONSerialization.data(withJSONObject: node) else { return nil }
        return try? JSONDecoder().decode(CanonicalCampaignTiles.self, from: bytes)
    }
}
