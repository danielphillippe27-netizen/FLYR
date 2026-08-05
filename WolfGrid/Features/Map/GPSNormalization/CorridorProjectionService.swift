import Foundation
import CoreLocation

/// Projects a point onto the nearest corridor within maxLateralDeviation.
struct CorridorProjectionService {
    private var corridors: [StreetCorridor]
    private let maxLateralDeviation: Double

    init(corridors: [StreetCorridor], maxLateralDeviation: Double) {
        self.corridors = corridors
        self.maxLateralDeviation = maxLateralDeviation
    }

    mutating func updateCorridors(_ corridors: [StreetCorridor]) {
        self.corridors = corridors
    }

    var corridorCount: Int { corridors.count }

    func corridor(withId corridorId: String) -> StreetCorridor? {
        corridors.first(where: { $0.id == corridorId })
    }

    /// Returns the raw Euclidean distance (meters) to the nearest point on any corridor. Used for debug diagnostics only.
    func nearestCorridorDistanceMeters(to point: CLLocationCoordinate2D) -> Double {
        var best = Double.infinity
        for corridor in corridors {
            guard let (projPoint, _, _) = GeospatialUtilities.nearestPointOnPolyline(point: point, polyline: corridor.polyline) else { continue }
            let d = GeospatialUtilities.distanceMeters(point, projPoint)
            if d < best { best = d }
        }
        return best
    }

    /// Find best projection among all corridors. Returns nil if none within maxLateralDeviation.
    func project(point: CLLocationCoordinate2D) -> CorridorProjection? {
        var best: CorridorProjection?
        var bestLateral = maxLateralDeviation + 1
        let origin = point
        for corridor in corridors {
            guard let (projPoint, segmentIndex, progressMeters) = GeospatialUtilities.nearestPointOnPolyline(point: point, polyline: corridor.polyline) else { continue }
            let segFrom: CLLocationCoordinate2D
            let segTo: CLLocationCoordinate2D
            let latOffset: Double
            if segmentIndex < corridor.polyline.count - 1 {
                segFrom = corridor.polyline[segmentIndex]
                segTo = corridor.polyline[segmentIndex + 1]
                latOffset = GeospatialUtilities.signedLateralOffsetMeters(
                    point: point,
                    segmentFrom: segFrom,
                    to: segTo,
                    origin: origin
                )
            } else {
                segFrom = corridor.polyline[max(0, segmentIndex - 1)]
                segTo = corridor.polyline[segmentIndex]
                latOffset = 0
            }
            let absOffset = abs(latOffset)
            if absOffset <= maxLateralDeviation && absOffset < bestLateral {
                bestLateral = absOffset
                best = CorridorProjection(
                    projectedPoint: projPoint,
                    progressMeters: progressMeters,
                    segmentIndex: segmentIndex,
                    lateralOffsetMeters: latOffset,
                    corridorId: corridor.id,
                    segmentFrom: segFrom,
                    segmentTo: segTo
                )
            }
        }
        return best
    }

    /// Project a point only onto a specific corridor ID. Returns nil if not found or outside maxLateralDeviation.
    func project(point: CLLocationCoordinate2D, onCorridorId corridorId: String?) -> CorridorProjection? {
        guard let corridorId else { return nil }
        guard let corridor = corridors.first(where: { $0.id == corridorId }) else { return nil }
        guard let (projPoint, segmentIndex, progressMeters) = GeospatialUtilities.nearestPointOnPolyline(point: point, polyline: corridor.polyline) else {
            return nil
        }
        let segFrom: CLLocationCoordinate2D
        let segTo: CLLocationCoordinate2D
        let latOffset: Double
        if segmentIndex < corridor.polyline.count - 1 {
            segFrom = corridor.polyline[segmentIndex]
            segTo = corridor.polyline[segmentIndex + 1]
            latOffset = GeospatialUtilities.signedLateralOffsetMeters(
                point: point,
                segmentFrom: segFrom,
                to: segTo,
                origin: point
            )
        } else {
            segFrom = corridor.polyline[max(0, segmentIndex - 1)]
            segTo = corridor.polyline[segmentIndex]
            latOffset = 0
        }
        guard abs(latOffset) <= maxLateralDeviation else { return nil }
        return CorridorProjection(
            projectedPoint: projPoint,
            progressMeters: progressMeters,
            segmentIndex: segmentIndex,
            lateralOffsetMeters: latOffset,
            corridorId: corridor.id,
            segmentFrom: segFrom,
            segmentTo: segTo
        )
    }
}
