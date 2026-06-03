import CoreLocation
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
