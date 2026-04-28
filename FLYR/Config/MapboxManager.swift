import Foundation
import CoreLocation
import MapboxMaps

/// Manages Mapbox configuration and access tokens
class MapboxManager {
    static let shared = MapboxManager()
    
    let accessToken: String
    
    private init() {
        self.accessToken = Config.mapboxAccessToken
    }
}

enum CampaignOfflineMapError: LocalizedError {
    case missingRegionGeometry

    var errorDescription: String? {
        switch self {
        case .missingRegionGeometry:
            return "Campaign map tiles could not be downloaded because the territory shape is missing."
        }
    }
}

final class MapboxOfflineService {
    static let shared = MapboxOfflineService()

    private let offlineManager = OfflineManager()
    private let tileStore = TileStore.default
    private let zoomRange: ClosedRange<UInt8> = 6...16

    private init() {}

    func downloadCampaignRegion(
        campaignId: String,
        boundaryGeoJSON: String?,
        addresses: [AddressFeature],
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let styleURIs = [
            StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!,
            StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!
        ]

        for (index, styleURI) in styleURIs.enumerated() {
            let baseProgress = Double(index) / Double(styleURIs.count)
            try await loadStylePack(styleURI: styleURI) { progress in
                let normalized = min(max(progress, 0), 1)
                onProgress(0.05 + ((baseProgress + (normalized / Double(styleURIs.count))) * 0.35))
            }
        }

        let descriptors = styleURIs.map {
            offlineManager.createTilesetDescriptor(
                for: TilesetDescriptorOptions(styleURI: $0, zoomRange: zoomRange, tilesets: nil)
            )
        }

        let regionGeometry = try offlineRegionGeometry(boundaryGeoJSON: boundaryGeoJSON, addresses: addresses)
        try await loadTileRegion(
            regionId: tileRegionIdentifier(for: campaignId),
            geometry: regionGeometry,
            descriptors: descriptors
        ) { progress in
            let normalized = min(max(progress, 0), 1)
            onProgress(0.40 + (normalized * 0.60))
        }
    }

    private func loadStylePack(
        styleURI: StyleURI,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        guard let loadOptions = StylePackLoadOptions(
            glyphsRasterizationMode: .ideographsRasterizedLocally,
            metadata: ["scope": "campaign-offline", "style_uri": styleURI.rawValue],
            acceptExpired: false
        ) else {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            let cancellable = offlineManager.loadStylePack(
                for: styleURI,
                loadOptions: loadOptions,
                progress: { progress in
                    let required = max(progress.requiredResourceCount, 1)
                    onProgress(Double(progress.completedResourceCount) / Double(required))
                },
                completion: { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )

            _ = cancellable
        }
    }

    private func loadTileRegion(
        regionId: String,
        geometry: Geometry,
        descriptors: [TilesetDescriptor],
        onProgress: @escaping (Double) -> Void
    ) async throws {
        guard let loadOptions = TileRegionLoadOptions(
            geometry: geometry,
            descriptors: descriptors,
            metadata: ["scope": "campaign-offline", "region_id": regionId],
            acceptExpired: false
        ) else {
            throw CampaignOfflineMapError.missingRegionGeometry
        }

        try await withCheckedThrowingContinuation { continuation in
            let cancellable = tileStore.loadTileRegion(
                forId: regionId,
                loadOptions: loadOptions,
                progress: { progress in
                    let required = max(progress.requiredResourceCount, 1)
                    onProgress(Double(progress.completedResourceCount) / Double(required))
                },
                completion: { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )

            _ = cancellable
        }
    }

    private func tileRegionIdentifier(for campaignId: String) -> String {
        "campaign-offline-\(campaignId.lowercased())"
    }

    private func offlineRegionGeometry(
        boundaryGeoJSON: String?,
        addresses: [AddressFeature]
    ) throws -> Geometry {
        if let boundaryGeoJSON,
           let geometry = geometryFromBoundaryGeoJSON(boundaryGeoJSON) {
            return geometry
        }

        if let fallback = geometryFromAddresses(addresses) {
            return fallback
        }

        throw CampaignOfflineMapError.missingRegionGeometry
    }

    private func geometryFromBoundaryGeoJSON(_ geoJSON: String) -> Geometry? {
        guard let data = geoJSON.data(using: .utf8) else { return nil }

        if let polygon = try? JSONDecoder().decode(OfflinePolygonGeoJSON.self, from: data),
           polygon.type.caseInsensitiveCompare("Polygon") == .orderedSame {
            let rings = polygon.coordinates.map { ring in
                ring.map { LocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            }
            guard !rings.isEmpty else { return nil }
            return .polygon(Polygon(rings))
        }

        if let multiPolygon = try? JSONDecoder().decode(OfflineMultiPolygonGeoJSON.self, from: data),
           multiPolygon.type.caseInsensitiveCompare("MultiPolygon") == .orderedSame {
            let polygons = multiPolygon.coordinates.map { polygon in
                Polygon(
                    polygon.map { ring in
                        ring.map { LocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    }
                )
            }
            guard !polygons.isEmpty else { return nil }
            return .multiPolygon(MultiPolygon(polygons))
        }

        return nil
    }

    private func geometryFromAddresses(_ addresses: [AddressFeature]) -> Geometry? {
        let coordinates = addresses.compactMap { feature -> CLLocationCoordinate2D? in
            guard let point = feature.geometry.asPoint, point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }

        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return .point(Point(first))
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let latPadding = max((maxLat - minLat) * 0.1, 0.0015)
        let lonPadding = max((maxLon - minLon) * 0.1, 0.0015)
        let ring = [
            LocationCoordinate2D(latitude: minLat - latPadding, longitude: minLon - lonPadding),
            LocationCoordinate2D(latitude: minLat - latPadding, longitude: maxLon + lonPadding),
            LocationCoordinate2D(latitude: maxLat + latPadding, longitude: maxLon + lonPadding),
            LocationCoordinate2D(latitude: maxLat + latPadding, longitude: minLon - lonPadding),
            LocationCoordinate2D(latitude: minLat - latPadding, longitude: minLon - lonPadding)
        ]

        return .polygon(Polygon([ring]))
    }
}

private struct OfflinePolygonGeoJSON: Decodable {
    let type: String
    let coordinates: [[[Double]]]
}

private struct OfflineMultiPolygonGeoJSON: Decodable {
    let type: String
    let coordinates: [[[[Double]]]]
}




