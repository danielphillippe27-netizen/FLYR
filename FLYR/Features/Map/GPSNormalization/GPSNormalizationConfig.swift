import Foundation
import CoreLocation

struct StreetCoverageVisitConfig {
    var rollingWindowPointLimit: Int
    var rollingWindowSeconds: TimeInterval
    var minimumAcceptedPointCount: Int
    var minimumProgressSpanMeters: Double
    var minimumTraveledDistanceMeters: Double
    var corridorBufferMeters: Double
    var closeMatchDistanceMeters: Double
    var progressMarginMeters: Double
    var frontageProgressWindowMeters: Double
    var minimumSupportingSamplesAtTarget: Int
    var repeatedNearbyRadiusMeters: Double
    var minimumRepeatedNearbyPoints: Int
    var sideConfidenceMinimumSamples: Int
    var sideConfidenceMinimumLateralMeters: Double
    var crossStreetNeutralBandMeters: Double
    var strongCoverageBonusProgressMeters: Double
    var visitScoreThreshold: Double
    var reemitCooldownSeconds: TimeInterval

    static let `default` = StreetCoverageVisitConfig(
        rollingWindowPointLimit: 18,
        rollingWindowSeconds: 45,
        minimumAcceptedPointCount: 4,
        minimumProgressSpanMeters: 35,
        minimumTraveledDistanceMeters: 30,
        corridorBufferMeters: 18,
        closeMatchDistanceMeters: 10,
        progressMarginMeters: 10,
        frontageProgressWindowMeters: 12,
        minimumSupportingSamplesAtTarget: 2,
        repeatedNearbyRadiusMeters: 18,
        minimumRepeatedNearbyPoints: 2,
        sideConfidenceMinimumSamples: 2,
        sideConfidenceMinimumLateralMeters: 6,
        crossStreetNeutralBandMeters: 4,
        strongCoverageBonusProgressMeters: 55,
        visitScoreThreshold: 3,
        reemitCooldownSeconds: 30
    )
}

/// Configuration for Pro GPS Normalization Mode (corridor-snapped, side-biased breadcrumb trail).
/// All thresholds are tunable; defaults are tuned for door-knocking / walking.
struct GPSNormalizationConfig {
    /// Discard points with horizontalAccuracy <= 0 or > this value (meters).
    var maxHorizontalAccuracy: Double
    /// Ignore points closer than this to the last accepted raw point (meters).
    var minMovementDistance: Double
    /// Max lateral distance from a corridor to accept projection (meters).
    var maxLateralDeviation: Double
    /// Perpendicular offset from road centerline toward active side (meters). Positive = one side.
    var preferredSideOffset: Double
    /// Reject implied speed above this (m/s). ~2.2 m/s is fast walking.
    var maxWalkingSpeedMetersPerSecond: Double
    /// Moving average window size (number of points) for smoothing.
    var smoothingWindow: Int
    /// Allow backward progress up to this (meters) before rejecting.
    var backwardToleranceMeters: Double
    /// Douglas-Peucker tolerance for post-session simplification (meters).
    var simplificationToleranceMeters: Double
    /// Require a meaningful lateral improvement before switching corridors (legacy; used as fallback when scoring disabled).
    var corridorSwitchHysteresisMeters: Double
    /// Number of consecutive points required before committing a corridor switch.
    var corridorSwitchConfirmationPoints: Int
    /// Score advantage (current - candidate) required to allow/confirm a switch. Higher = stay on current road more.
    var switchAdvantageThreshold: Double
    /// When switching to a new corridor, require at least this progress along the candidate before committing (avoids diagonal jumps at intersections).
    var minNewCorridorProgressMeters: Double
    /// Base penalty added to candidate score when candidate is not the current corridor (continuity bias).
    var switchBasePenalty: Double
    /// When true, penalize corridors whose tangent does not align with recent movement heading.
    var headingPenaltyEnabled: Bool
    /// Reject candidate switch if heading mismatch exceeds this (degrees). Ignored when movement is very slow.
    var maxHeadingMismatchDegrees: Double
    /// If nearest road is farther than this, allow raw fallback instead of freezing.
    var maxProjectionGapBeforeRawFallbackMeters: Double
    /// When true, normalized trail is computed and used for rendering.
    var isProModeEnabled: Bool
    /// When true (e.g. debug build), show raw/normalized/corridor overlay on map.
    var showDebugOverlay: Bool
    /// Conservative second-level fallback using accepted raw path coverage on a street corridor.
    var streetCoverage: StreetCoverageVisitConfig

    init(
        maxHorizontalAccuracy: Double = 20,
        minMovementDistance: Double = 4,
        maxLateralDeviation: Double = 17,
        preferredSideOffset: Double = 5,
        // ~3.2 m/s (~11.5 km/h): brisk walk without rejecting sidewalk movement as “too fast.”
        maxWalkingSpeedMetersPerSecond: Double = 3.2,
        smoothingWindow: Int = 2,
        backwardToleranceMeters: Double = 8,
        simplificationToleranceMeters: Double = 1.5,
        corridorSwitchHysteresisMeters: Double = 7,
        corridorSwitchConfirmationPoints: Int = 3,
        switchAdvantageThreshold: Double = 6,
        minNewCorridorProgressMeters: Double = 6,
        switchBasePenalty: Double = 5,
        headingPenaltyEnabled: Bool = true,
        maxHeadingMismatchDegrees: Double = 100,
        maxProjectionGapBeforeRawFallbackMeters: Double = 45,
        isProModeEnabled: Bool = true,
        showDebugOverlay: Bool = false,
        streetCoverage: StreetCoverageVisitConfig = .default
    ) {
        self.maxHorizontalAccuracy = maxHorizontalAccuracy
        self.minMovementDistance = minMovementDistance
        self.maxLateralDeviation = maxLateralDeviation
        self.preferredSideOffset = preferredSideOffset
        self.maxWalkingSpeedMetersPerSecond = maxWalkingSpeedMetersPerSecond
        self.smoothingWindow = smoothingWindow
        self.backwardToleranceMeters = backwardToleranceMeters
        self.simplificationToleranceMeters = simplificationToleranceMeters
        self.corridorSwitchHysteresisMeters = corridorSwitchHysteresisMeters
        self.corridorSwitchConfirmationPoints = max(1, corridorSwitchConfirmationPoints)
        self.switchAdvantageThreshold = switchAdvantageThreshold
        self.minNewCorridorProgressMeters = minNewCorridorProgressMeters
        self.switchBasePenalty = switchBasePenalty
        self.headingPenaltyEnabled = headingPenaltyEnabled
        self.maxHeadingMismatchDegrees = maxHeadingMismatchDegrees
        self.maxProjectionGapBeforeRawFallbackMeters = maxProjectionGapBeforeRawFallbackMeters
        self.isProModeEnabled = isProModeEnabled
        self.showDebugOverlay = showDebugOverlay
        self.streetCoverage = streetCoverage
    }

    /// Shared default config; can later be loaded from UserDefaults or remote.
    static let `default` = GPSNormalizationConfig()
}
