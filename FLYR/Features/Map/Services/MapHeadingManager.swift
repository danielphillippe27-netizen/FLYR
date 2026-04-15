import Combine
import CoreLocation
import Foundation
import UIKit

struct MapHeadingState: Equatable {
    enum Source: String, Equatable {
        case trueNorth
        case magneticNorth
    }

    static let maximumRenderableAccuracy: CLLocationDirection = 25
    static let unavailable = MapHeadingState(heading: nil, accuracy: nil, source: nil)

    let heading: CLLocationDirection?
    let accuracy: CLLocationDirection?
    let source: Source?

    var isRenderable: Bool {
        guard let heading, let accuracy else { return false }
        return heading.isFinite && accuracy >= 0 && accuracy <= Self.maximumRenderableAccuracy
    }
}

extension CLLocationDirection {
    static func normalizedCompassAngle(_ angle: CLLocationDirection) -> CLLocationDirection {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    static func shortestCompassDelta(from current: CLLocationDirection, to target: CLLocationDirection) -> CLLocationDirection {
        let normalizedCurrent = normalizedCompassAngle(current)
        let normalizedTarget = normalizedCompassAngle(target)
        let delta = normalizedTarget - normalizedCurrent

        if delta > 180 {
            return delta - 360
        }
        if delta < -180 {
            return delta + 360
        }
        return delta
    }
}

@MainActor
final class MapHeadingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MapHeadingManager()

    @Published private(set) var state: MapHeadingState = .unavailable

    private let locationManager = CLLocationManager()
    private let smoother = CircularHeadingSmoother()
    private var isUpdating = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = 1
        updateHeadingOrientation()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    func start() {
        guard CLLocationManager.headingAvailable() else {
            stop(reset: true)
            return
        }

        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            stop(reset: true)
            return
        }

        updateHeadingOrientation()
        guard !isUpdating else { return }
        isUpdating = true
        locationManager.startUpdatingHeading()
    }

    func stop(reset: Bool) {
        if isUpdating {
            locationManager.stopUpdatingHeading()
            isUpdating = false
        }

        guard reset else { return }
        smoother.reset()
        state = .unavailable
    }

    @objc
    private func handleDeviceOrientationDidChange() {
        updateHeadingOrientation()
    }

    private func updateHeadingOrientation() {
        locationManager.headingOrientation = Self.headingOrientation(for: UIDevice.current.orientation)
    }

    private static func headingOrientation(for orientation: UIDeviceOrientation) -> CLDeviceOrientation {
        switch orientation {
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }

    private static func resolvedHeading(from heading: CLHeading) -> (value: CLLocationDirection, source: MapHeadingState.Source)? {
        if heading.trueHeading >= 0 {
            return (CLLocationDirection.normalizedCompassAngle(heading.trueHeading), .trueNorth)
        }
        if heading.magneticHeading >= 0 {
            return (CLLocationDirection.normalizedCompassAngle(heading.magneticHeading), .magneticNorth)
        }
        return nil
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard let resolved = Self.resolvedHeading(from: newHeading) else {
            smoother.reset()
            state = .unavailable
            return
        }

        let accuracy = newHeading.headingAccuracy
        guard accuracy >= 0, accuracy <= MapHeadingState.maximumRenderableAccuracy else {
            smoother.reset()
            state = MapHeadingState(heading: nil, accuracy: accuracy, source: resolved.source)
            return
        }

        let smoothedHeading = smoother.nextHeading(toward: resolved.value, accuracy: accuracy)
        state = MapHeadingState(
            heading: smoothedHeading,
            accuracy: accuracy,
            source: resolved.source
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            start()
        } else {
            stop(reset: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ [MapHeadingManager] Heading update failed: \(error.localizedDescription)")
        stop(reset: true)
    }
}

private final class CircularHeadingSmoother {
    private var currentHeading: CLLocationDirection?

    func reset() {
        currentHeading = nil
    }

    func nextHeading(toward target: CLLocationDirection, accuracy: CLLocationDirection) -> CLLocationDirection {
        let normalizedTarget = CLLocationDirection.normalizedCompassAngle(target)
        guard let currentHeading else {
            self.currentHeading = normalizedTarget
            return normalizedTarget
        }

        let delta = CLLocationDirection.shortestCompassDelta(from: currentHeading, to: normalizedTarget)
        let distance = abs(delta)

        if distance < 0.6 {
            return currentHeading
        }

        let accuracyFactor: Double
        switch accuracy {
        case ..<8:
            accuracyFactor = 0.28
        case ..<15:
            accuracyFactor = 0.22
        default:
            accuracyFactor = 0.16
        }

        let responsiveness: Double
        switch distance {
        case ..<10:
            responsiveness = accuracyFactor * 0.7
        case ..<35:
            responsiveness = accuracyFactor
        default:
            responsiveness = min(0.42, accuracyFactor * 1.35)
        }

        let next = CLLocationDirection.normalizedCompassAngle(currentHeading + delta * responsiveness)
        self.currentHeading = next
        return next
    }
}
