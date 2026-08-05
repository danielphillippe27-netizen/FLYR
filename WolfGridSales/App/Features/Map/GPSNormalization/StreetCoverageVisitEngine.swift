import Foundation
import CoreLocation

struct StreetCoverageVisitCandidate: Sendable {
    let targetId: String
    let score: Double
    let matchedDistanceMeters: Double
    let pathSpanMeters: Double
    let sameSide: Bool?
    let supportingPointCount: Int
    let corridorId: String
}

private struct StreetCoverageAcceptedSample: Sendable {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let progressMeters: Double
    let lateralOffsetMeters: Double
    let segmentFrom: CLLocationCoordinate2D?
    let segmentTo: CLLocationCoordinate2D?
    let sideConfidenceStrong: Bool
}

final class StreetCoverageVisitEngine {
    private let config: StreetCoverageVisitConfig
    private var corridorsById: [String: StreetCorridor] = [:]
    private var samplesByCorridorId: [String: [StreetCoverageAcceptedSample]] = [:]
    private var lastEmissionAtByTargetId: [String: Date] = [:]

    init(config: StreetCoverageVisitConfig = .default, corridors: [StreetCorridor]) {
        self.config = config
        updateCorridors(corridors)
    }

    func updateCorridors(_ corridors: [StreetCorridor]) {
        corridorsById = Dictionary(uniqueKeysWithValues: corridors.compactMap { corridor in
            guard let id = corridor.id else { return nil }
            return (id, corridor)
        })
        samplesByCorridorId = samplesByCorridorId.filter { corridorsById[$0.key] != nil }
    }

    func reset() {
        samplesByCorridorId.removeAll()
        lastEmissionAtByTargetId.removeAll()
    }

    func process(
        acceptedLocation location: CLLocation,
        corridorContext: CorridorContext?,
        buildingCentroids: [String: CLLocation],
        targetBuildingIds: [String],
        alreadyVisited: Set<String>
    ) -> [StreetCoverageVisitCandidate] {
        guard let context = corridorContext,
              !context.isFallback,
              let corridorId = context.corridorId,
              let corridor = corridorsById[corridorId] else {
            return []
        }

        let sample = StreetCoverageAcceptedSample(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            progressMeters: context.progressMeters,
            lateralOffsetMeters: context.lateralOffsetMeters,
            segmentFrom: context.segmentFrom,
            segmentTo: context.segmentTo,
            sideConfidenceStrong: context.sideConfidenceUnusuallyStrong
        )
        append(sample, toCorridorId: corridorId, now: location.timestamp)

        guard let samples = samplesByCorridorId[corridorId], samples.count >= config.minimumAcceptedPointCount else {
            return []
        }

        let progressValues = samples.map(\.progressMeters)
        guard let minimumProgress = progressValues.min(),
              let maximumProgress = progressValues.max() else {
            return []
        }
        let progressSpan = maximumProgress - minimumProgress
        guard progressSpan >= config.minimumProgressSpanMeters else { return [] }

        let traveledDistance = totalDistance(samples.map(\.coordinate))
        guard traveledDistance >= config.minimumTraveledDistanceMeters else { return [] }

        var candidates: [StreetCoverageVisitCandidate] = []
        for targetId in targetBuildingIds where !alreadyVisited.contains(targetId.lowercased()) {
            guard let centroid = buildingCentroids[targetId] else { continue }
            let normalizedTargetId = targetId.lowercased()
            if let lastEmissionAt = lastEmissionAtByTargetId[normalizedTargetId],
               location.timestamp.timeIntervalSince(lastEmissionAt) < config.reemitCooldownSeconds {
                continue
            }

            guard let targetProjection = GeospatialUtilities.nearestPointOnPolyline(
                point: centroid.coordinate,
                polyline: corridor.polyline
            ) else {
                continue
            }

            let targetProgress = targetProjection.progressAlongLineMeters
            guard targetProgress >= minimumProgress - config.progressMarginMeters,
                  targetProgress <= maximumProgress + config.progressMarginMeters else {
                continue
            }

            let frontagePoint = corridor.coordinate(atProgressMeters: targetProgress)
            let centroidDistance = nearestDistanceMeters(from: centroid.coordinate, toPath: samples.map(\.coordinate))
            let frontageDistance = nearestDistanceMeters(from: frontagePoint, toPath: samples.map(\.coordinate))
            let matchedDistance = min(centroidDistance, frontageDistance)
            guard matchedDistance <= config.corridorBufferMeters else { continue }

            let supportingPointCount = supportingSampleCount(
                samples: samples,
                targetProgressMeters: targetProgress,
                targetCoordinate: centroid.coordinate,
                frontageCoordinate: frontagePoint
            )
            guard supportingPointCount >= config.minimumSupportingSamplesAtTarget else { continue }

            let sideEvaluation = evaluateSide(samples: samples, targetCoordinate: centroid.coordinate)
            var score = 0.0
            score += matchedDistance <= config.closeMatchDistanceMeters ? 2 : 1
            if supportingPointCount >= config.minimumRepeatedNearbyPoints {
                score += 1
            }
            if progressSpan >= config.strongCoverageBonusProgressMeters {
                score += 1
            }
            if sideEvaluation.sameSide == true {
                score += 1
            } else if sideEvaluation.oppositeStrong {
                score -= 2
            }

            guard score >= config.visitScoreThreshold else { continue }

            lastEmissionAtByTargetId[normalizedTargetId] = location.timestamp
            candidates.append(
                StreetCoverageVisitCandidate(
                    targetId: targetId,
                    score: score,
                    matchedDistanceMeters: matchedDistance,
                    pathSpanMeters: progressSpan,
                    sameSide: sideEvaluation.sameSide,
                    supportingPointCount: supportingPointCount,
                    corridorId: corridorId
                )
            )
        }

        return candidates
    }

    private func append(_ sample: StreetCoverageAcceptedSample, toCorridorId corridorId: String, now: Date) {
        var samples = samplesByCorridorId[corridorId] ?? []
        samples.append(sample)
        let cutoff = now.addingTimeInterval(-config.rollingWindowSeconds)
        samples = samples.filter { $0.timestamp >= cutoff }
        if samples.count > config.rollingWindowPointLimit {
            samples.removeFirst(samples.count - config.rollingWindowPointLimit)
        }
        samplesByCorridorId[corridorId] = samples
    }

    private func supportingSampleCount(
        samples: [StreetCoverageAcceptedSample],
        targetProgressMeters: Double,
        targetCoordinate: CLLocationCoordinate2D,
        frontageCoordinate: CLLocationCoordinate2D
    ) -> Int {
        samples.reduce(into: 0) { count, sample in
            let progressDelta = abs(sample.progressMeters - targetProgressMeters)
            guard progressDelta <= config.frontageProgressWindowMeters else { return }

            let centroidDistance = GeospatialUtilities.distanceMeters(sample.coordinate, targetCoordinate)
            let frontageDistance = GeospatialUtilities.distanceMeters(sample.coordinate, frontageCoordinate)
            if min(centroidDistance, frontageDistance) <= config.repeatedNearbyRadiusMeters {
                count += 1
            }
        }
    }

    private func evaluateSide(
        samples: [StreetCoverageAcceptedSample],
        targetCoordinate: CLLocationCoordinate2D
    ) -> (sameSide: Bool?, oppositeStrong: Bool) {
        var sameSideCount = 0
        var oppositeSideCount = 0

        for sample in samples where sample.sideConfidenceStrong {
            guard abs(sample.lateralOffsetMeters) >= config.sideConfidenceMinimumLateralMeters,
                  let segmentFrom = sample.segmentFrom,
                  let segmentTo = sample.segmentTo else {
                continue
            }

            let targetOffset = GeospatialUtilities.signedLateralOffsetMeters(
                point: targetCoordinate,
                segmentFrom: segmentFrom,
                to: segmentTo,
                origin: sample.coordinate
            )
            guard abs(targetOffset) >= config.crossStreetNeutralBandMeters else { continue }

            let sameSide = (sample.lateralOffsetMeters >= 0 && targetOffset >= 0)
                || (sample.lateralOffsetMeters < 0 && targetOffset < 0)
            if sameSide {
                sameSideCount += 1
            } else {
                oppositeSideCount += 1
            }
        }

        if sameSideCount >= config.sideConfidenceMinimumSamples && oppositeSideCount == 0 {
            return (true, false)
        }
        if oppositeSideCount >= config.sideConfidenceMinimumSamples && sameSideCount == 0 {
            return (false, true)
        }
        return (nil, false)
    }

    private func totalDistance(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        return zip(coordinates, coordinates.dropFirst()).reduce(0) { partial, pair in
            partial + GeospatialUtilities.distanceMeters(pair.0, pair.1)
        }
    }

    private func nearestDistanceMeters(
        from point: CLLocationCoordinate2D,
        toPath path: [CLLocationCoordinate2D]
    ) -> Double {
        guard path.count >= 2 else {
            guard let only = path.first else { return .infinity }
            return GeospatialUtilities.distanceMeters(point, only)
        }

        var best = Double.infinity
        for (from, to) in zip(path, path.dropFirst()) {
            guard let projected = GeospatialUtilities.project(point: point, ontoSegmentFrom: from, to: to) else {
                continue
            }
            best = min(best, GeospatialUtilities.distanceMeters(point, projected.point))
        }
        return best
    }
}
