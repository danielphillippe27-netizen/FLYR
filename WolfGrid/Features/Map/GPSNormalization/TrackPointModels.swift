import Foundation
import CoreLocation

// MARK: - Rejection reasons (for logging and debug)

enum RejectionReason: String, Sendable {
    case poorAccuracy = "poor_accuracy"
    case tooClose = "too_close"
    case tooFast = "too_fast"
    case tooFarFromCorridor = "too_far_from_corridor"
    case backwardJump = "backward_jump"
    case invalidProjection = "invalid_projection"
}

// MARK: - Side of street (relative to corridor direction)

enum SideOfStreet: String, Sendable {
    case left
    case right
    case unknown
}

// MARK: - Raw track point (accepted GPS sample)

struct RawTrackPoint: Sendable {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let horizontalAccuracy: Double
    /// Non-nil only when this point was recorded but later discarded for normalization (e.g. for debug log).
    let rejectionReason: RejectionReason?
}

// MARK: - Normalized track point (for render trail)

struct NormalizedTrackPoint: Sendable {
    let rawCoordinate: CLLocationCoordinate2D
    let rawTimestamp: Date
    let normalizedCoordinate: CLLocationCoordinate2D
    let progressAlongCorridor: Double
    let lateralOffsetMeters: Double
    let corridorId: String?
    let sideOfStreet: SideOfStreet
    let rejectionReason: RejectionReason?
}
