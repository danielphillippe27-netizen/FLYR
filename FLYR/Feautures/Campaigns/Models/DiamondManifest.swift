import Foundation

struct DiamondManifest: Codable, Equatable {
    let campaignId: String
    let diamondMode: Bool
    let geometryProvider: String?
    let geometryVersion: Int?
    let geometryUrl: URL?
    let geometryEtag: String?
    let tilejsonUrl: URL?
    let vectorTileUrlTemplate: String?
    let sourceLayers: DiamondSourceLayers?
    let promoteIds: DiamondPromoteIds?
    let joinKey: String?
    let primaryStateLayer: String?
    let bounds: [Double]?
    let minzoom: Double?
    let maxzoom: Double?
    let stateSource: String?
    let stateCursor: String?
    let supportsFeatureState: Bool
    let supportsDifferentialStateSync: Bool
    let supportsRepScope: Bool
    let fallbackGeometryProvider: String?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case diamondMode = "diamond_mode"
        case geometryProvider = "geometry_provider"
        case geometryVersion = "geometry_version"
        case geometryUrl = "geometry_url"
        case geometryEtag = "geometry_etag"
        case tilejsonUrl = "tilejson_url"
        case vectorTileUrlTemplate = "vector_tile_url_template"
        case sourceLayers = "source_layers"
        case promoteIds = "promote_ids"
        case joinKey = "join_key"
        case primaryStateLayer = "primary_state_layer"
        case bounds
        case minzoom
        case maxzoom
        case stateSource = "state_source"
        case stateCursor = "state_cursor"
        case supportsFeatureState = "supports_feature_state"
        case supportsDifferentialStateSync = "supports_differential_state_sync"
        case supportsRepScope = "supports_rep_scope"
        case fallbackGeometryProvider = "fallback_geometry_provider"
    }

    var isPMTilesGeometryProvider: Bool {
        switch geometryProvider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pmtiles", "pmtiles_zxy":
            return true
        default:
            return false
        }
    }

    var hasRenderablePMTilesGeometry: Bool {
        diamondMode &&
            isPMTilesGeometryProvider &&
            vectorTileUrlTemplate?.isEmpty == false &&
            sourceLayers?.buildings.isEmpty == false
    }

    var hasRenderablePMTilesAddresses: Bool {
        hasRenderablePMTilesAddressCylinders
    }

    var hasRenderablePMTilesAddressCylinders: Bool {
        diamondMode &&
            isPMTilesGeometryProvider &&
            vectorTileUrlTemplate?.isEmpty == false &&
            sourceLayers?.addressCircles?.isEmpty == false
    }
}

struct DiamondSourceLayers: Codable, Equatable {
    let buildings: String
    let addresses: String?
    let addressCircles: String?
    let parcels: String?

    enum CodingKeys: String, CodingKey {
        case buildings
        case addresses
        case addressCircles = "address_circles"
        case parcels
    }

    var primaryAddressLayer: String? {
        addressCircles?.isEmpty == false ? addressCircles : addresses
    }
}

struct DiamondPromoteIds: Codable, Equatable {
    let buildings: String
    let addresses: String?
    let addressCircles: String?
    let parcels: String?

    enum CodingKeys: String, CodingKey {
        case buildings
        case addresses
        case addressCircles = "address_circles"
        case parcels
    }

    var primaryAddressPromoteId: String? {
        addressCircles?.isEmpty == false ? addressCircles : addresses
    }
}
