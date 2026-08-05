import Foundation
import CoreLocation

/// Infers which side of the street the user is canvassing (for offset direction).
struct SideOfStreetInference {
    /// Target or completed building centroids near the corridor (for majority vote).
    private var candidatePoints: [CLLocationCoordinate2D]
    private var lastChosenSide: SideOfStreet = .unknown

    init(candidatePoints: [CLLocationCoordinate2D] = []) {
        self.candidatePoints = candidatePoints
    }

    mutating func updateCandidates(_ points: [CLLocationCoordinate2D]) {
        candidatePoints = points
    }

    /// Given current segment direction (from -> to) and projected point on corridor, choose left or right.
    mutating func inferSide(
        segmentFrom: CLLocationCoordinate2D,
        segmentTo: CLLocationCoordinate2D,
        projectedPoint: CLLocationCoordinate2D,
        userPoint: CLLocationCoordinate2D,
        corridorId: String?
    ) -> SideOfStreet {
        let origin = projectedPoint
        let signed = GeospatialUtilities.signedLateralOffsetMeters(
            point: userPoint,
            segmentFrom: segmentFrom,
            to: segmentTo,
            origin: origin
        )
        if abs(signed) < 2 {
            return lastChosenSide != .unknown ? lastChosenSide : .right
        }
        let side: SideOfStreet = signed > 0 ? .left : .right
        lastChosenSide = side
        if !candidatePoints.isEmpty {
            var leftCount = 0
            var rightCount = 0
            for c in candidatePoints {
                let d = GeospatialUtilities.signedLateralOffsetMeters(
                    point: c,
                    segmentFrom: segmentFrom,
                    to: segmentTo,
                    origin: origin
                )
                if d > 2 { leftCount += 1 }
                else if d < -2 { rightCount += 1 }
            }
            if leftCount > rightCount { lastChosenSide = .left }
            else if rightCount > leftCount { lastChosenSide = .right }
        }
        return lastChosenSide
    }

    mutating func reset() {
        lastChosenSide = .unknown
    }
}
