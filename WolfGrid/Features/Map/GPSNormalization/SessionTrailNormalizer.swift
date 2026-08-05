import Foundation
import CoreLocation

/// Orchestrates the Pro GPS normalization pipeline: corridor projection, progress constraint, light smoothing.
/// Live display path is centerline-snapped only (no side-of-street offset) for visual stability.
/// IMPORTANT: The rendered path is for display only. Visit inference must use accepted raw points + corridor/proximity, never this path.
final class SessionTrailNormalizer {
    private struct TraversedCorridorSample {
        let corridorId: String
        let progressMeters: Double
    }

    private let config: GPSNormalizationConfig
    private var corridorService: CorridorProjectionService
    private var sideInference: SideOfStreetInference
    private var progressConstraint: ProgressConstraint
    private var smoother: TrailSmoothing

    private var normalizedPoints: [CLLocationCoordinate2D] = []
    private var normalizedSegmentBreaks: Set<Int> = []
    private var lastCorridorId: String?
    private var pendingCorridorId: String?
    private var pendingCorridorHits: Int = 0
    /// Progress along candidate corridor when we first started considering it (for minNewCorridorProgressMeters guard).
    private var pendingCandidateProgressStart: Double?
    /// Last N accepted raw coordinates for movement-derived heading (continuity bias).
    private var lastAcceptedRawCoords: [CLLocationCoordinate2D] = []
    private let maxAcceptedRawCoords = 5
    /// Consecutive successful projections (reset on fallback). Used for confidence.
    private var consecutiveProjectionCount: Int = 0
    /// Points since last corridor switch. Used for switch stability in confidence.
    private var pointsSinceCorridorSwitch: Int = 0
    /// Sequential snapped projections, with nil separators for fallback gaps.
    private var traversedCorridorSamples: [TraversedCorridorSample?] = []

    /// Last corridor context for visit inference. Updated on each process().
    /// Do NOT use the rendered path for visit scoring — use accepted raw + this context only.
    private(set) var lastCorridorContext: CorridorContext?

    init(
        config: GPSNormalizationConfig = .default,
        corridors: [StreetCorridor],
        candidatePointsForSide: [CLLocationCoordinate2D] = []
    ) {
        self.config = config
        self.corridorService = CorridorProjectionService(corridors: corridors, maxLateralDeviation: config.maxLateralDeviation)
        self.sideInference = SideOfStreetInference(candidatePoints: candidatePointsForSide)
        self.progressConstraint = ProgressConstraint(backwardToleranceMeters: config.backwardToleranceMeters)
        self.smoother = TrailSmoothing(windowSize: config.smoothingWindow)
    }

    /// Update corridors (e.g. when campaign roads load).
    func updateCorridors(_ corridors: [StreetCorridor]) {
        corridorService.updateCorridors(corridors)
    }

    /// Update candidate points for side-of-street inference (building centroids).
    func updateCandidatePoints(_ points: [CLLocationCoordinate2D]) {
        sideInference.updateCandidates(points)
    }

    /// Process an already-accepted raw location. Returns the normalized coordinate to use for the render trail (or fallback to raw).
    func process(acceptedLocation location: CLLocation) -> CLLocationCoordinate2D {
        let raw = location.coordinate
        guard config.isProModeEnabled else {
            normalizedPoints.append(raw)
            return raw
        }
        #if DEBUG
        let corridorCount = corridorService.corridorCount
        if corridorCount == 0 {
            print("⚠️ [GPSNorm] process() called but corridors array is EMPTY — trailNormalizer has no roads. Session roads not loaded.")
        }
        #endif
        let bestProjection = corridorService.project(point: raw)
        if let projection = stabilizedProjection(for: raw, bestProjection: bestProjection) {
            #if DEBUG
            let snapCount = normalizedPoints.count + 1
            if snapCount <= 5 || snapCount % 20 == 0 {
                print("✅ [GPSNorm] SNAPPED (point \(snapCount)) lateral=\(String(format: "%.1f", abs(projection.lateralOffsetMeters)))m corridor=\(projection.corridorId ?? "?")")
            }
            #endif
            let didSwitchCorridor = lastCorridorId != nil && lastCorridorId != projection.corridorId
            if didSwitchCorridor {
                normalizedSegmentBreaks.insert(normalizedPoints.count)
                progressConstraint.reset()
                sideInference.reset()
                pointsSinceCorridorSwitch = 0
            }
            lastCorridorId = projection.corridorId
            pointsSinceCorridorSwitch += 1
            consecutiveProjectionCount += 1
            let confidence = projectionConfidence(
                lateralOffsetMeters: projection.lateralOffsetMeters,
                sameCorridorContinuity: !didSwitchCorridor,
                noRecentFallback: true,
                switchStability: pointsSinceCorridorSwitch >= 3
            )
            let side = sideInference.inferSide(
                segmentFrom: projection.segmentFrom,
                segmentTo: projection.segmentTo,
                projectedPoint: projection.projectedPoint,
                userPoint: raw,
                corridorId: projection.corridorId
            )
            let sideStrong = abs(projection.lateralOffsetMeters) > 8 && side != .unknown
            lastCorridorContext = CorridorContext(
                corridorId: projection.corridorId,
                progressMeters: projection.progressMeters,
                lateralOffsetMeters: projection.lateralOffsetMeters,
                projectionConfidence: confidence,
                isFallback: false,
                sideOfStreet: side,
                sideConfidenceUnusuallyStrong: sideStrong,
                segmentFrom: projection.segmentFrom,
                segmentTo: projection.segmentTo
            )
            guard progressConstraint.accept(projectedProgressMeters: projection.progressMeters) else {
                normalizedPoints.append(normalizedPoints.last ?? raw)
                return normalizedPoints.last ?? raw
            }
            if let corridorId = projection.corridorId {
                traversedCorridorSamples.append(
                    TraversedCorridorSample(
                        corridorId: corridorId,
                        progressMeters: projection.progressMeters
                    )
                )
            }
            // Display path: centerline only. No side-of-street offset for live drawing.
            let centerline = projection.projectedPoint
            recordAcceptedRaw(raw)
            if let smoothed = smoother.add(centerline) {
                normalizedPoints.append(smoothed)
                return smoothed
            } else {
                normalizedPoints.append(centerline)
                return centerline
            }
        }
        consecutiveProjectionCount = 0
        lastCorridorContext = CorridorContext(
            corridorId: lastCorridorId,
            progressMeters: 0,
            lateralOffsetMeters: 0,
            projectionConfidence: .none,
            isFallback: true,
            sideOfStreet: nil,
            sideConfidenceUnusuallyStrong: false,
            segmentFrom: nil,
            segmentTo: nil
        )
        #if DEBUG
        let nearestMeters = corridorService.nearestCorridorDistanceMeters(to: raw)
        let total = normalizedPoints.count + 1
        if total <= 5 || total % 20 == 0 {
            print("⚠️ [GPSNorm] FALLBACK raw GPS (point \(total)) — nearest corridor: \(String(format: "%.1f", nearestMeters))m, maxLateral: \(config.maxLateralDeviation)m, corridors: \(corridorService.corridorCount)")
        }
        #endif
        if traversedCorridorSamples.last != nil {
            traversedCorridorSamples.append(nil)
        }
        let fallback: CLLocationCoordinate2D
        if let last = normalizedPoints.last {
            let nearestMeters = corridorService.nearestCorridorDistanceMeters(to: raw)
            if nearestMeters.isFinite && nearestMeters <= config.maxProjectionGapBeforeRawFallbackMeters {
                // Keep the trail visually stable through short projection dropouts.
                fallback = last
            } else {
                fallback = raw
            }
        } else {
            fallback = raw
        }
        if let smoothed = smoother.add(fallback) {
            normalizedPoints.append(smoothed)
            recordAcceptedRaw(raw)
            return smoothed
        }
        normalizedPoints.append(fallback)
        recordAcceptedRaw(raw)
        return fallback
    }

    private func recordAcceptedRaw(_ coord: CLLocationCoordinate2D) {
        lastAcceptedRawCoords.append(coord)
        if lastAcceptedRawCoords.count > maxAcceptedRawCoords {
            lastAcceptedRawCoords.removeFirst()
        }
    }

    var normalizedPathCoordinates: [CLLocationCoordinate2D] {
        normalizedPoints
    }

    func normalizedPathSegments() -> [[CLLocationCoordinate2D]] {
        guard !normalizedPoints.isEmpty else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        for (i, coord) in normalizedPoints.enumerated() {
            if normalizedSegmentBreaks.contains(i) && !current.isEmpty {
                segments.append(current)
                current = []
            }
            current.append(coord)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    /// Post-session: simplify normalized trail with Douglas-Peucker (single polyline for storage); do not modify raw.
    func finalizeNormalizedTrail() -> [CLLocationCoordinate2D] {
        guard normalizedPoints.count > 2 else { return normalizedPoints }
        return GeospatialUtilities.douglasPeucker(normalizedPoints, toleranceMeters: config.simplificationToleranceMeters)
    }

    func traversedCorridorSegments() -> [[CLLocationCoordinate2D]] {
        guard !traversedCorridorSamples.isEmpty else { return [] }

        var segments: [[CLLocationCoordinate2D]] = []
        var previousSample: TraversedCorridorSample?
        var currentCorridorId: String?

        for sample in traversedCorridorSamples {
            guard let sample else {
                previousSample = nil
                currentCorridorId = nil
                continue
            }
            defer { previousSample = sample }

            guard let previousSample,
                  previousSample.corridorId == sample.corridorId,
                  abs(sample.progressMeters - previousSample.progressMeters) >= 0.5,
                  let corridor = corridorService.corridor(withId: sample.corridorId) else {
                continue
            }

            let slice = corridor.slice(
                fromProgressMeters: previousSample.progressMeters,
                toProgressMeters: sample.progressMeters
            )
            guard slice.count >= 2 else { continue }

            if currentCorridorId == sample.corridorId,
               !segments.isEmpty,
               let lastPoint = segments[segments.count - 1].last,
               let firstPoint = slice.first,
               GeospatialUtilities.distanceMeters(lastPoint, firstPoint) < 0.5 {
                segments[segments.count - 1].append(contentsOf: slice.dropFirst())
            } else {
                segments.append(slice)
            }
            currentCorridorId = sample.corridorId
        }

        return segments
    }

    func reset() {
        normalizedPoints.removeAll()
        normalizedSegmentBreaks.removeAll()
        traversedCorridorSamples.removeAll()
        lastCorridorId = nil
        pendingCorridorId = nil
        pendingCorridorHits = 0
        pendingCandidateProgressStart = nil
        lastAcceptedRawCoords.removeAll()
        consecutiveProjectionCount = 0
        pointsSinceCorridorSwitch = 0
        lastCorridorContext = nil
        progressConstraint.reset()
        sideInference.reset()
        smoother.reset()
    }

    /// Deterministic confidence from explicit ingredients (no opaque float).
    private func projectionConfidence(
        lateralOffsetMeters: Double,
        sameCorridorContinuity: Bool,
        noRecentFallback: Bool,
        switchStability: Bool
    ) -> ProjectionConfidence {
        let absLateral = abs(lateralOffsetMeters)
        let lateralBucket: Bool // good = close to centerline
        if absLateral <= 5 { lateralBucket = true }
        else if absLateral <= 12 { lateralBucket = false }
        else { return .low }
        if lateralBucket && sameCorridorContinuity && noRecentFallback && switchStability { return .high }
        if lateralBucket || (sameCorridorContinuity && noRecentFallback) { return .medium }
        return .low
    }

    private func stabilizedProjection(
        for raw: CLLocationCoordinate2D,
        bestProjection: CorridorProjection?
    ) -> CorridorProjection? {
        guard let bestProjection else { return nil }
        let currentCorridorId = lastCorridorId
        let currentProjection = currentCorridorId.flatMap { corridorService.project(point: raw, onCorridorId: $0) }

        // Same corridor as current: accept best (no switch).
        if bestProjection.corridorId == currentCorridorId {
            pendingCorridorId = nil
            pendingCorridorHits = 0
            pendingCandidateProgressStart = nil
            return bestProjection
        }

        // No current corridor: accept best.
        guard let curId = currentCorridorId, let currentProj = currentProjection else {
            pendingCorridorId = nil
            pendingCorridorHits = 0
            pendingCandidateProgressStart = nil
            return bestProjection
        }

        // Candidate is different corridor — apply hard gates and score-based switch.
        let movementHeading = recentMovementHeadingDegrees()
        if let reject = hardGateCandidateSwitch(
            candidate: bestProjection,
            current: currentProj,
            currentCorridorId: curId,
            movementHeadingDegrees: movementHeading
        ) {
            if reject {
                pendingCorridorId = nil
                pendingCorridorHits = 0
                pendingCandidateProgressStart = nil
                return currentProj
            }
        }

        let currentScore = scoreProjection(
            currentProj,
            isCurrentCorridor: true,
            movementHeadingDegrees: movementHeading
        )
        let candidateScore = scoreProjection(
            bestProjection,
            isCurrentCorridor: false,
            movementHeadingDegrees: movementHeading
        )
        let advantage = currentScore - candidateScore
        if advantage < config.switchAdvantageThreshold {
            pendingCorridorId = nil
            pendingCorridorHits = 0
            pendingCandidateProgressStart = nil
            return currentProj
        }

        if pendingCorridorId == bestProjection.corridorId {
            pendingCorridorHits += 1
            let progressOnCandidate = bestProjection.progressMeters - (pendingCandidateProgressStart ?? bestProjection.progressMeters)
            if progressOnCandidate < config.minNewCorridorProgressMeters {
                if pendingCorridorHits >= config.corridorSwitchConfirmationPoints {
                    pendingCorridorId = nil
                    pendingCorridorHits = 0
                    pendingCandidateProgressStart = nil
                    return currentProj
                }
            }
        } else {
            pendingCorridorId = bestProjection.corridorId
            pendingCorridorHits = 1
            pendingCandidateProgressStart = bestProjection.progressMeters
        }

        if pendingCorridorHits < config.corridorSwitchConfirmationPoints {
            return currentProj
        }
        let progressOnCandidate = bestProjection.progressMeters - (pendingCandidateProgressStart ?? bestProjection.progressMeters)
        if progressOnCandidate < config.minNewCorridorProgressMeters {
            pendingCorridorId = nil
            pendingCorridorHits = 0
            pendingCandidateProgressStart = nil
            return currentProj
        }
        pendingCorridorId = nil
        pendingCorridorHits = 0
        pendingCandidateProgressStart = nil
        return bestProjection
    }

    /// Returns nil if no gate applied, true if candidate should be rejected (stay on current).
    private func hardGateCandidateSwitch(
        candidate: CorridorProjection,
        current: CorridorProjection,
        currentCorridorId: String,
        movementHeadingDegrees: Double?
    ) -> Bool? {
        if abs(candidate.lateralOffsetMeters) > config.maxLateralDeviation {
            return true
        }
        if config.headingPenaltyEnabled, let heading = movementHeadingDegrees {
            let corridorDeg = GeospatialUtilities.segmentHeadingDegrees(from: candidate.segmentFrom, to: candidate.segmentTo)
            let diff = GeospatialUtilities.angularDifferenceDegrees(heading, corridorDeg)
            if diff > config.maxHeadingMismatchDegrees {
                return true
            }
        }
        return nil
    }

    private func scoreProjection(
        _ p: CorridorProjection,
        isCurrentCorridor: Bool,
        movementHeadingDegrees: Double?
    ) -> Double {
        let lateral = min(abs(p.lateralOffsetMeters), 30.0)
        var headingPenalty: Double = 0
        if config.headingPenaltyEnabled, let heading = movementHeadingDegrees {
            let corridorDeg = GeospatialUtilities.segmentHeadingDegrees(from: p.segmentFrom, to: p.segmentTo)
            let diff = GeospatialUtilities.angularDifferenceDegrees(heading, corridorDeg)
            switch diff {
            case 0..<20: headingPenalty = 0
            case 20..<45: headingPenalty = 2
            case 45..<75: headingPenalty = 6
            default: headingPenalty = 12
            }
        }
        let switchPenalty: Double = isCurrentCorridor ? 0 : config.switchBasePenalty
        var progressPenalty: Double = 0
        if isCurrentCorridor, let lastProgress = progressConstraint.lastAcceptedProgress {
            let delta = p.progressMeters - lastProgress
            if delta < -6 {
                progressPenalty = 8
            }
        }
        return lateral + headingPenalty + switchPenalty + progressPenalty
    }

    private func recentMovementHeadingDegrees() -> Double? {
        guard lastAcceptedRawCoords.count >= 2 else { return nil }
        let from = lastAcceptedRawCoords[lastAcceptedRawCoords.count - 2]
        let to = lastAcceptedRawCoords[lastAcceptedRawCoords.count - 1]
        return GeospatialUtilities.segmentHeadingDegrees(from: from, to: to)
    }
}
