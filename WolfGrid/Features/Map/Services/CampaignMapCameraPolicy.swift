import CoreLocation
import CoreGraphics
import Foundation

enum CampaignMapCameraMode: Equatable {
    case idle
    case centered
    case heading3D

    func modeAfterLocationControlTap(hasLocation: Bool) -> CampaignMapCameraMode {
        guard hasLocation else { return self }
        switch self {
        case .idle:
            return .centered
        case .centered:
            return .heading3D
        case .heading3D:
            return .centered
        }
    }
}

struct CampaignMapFollowCameraSnapshot: Equatable {
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection

    static func == (lhs: CampaignMapFollowCameraSnapshot, rhs: CampaignMapFollowCameraSnapshot) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.heading == rhs.heading
    }
}

enum CampaignMapFollowCameraPolicy {
    static let minimumMovementMeters = 1.5
    static let minimumHeadingDeltaDegrees: CLLocationDirection = 3

    static func shouldUpdateCamera(
        from previous: CampaignMapFollowCameraSnapshot?,
        to next: CampaignMapFollowCameraSnapshot
    ) -> Bool {
        guard let previous else { return true }
        let movedDistance = GeospatialUtilities.distanceMeters(previous.coordinate, next.coordinate)
        let headingDelta = abs(CLLocationDirection.shortestCompassDelta(from: previous.heading, to: next.heading))
        return movedDistance >= minimumMovementMeters || headingDelta >= minimumHeadingDeltaDegrees
    }
}

struct CampaignMapCameraPose: Equatable {
    let bearing: CLLocationDirection
    let pitch: CGFloat
}

enum CampaignMapCameraDragPolicy {
    static let minimumPitch: CGFloat = 0
    static let maximumPitch: CGFloat = 75

    private static let bearingDegreesPerPoint: CGFloat = 0.35
    private static let pitchDegreesPerPoint: CGFloat = 0.25

    static func applyDrag(
        currentBearing: CLLocationDirection,
        currentPitch: CGFloat,
        dragAmount: CGSize
    ) -> CampaignMapCameraPose {
        let nextBearing = CLLocationDirection.normalizedCompassAngle(
            currentBearing + CLLocationDirection(dragAmount.width * bearingDegreesPerPoint)
        )
        let nextPitch = (currentPitch - (dragAmount.height * pitchDegreesPerPoint))
            .clamped(to: minimumPitch...maximumPitch)
        return CampaignMapCameraPose(bearing: nextBearing, pitch: nextPitch)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
