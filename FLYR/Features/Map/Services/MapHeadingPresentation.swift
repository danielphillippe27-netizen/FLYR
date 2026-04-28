import CoreLocation
import Foundation

struct MapHeadingPresentationState: Equatable {
    enum Mode: String, Equatable {
        case unavailable
        case frozen
        case heading
        case blended
        case course
    }

    static let unavailable = MapHeadingPresentationState(
        heading: nil,
        confidence: 0,
        spreadDegrees: 0,
        opacity: 0,
        mode: .unavailable
    )

    let heading: CLLocationDirection?
    let confidence: Double
    let spreadDegrees: CLLocationDirection
    let opacity: Double
    let mode: Mode

    var isRenderable: Bool {
        guard let heading else { return false }
        return heading.isFinite && opacity > 0.01
    }
}

@MainActor
final class MapHeadingPresentationEngine {
    private enum Threshold {
        static let blendStartSpeedMPS = 1.1
        static let coursePreferredSpeedMPS = 1.8
        static let minimumCourseSpeedMPS = 0.9
        static let maximumCourseAccuracyMeters = 35.0
        static let freezeWindowSeconds: TimeInterval = 2.25
    }

    private struct Candidate {
        let heading: CLLocationDirection
        let confidence: Double
        let mode: MapHeadingPresentationState.Mode
    }

    private var displayedHeading: CLLocationDirection?
    private var lastDisplayUpdateAt: Date?
    private var lastCompassHeading: CLLocationDirection?
    private var stableCompassSampleCount = 0
    private var lastReliableHeading: CLLocationDirection?
    private var lastReliableHeadingAt: Date?

    func reset() {
        displayedHeading = nil
        lastDisplayUpdateAt = nil
        lastCompassHeading = nil
        stableCompassSampleCount = 0
        lastReliableHeading = nil
        lastReliableHeadingAt = nil
    }

    func nextState(
        location: CLLocation?,
        headingState: MapHeadingState,
        now: Date = Date()
    ) -> MapHeadingPresentationState {
        let speed = Self.validSpeed(from: location)
        let compassCandidate = compassCandidate(from: headingState)
        let courseCandidate = courseCandidate(from: location)

        if let candidate = selectedCandidate(
            speed: speed,
            compassCandidate: compassCandidate,
            courseCandidate: courseCandidate
        ) {
            let smoothedHeading = smoothHeading(
                toward: candidate.heading,
                mode: candidate.mode,
                confidence: candidate.confidence,
                now: now
            )

            let state = MapHeadingPresentationState(
                heading: smoothedHeading,
                confidence: candidate.confidence,
                spreadDegrees: spreadDegrees(for: candidate.mode, confidence: candidate.confidence),
                opacity: opacity(for: candidate.mode, confidence: candidate.confidence),
                mode: candidate.mode
            )

            if candidate.mode != .frozen {
                lastReliableHeading = smoothedHeading
                lastReliableHeadingAt = now
            }

            return state
        }

        if let frozenHeading = frozenHeading(now: now) {
            let smoothedHeading = smoothHeading(
                toward: frozenHeading,
                mode: .frozen,
                confidence: 0.18,
                now: now
            )

            return MapHeadingPresentationState(
                heading: smoothedHeading,
                confidence: 0.18,
                spreadDegrees: 110,
                opacity: 0.06,
                mode: .frozen
            )
        }

        displayedHeading = nil
        lastDisplayUpdateAt = now
        return .unavailable
    }

    private func compassCandidate(from headingState: MapHeadingState) -> Candidate? {
        guard headingState.isRenderable,
              let heading = headingState.heading,
              let accuracy = headingState.accuracy else {
            stableCompassSampleCount = max(0, stableCompassSampleCount - 1)
            return nil
        }

        let normalizedHeading = CLLocationDirection.normalizedCompassAngle(heading)
        if let lastCompassHeading {
            let delta = abs(CLLocationDirection.shortestCompassDelta(from: lastCompassHeading, to: normalizedHeading))
            switch delta {
            case ..<6:
                stableCompassSampleCount = min(stableCompassSampleCount + 2, 6)
            case ..<12:
                stableCompassSampleCount = min(stableCompassSampleCount + 1, 6)
            case ..<24:
                stableCompassSampleCount = max(stableCompassSampleCount - 1, 0)
            default:
                stableCompassSampleCount = 0
            }
        } else {
            stableCompassSampleCount = 1
        }
        lastCompassHeading = normalizedHeading

        let accuracyScore = ((MapHeadingState.maximumRenderableAccuracy - accuracy) / MapHeadingState.maximumRenderableAccuracy).clamped01
        let stabilityScore = (Double(stableCompassSampleCount) / 4.0).clamped01
        let confidence = ((accuracyScore * 0.6) + (stabilityScore * 0.4)).clamped01
        guard confidence >= 0.2 else { return nil }

        return Candidate(heading: normalizedHeading, confidence: confidence, mode: .heading)
    }

    private func courseCandidate(from location: CLLocation?) -> Candidate? {
        guard let location,
              location.course >= 0,
              location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= Threshold.maximumCourseAccuracyMeters else {
            return nil
        }

        let speed = Self.validSpeed(from: location)
        guard speed >= Threshold.minimumCourseSpeedMPS else { return nil }

        let speedScore = (
            (speed - Threshold.minimumCourseSpeedMPS) /
            (Threshold.coursePreferredSpeedMPS - Threshold.minimumCourseSpeedMPS)
        ).clamped01
        let accuracyScore = (
            (Threshold.maximumCourseAccuracyMeters - location.horizontalAccuracy) /
            (Threshold.maximumCourseAccuracyMeters - 8)
        ).clamped01
        let confidence = (0.35 + (speedScore * 0.45) + (accuracyScore * 0.20)).clamped01

        return Candidate(
            heading: CLLocationDirection.normalizedCompassAngle(location.course),
            confidence: confidence,
            mode: .course
        )
    }

    private func selectedCandidate(
        speed: CLLocationSpeed,
        compassCandidate: Candidate?,
        courseCandidate: Candidate?
    ) -> Candidate? {
        if let courseCandidate, speed >= Threshold.coursePreferredSpeedMPS {
            return Candidate(
                heading: courseCandidate.heading,
                confidence: max(courseCandidate.confidence, 0.72),
                mode: .course
            )
        }

        if let compassCandidate,
           let courseCandidate,
           speed >= Threshold.blendStartSpeedMPS {
            let courseWeight = (
                0.25 +
                (0.55 * (
                    (speed - Threshold.blendStartSpeedMPS) /
                    (Threshold.coursePreferredSpeedMPS - Threshold.blendStartSpeedMPS)
                ).clamped01)
            ).clamped01
            let blendedHeading = Self.interpolateAngle(
                from: compassCandidate.heading,
                to: courseCandidate.heading,
                factor: courseWeight
            )
            let mode: MapHeadingPresentationState.Mode = courseWeight > 0.72 ? .course : .blended
            let confidence = ((courseCandidate.confidence * 0.65) + (compassCandidate.confidence * 0.35)).clamped01

            return Candidate(
                heading: blendedHeading,
                confidence: confidence,
                mode: mode
            )
        }

        if let compassCandidate, compassCandidate.confidence >= 0.35 {
            return compassCandidate
        }

        if let courseCandidate, speed >= Threshold.blendStartSpeedMPS {
            return Candidate(
                heading: courseCandidate.heading,
                confidence: max(0.35, courseCandidate.confidence * 0.75),
                mode: .course
            )
        }

        return nil
    }

    private func frozenHeading(now: Date) -> CLLocationDirection? {
        guard let lastReliableHeading,
              let lastReliableHeadingAt,
              now.timeIntervalSince(lastReliableHeadingAt) <= Threshold.freezeWindowSeconds else {
            return nil
        }

        return lastReliableHeading
    }

    private func smoothHeading(
        toward target: CLLocationDirection,
        mode: MapHeadingPresentationState.Mode,
        confidence: Double,
        now: Date
    ) -> CLLocationDirection {
        let normalizedTarget = CLLocationDirection.normalizedCompassAngle(target)
        guard let displayedHeading else {
            displayedHeading = normalizedTarget
            lastDisplayUpdateAt = now
            return normalizedTarget
        }

        let elapsed = max(1.0 / 15.0, min(1.0, now.timeIntervalSince(lastDisplayUpdateAt ?? now)))
        lastDisplayUpdateAt = now

        let delta = CLLocationDirection.shortestCompassDelta(from: displayedHeading, to: normalizedTarget)
        let distance = abs(delta)
        let deadband: CLLocationDirection
        let responsiveness: Double
        let maximumRateDegreesPerSecond: CLLocationDirection

        switch mode {
        case .course:
            deadband = 4
            responsiveness = 0.42
            maximumRateDegreesPerSecond = 160
        case .blended:
            deadband = 6
            responsiveness = 0.32
            maximumRateDegreesPerSecond = 120
        case .heading:
            deadband = 9
            responsiveness = 0.24
            maximumRateDegreesPerSecond = 90
        case .frozen:
            deadband = 14
            responsiveness = 0.16
            maximumRateDegreesPerSecond = 45
        case .unavailable:
            return displayedHeading
        }

        guard distance >= deadband else { return displayedHeading }

        let weightedResponsiveness = responsiveness * (0.6 + (confidence.clamped01 * 0.5))
        let desiredStep = delta * weightedResponsiveness
        let maximumStep = maximumRateDegreesPerSecond * elapsed
        let clampedStep = desiredStep.clamped(to: -maximumStep...maximumStep)
        let nextHeading = CLLocationDirection.normalizedCompassAngle(displayedHeading + clampedStep)

        self.displayedHeading = nextHeading
        return nextHeading
    }

    private func spreadDegrees(
        for mode: MapHeadingPresentationState.Mode,
        confidence: Double
    ) -> CLLocationDirection {
        let inverseConfidence = 1 - confidence.clamped01

        switch mode {
        case .course:
            return 44 + (inverseConfidence * 12)
        case .blended:
            return 58 + (inverseConfidence * 20)
        case .heading:
            return 74 + (inverseConfidence * 28)
        case .frozen:
            return 110
        case .unavailable:
            return 0
        }
    }

    private func opacity(
        for mode: MapHeadingPresentationState.Mode,
        confidence: Double
    ) -> Double {
        switch mode {
        case .course:
            return 0.12 + (confidence.clamped01 * 0.10)
        case .blended:
            return 0.10 + (confidence.clamped01 * 0.08)
        case .heading:
            return 0.08 + (confidence.clamped01 * 0.07)
        case .frozen:
            return 0.06
        case .unavailable:
            return 0
        }
    }

    private static func validSpeed(from location: CLLocation?) -> CLLocationSpeed {
        guard let location, location.speed >= 0 else { return 0 }
        return location.speed
    }

    private static func interpolateAngle(
        from start: CLLocationDirection,
        to end: CLLocationDirection,
        factor: Double
    ) -> CLLocationDirection {
        let delta = CLLocationDirection.shortestCompassDelta(from: start, to: end)
        return CLLocationDirection.normalizedCompassAngle(start + (delta * factor.clamped01))
    }
}

private extension Double {
    var clamped01: Double {
        clamped(to: 0...1)
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
