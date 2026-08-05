import Foundation
import CoreLocation

// MARK: - Design rule (hard invariant)
// Visit scoring uses ACCEPTED RAW points + corridor/proximity context ONLY.
// Do NOT use the rendered display path for visit inference.

/// Configuration for scored visit inference. All thresholds tunable.
struct ScoredVisitConfig {
    /// Within this distance (m): +1. Within proximityTier2Meters: +2.
    var proximityTier1Meters: Double
    var proximityTier2Meters: Double
    /// Progress-passed + nearby: +2. Requires both proximity evidence and progress past building on same corridor.
    var progressPassedToleranceMeters: Double
    /// Dwell/slowdown bonus: +2. Only when recent accepted points remain within this radius (spatial tightness).
    var dwellSpatialTightnessMeters: Double
    /// Dwell/slowdown: minimum seconds near building to count.
    var dwellMinSeconds: Double
    /// Speed (m/s) below which we consider "slowdown" near building.
    var slowdownMaxSpeedMPS: Double
    /// Repeated accepted points within proximity: +2.
    var repeatedProximityMeters: Double
    var repeatedMinCount: Int
    /// Wrong-side penalty: apply only when side confidence unusually strong. Start tiny (e.g. -0.5).
    var wrongSidePenalty: Double
    /// Reject point if implied speed above this (m/s).
    var maxImpliedSpeedMPS: Double
    /// Score >= this to mark visited. Default 2 matches two proximity tiers at ≤10 m in a single accepted fix (typical pass-by).
    var visitThreshold: Int

    static let `default` = ScoredVisitConfig(
        proximityTier1Meters: 15,
        /// Match tier 1 so one accepted fix within campaign proximity (≤15 m) yields +2 from tiers alone (threshold 2).
        /// With tier2 at 10 m, walking paths often stayed in 11–15 m from building centroids and never scored.
        proximityTier2Meters: 15,
        progressPassedToleranceMeters: 5,
        dwellSpatialTightnessMeters: 8,
        dwellMinSeconds: 3,
        slowdownMaxSpeedMPS: 0.6,
        repeatedProximityMeters: 15,
        repeatedMinCount: 2,
        wrongSidePenalty: 0.5,
        maxImpliedSpeedMPS: 15,
        visitThreshold: 2
    )
}

/// Per-building state for scoring.
private struct BuildingScoreState {
    var score: Double
    var progressBonusAwarded: Bool
    var dwellEnteredAt: Date?
    var dwellBonusAwarded: Bool
    var recentNearbyPoints: [(date: Date, coord: CLLocationCoordinate2D)]
    var confirmedCount: Int
    var repeatedBonusAwarded: Bool
}

/// Visit inference engine: scores candidates from accepted raw + corridor context; never uses display path.
final class ScoredVisitEngine {
    private let config: ScoredVisitConfig
    private var corridors: [StreetCorridor]
    private var stateByBuilding: [String: BuildingScoreState] = [:]
    private var lastProcessedLocation: CLLocation?
    private let maxRecentPoints = 20

    init(config: ScoredVisitConfig = .default, corridors: [StreetCorridor]) {
        self.config = config
        self.corridors = corridors
    }

    func updateCorridors(_ corridors: [StreetCorridor]) {
        self.corridors = corridors
    }

    /// Process one accepted raw point. Returns building IDs that crossed the visit threshold.
    /// Caller must use accepted raw + corridor context only — never the rendered path.
    func process(
        acceptedLocation location: CLLocation,
        corridorContext: CorridorContext?,
        buildingCentroids: [String: CLLocation],
        targetBuildingIds: [String],
        alreadyCompleted: Set<String>
    ) -> [String] {
        let incomplete = targetBuildingIds.filter { !alreadyCompleted.contains($0.lowercased()) }
        guard !incomplete.isEmpty else { return [] }

        // Reject impossible speed
        if let last = lastProcessedLocation {
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            let dist = location.distance(from: last)
            if dt > 0, dist / dt > config.maxImpliedSpeedMPS {
                lastProcessedLocation = location
                return []
            }
        }
        lastProcessedLocation = location

        var toMark: [String] = []
        #if DEBUG
        var debugNearestNotMarked: (buildingId: String, distance: Double, corridorId: String?, isFallback: Bool, score: Double, reason: String)?
        let debugMaxDistance: Double = 25
        #endif
        for buildingId in incomplete {
            guard let centroid = buildingCentroids[buildingId] else { continue }
            let distance = location.distance(from: centroid)
            var state = stateByBuilding[buildingId] ?? BuildingScoreState(
                score: 0,
                progressBonusAwarded: false,
                dwellEnteredAt: nil,
                dwellBonusAwarded: false,
                recentNearbyPoints: [],
                confirmedCount: 0,
                repeatedBonusAwarded: false
            )

            var pointsThisTick: Double = 0

            // Proximity tiers
            if distance <= config.proximityTier1Meters {
                pointsThisTick += 1
                if distance <= config.proximityTier2Meters { pointsThisTick += 1 }
            }

            // Progress passed frontage + nearby (+2 once when paired with proximity)
            let progressBonus: Double
            if !state.progressBonusAwarded,
               let ctx = corridorContext, !ctx.isFallback, let cid = ctx.corridorId, distance <= config.proximityTier1Meters,
               let buildingProgress = progressMeters(of: centroid, onCorridorId: cid) {
                let passed = ctx.progressMeters >= buildingProgress - config.progressPassedToleranceMeters
                if passed {
                    progressBonus = 2
                    state.progressBonusAwarded = true
                } else {
                    progressBonus = 0
                }
            } else {
                progressBonus = 0
            }
            pointsThisTick += progressBonus

            // Dwell/slowdown: only when spatially tight and corridor consistent
            let speed = location.speed >= 0 ? location.speed : 0
            let isSlow = speed < config.slowdownMaxSpeedMPS
            state.recentNearbyPoints.append((location.timestamp, location.coordinate))
            if state.recentNearbyPoints.count > maxRecentPoints {
                state.recentNearbyPoints.removeFirst()
            }
            let tightRadius = config.dwellSpatialTightnessMeters
            let recentTight = state.recentNearbyPoints.allSatisfy { GeospatialUtilities.distanceMeters($0.coord, location.coordinate) <= tightRadius }
            let nearBuilding = distance <= config.proximityTier1Meters
            let sameCorridor = corridorContext.map { !$0.isFallback && $0.corridorId != nil } ?? false
            if isSlow && nearBuilding && (sameCorridor || corridorContext == nil) && recentTight {
                if let entered = state.dwellEnteredAt {
                    let dwellSec = location.timestamp.timeIntervalSince(entered)
                    if dwellSec >= config.dwellMinSeconds && !state.dwellBonusAwarded {
                        pointsThisTick += 2
                        state.dwellBonusAwarded = true
                    }
                } else {
                    state.dwellEnteredAt = location.timestamp
                }
            } else {
                state.dwellEnteredAt = nil
            }

            // Repeated confirmations (+2 once when enough nearby accepted points)
            if distance <= config.repeatedProximityMeters {
                state.confirmedCount += 1
                if state.confirmedCount >= config.repeatedMinCount && !state.repeatedBonusAwarded {
                    pointsThisTick += 2
                    state.repeatedBonusAwarded = true
                }
            } else {
                state.confirmedCount = 0
            }

            // Wrong-side: tiny penalty only when confidence unusually strong
            var wrongSidePenalty: Double = 0
            if let ctx = corridorContext, ctx.sideConfidenceUnusuallyStrong,
               let from = ctx.segmentFrom, let to = ctx.segmentTo {
                let buildingLateral = GeospatialUtilities.signedLateralOffsetMeters(
                    point: centroid.coordinate,
                    segmentFrom: from,
                    to: to,
                    origin: location.coordinate
                )
                let userLateral = ctx.lateralOffsetMeters
                if (buildingLateral > 2 && userLateral < -2) || (buildingLateral < -2 && userLateral > 2) {
                    wrongSidePenalty = config.wrongSidePenalty
                }
            }
            pointsThisTick -= wrongSidePenalty

            state.score += pointsThisTick
            stateByBuilding[buildingId] = state

            if Int(state.score.rounded()) >= config.visitThreshold {
                toMark.append(buildingId)
                stateByBuilding.removeValue(forKey: buildingId)
            } else {
                #if DEBUG
                if distance <= debugMaxDistance {
                    let candidate = (buildingId, distance, corridorContext?.corridorId, corridorContext?.isFallback ?? true, state.score, "score \(Int(state.score.rounded())) < \(config.visitThreshold)")
                    if debugNearestNotMarked == nil || distance < debugNearestNotMarked!.distance {
                        debugNearestNotMarked = candidate
                    }
                }
                #endif
            }
        }
        #if DEBUG
        if let d = debugNearestNotMarked, toMark.isEmpty {
            print("🏠 [ScoredVisit] nearest not marked: id=\(d.buildingId) dist_m=\(String(format: "%.1f", d.distance)) corridor=\(d.corridorId ?? "fallback") fallback=\(d.isFallback) score=\(String(format: "%.1f", d.score)) threshold=\(config.visitThreshold) reason=\(d.reason)")
        }
        #endif
        return toMark
    }

    /// Progress in meters along corridor for a point (e.g. building centroid). Nil if corridor not found or projection fails.
    private func progressMeters(of location: CLLocation, onCorridorId corridorId: String) -> Double? {
        guard let corridor = corridors.first(where: { $0.id == corridorId }) else { return nil }
        return GeospatialUtilities.nearestPointOnPolyline(point: location.coordinate, polyline: corridor.polyline)
            .map { $0.progressAlongLineMeters }
    }

    func reset() {
        stateByBuilding.removeAll()
        lastProcessedLocation = nil
    }
}
