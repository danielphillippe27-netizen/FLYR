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
    let addressVectorTileUrlTemplate: String?
    let addressSourceLayer: String?
    let addressPromoteId: String?
    let addressMinzoom: Double?
    let addressMaxzoom: Double?
    let parcelVectorTileUrlTemplate: String?
    let parcelSourceLayer: String?
    let parcelPromoteId: String?
    let parcelMinzoom: Double?
    let parcelMaxzoom: Double?
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
    let buildingsRenderMode: String?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case diamondMode = "diamond_mode"
        case geometryProvider = "geometry_provider"
        case geometryVersion = "geometry_version"
        case geometryUrl = "geometry_url"
        case geometryEtag = "geometry_etag"
        case tilejsonUrl = "tilejson_url"
        case vectorTileUrlTemplate = "vector_tile_url_template"
        case addressVectorTileUrlTemplate = "address_vector_tile_url_template"
        case addressSourceLayer = "address_source_layer"
        case addressPromoteId = "address_promote_id"
        case addressMinzoom = "address_minzoom"
        case addressMaxzoom = "address_maxzoom"
        case parcelVectorTileUrlTemplate = "parcel_vector_tile_url_template"
        case parcelSourceLayer = "parcel_source_layer"
        case parcelPromoteId = "parcel_promote_id"
        case parcelMinzoom = "parcel_minzoom"
        case parcelMaxzoom = "parcel_maxzoom"
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
        case buildingsRenderMode = "buildings_render_mode"
    }

    var isPMTilesGeometryProvider: Bool {
        switch geometryProvider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pmtiles", "pmtiles_zxy", "pmtiles_addresses":
            return true
        default:
            return false
        }
    }

    var hasRenderablePMTilesGeometry: Bool {
        diamondMode &&
            isPMTilesGeometryProvider &&
            buildingsRenderAsVectorTiles &&
            hasText(vectorTileUrlTemplate) &&
            hasText(sourceLayers?.buildings)
    }

    var hasRenderablePMTilesAddresses: Bool {
        hasRenderablePMTilesAddressCylinders || hasRenderablePMTilesAddressPoints
    }

    var hasRenderablePMTilesParcels: Bool {
        diamondMode &&
            isPMTilesGeometryProvider &&
            hasText(parcelVectorTileUrlTemplate) &&
            hasText(parcelSourceLayer ?? sourceLayers?.parcels)
    }

    var hasRenderablePMTilesAddressCylinders: Bool {
        diamondMode &&
            isPMTilesGeometryProvider &&
            hasText(addressVectorTileUrlTemplate ?? vectorTileUrlTemplate) &&
            hasText(sourceLayers?.addressCircles)
    }

    var buildingsRenderAsGeoJSON: Bool {
        switch buildingsRenderMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "geojson", "map_bundle", "map-bundle":
            return true
        default:
            return false
        }
    }

    var buildingsRenderAsVectorTiles: Bool {
        !buildingsRenderAsGeoJSON
    }

    var buildingTilesAreCampaignScoped: Bool {
        hasRenderablePMTilesGeometry
    }

    var hasRenderablePMTilesAddressPoints: Bool {
        diamondMode &&
            isPMTilesGeometryProvider &&
            hasText(addressVectorTileUrlTemplate) &&
            hasText(addressSourceLayer ?? sourceLayers?.addresses)
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DiamondSourceLayers: Codable, Equatable {
    let buildings: String?
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
    let buildings: String?
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
