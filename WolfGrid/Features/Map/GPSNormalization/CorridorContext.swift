import Foundation
import CoreLocation

// MARK: - Projection confidence (deterministic buckets from explicit ingredients)
// Used for visit inference only. Do NOT use the rendered display path for visit scoring.

/// Confidence that the user is on a corridor, derived from:
/// - lateral deviation bucket (distance from centerline)
/// - same-corridor continuity (unchanged corridor id)
/// - no recent fallback (consecutive successful projections)
/// - corridor switch stability (not immediately after a switch)
enum ProjectionConfidence: String, Sendable {
    case high
    case medium
    case low
    case none  // fallback (no projection)
}

/// Context emitted after each accepted raw point for visit inference.
/// Visit scoring must use accepted raw points + this context only — never the displayed path.
struct CorridorContext: Sendable {
    var corridorId: String?
    var progressMeters: Double
    var lateralOffsetMeters: Double
    var projectionConfidence: ProjectionConfidence
    var isFallback: Bool
    /// Optional side-of-street; used only for a tiny penalty when sideConfidenceUnusuallyStrong.
    var sideOfStreet: SideOfStreet?
    /// True only when side inference is very confident (e.g. clear lateral + stable); then wrong-side penalty may apply (conservative).
    var sideConfidenceUnusuallyStrong: Bool
    /// Current segment (for wrong-side check: project building centroid onto segment and compare signed lateral).
    var segmentFrom: CLLocationCoordinate2D?
    var segmentTo: CLLocationCoordinate2D?
}
