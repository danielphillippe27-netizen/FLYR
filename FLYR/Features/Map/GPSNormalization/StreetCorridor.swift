import Foundation
import CoreLocation

/// A street corridor: polyline (e.g. road centerline) with optional id and precomputed cumulative distances.
struct StreetCorridor: Sendable {
    let id: String?
    let polyline: [CLLocationCoordinate2D]
    let roadName: String?
    let roadClass: String?
    private let cumulativeDistances: [Double]

    init(id: String? = nil, polyline: [CLLocationCoordinate2D], roadName: String? = nil, roadClass: String? = nil) {
        self.id = id
        self.polyline = polyline
        self.roadName = roadName
        self.roadClass = roadClass
        self.cumulativeDistances = GeospatialUtilities.cumulativeDistancesAlongPolyline(polyline)
    }

    var totalLengthMeters: Double {
        cumulativeDistances.last ?? 0
    }

    /// Cumulative distance from start to each vertex.
    func distances() -> [Double] {
        cumulativeDistances
    }

    func coordinate(atProgressMeters progressMeters: Double) -> CLLocationCoordinate2D {
        guard !polyline.isEmpty else { return CLLocationCoordinate2D() }
        guard polyline.count >= 2,
              let totalLength = cumulativeDistances.last,
              totalLength > 0 else {
            return polyline[0]
        }

        let clamped = min(max(progressMeters, 0), totalLength)
        if clamped <= 0 { return polyline[0] }
        if clamped >= totalLength { return polyline[polyline.count - 1] }

        for index in 0..<(cumulativeDistances.count - 1) {
            let startDistance = cumulativeDistances[index]
            let endDistance = cumulativeDistances[index + 1]
            guard clamped <= endDistance else { continue }

            let segmentLength = endDistance - startDistance
            guard segmentLength > 0 else { return polyline[index] }

            let ratio = (clamped - startDistance) / segmentLength
            let from = polyline[index]
            let to = polyline[index + 1]
            let latitude = from.latitude + (to.latitude - from.latitude) * ratio
            let longitude = from.longitude + (to.longitude - from.longitude) * ratio
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        return polyline[polyline.count - 1]
    }

    func slice(fromProgressMeters startProgressMeters: Double, toProgressMeters endProgressMeters: Double) -> [CLLocationCoordinate2D] {
        guard polyline.count >= 2,
              let totalLength = cumulativeDistances.last,
              totalLength > 0 else {
            return polyline
        }

        let clampedStart = min(max(startProgressMeters, 0), totalLength)
        let clampedEnd = min(max(endProgressMeters, 0), totalLength)
        let lower = min(clampedStart, clampedEnd)
        let upper = max(clampedStart, clampedEnd)

        var segment: [CLLocationCoordinate2D] = [coordinate(atProgressMeters: lower)]
        for index in 1..<(polyline.count - 1) {
            let vertexDistance = cumulativeDistances[index]
            if vertexDistance > lower && vertexDistance < upper {
                segment.append(polyline[index])
            }
        }
        segment.append(coordinate(atProgressMeters: upper))

        if clampedEnd < clampedStart {
            segment.reverse()
        }

        var deduped: [CLLocationCoordinate2D] = []
        for coordinate in segment {
            if let last = deduped.last,
               GeospatialUtilities.distanceMeters(last, coordinate) < 0.01 {
                continue
            }
            deduped.append(coordinate)
        }
        return deduped
    }
}

/// Result of projecting a point onto a corridor.
struct CorridorProjection: Sendable {
    let projectedPoint: CLLocationCoordinate2D
    let progressMeters: Double
    let segmentIndex: Int
    let lateralOffsetMeters: Double
    let corridorId: String?
    let segmentFrom: CLLocationCoordinate2D
    let segmentTo: CLLocationCoordinate2D
}

// MARK: - Build corridors from MapFeaturesService roads

extension StreetCorridor {

    /// Flatten campaign road features into a list of StreetCorridor (one per LineString or per part of MultiLineString).
    static func from(roadFeatures: [RoadFeature]) -> [StreetCorridor] {
        var corridors: [StreetCorridor] = []
        for (idx, feature) in roadFeatures.enumerated() {
            let geom = feature.geometry
            let id = feature.properties.id ?? feature.id ?? "road-\(idx)"
            let name = feature.properties.name
            let roadClass = feature.properties.roadClass
            if let line = geom.asLineString, line.count >= 2 {
                let coords = line.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                corridors.append(StreetCorridor(id: id, polyline: coords, roadName: name, roadClass: roadClass))
            } else if let multi = geom.asMultiLineString {
                for (i, line) in multi.enumerated() where line.count >= 2 {
                    let coords = line.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    corridors.append(StreetCorridor(id: "\(id)-\(i)", polyline: coords, roadName: name, roadClass: roadClass))
                }
            }
        }
        return corridors
    }
}
