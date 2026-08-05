import Foundation
import Combine
import CoreLocation
import UIKit

final class WalkModeManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isActive: Bool = false
    @Published var focusedAddressID: UUID?
    @Published var highlightedAddressID: UUID?
    @Published var lastConfidence: Double = 0

    var statusProvider: ((UUID) -> AddressStatus?)?

    private var route: [CampaignAddress] = []
    private var locationManager: CLLocationManager?
    private var currentHeading: CLHeading?
    private var lastTriggeredAt: Date?
    private var lastMovementLocation: CLLocation?
    private var lastMovementAt: Date?
    private var isSteppedDownForStandstill = false
    private var statuses: [UUID: AddressStatus] = [:]

    func activate(route: [CampaignAddress], startingAt: UUID?) {
        locationManager?.stopUpdatingLocation()
        locationManager?.stopUpdatingHeading()
        locationManager?.delegate = nil
        self.route = route.filter { $0.coordinate != nil }
        if let startingAt {
            focusedAddressID = startingAt
            highlightedAddressID = startingAt
        } else if focusedAddressID == nil {
            focusedAddressID = highlightedAddressID
        }

        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 3.0
        manager.headingFilter = 5.0
        locationManager = manager
        isSteppedDownForStandstill = false
        lastMovementLocation = nil
        lastMovementAt = Date()

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates(manager)
        case .denied, .restricted:
            break
        @unknown default:
            break
        }

        isActive = true
    }

    func deactivate() {
        locationManager?.stopUpdatingLocation()
        locationManager?.stopUpdatingHeading()
        locationManager?.delegate = nil
        locationManager = nil
        isActive = false
        lastConfidence = 0
        currentHeading = nil
        lastMovementLocation = nil
        lastMovementAt = nil
        isSteppedDownForStandstill = false
    }

    func manualOverride(addressID: UUID) {
        focusedAddressID = addressID
        highlightedAddressID = addressID
        lastTriggeredAt = Date()
        lastConfidence = 0
    }

    func updateStatuses(_ statuses: [UUID: AddressStatus]) {
        self.statuses = statuses
    }

    func computeConfidence(
        location: CLLocation,
        heading: CLHeading?,
        candidate: CampaignAddress,
        lastTriggeredAt: Date?,
        routeIndex: Int,
        focusedRouteIndex: Int
    ) -> Double {
        let distance = location.distance(from: candidate.clLocation)
        let distanceScore = max(0, 1.0 - (distance / 25.0))

        let speed = max(0, location.speed)
        let speedScore = exp(-pow(speed - 1.4, 2) / (2 * 0.36))

        var headingScore = 0.0
        if let heading {
            let bearing = location.bearing(to: candidate.clLocation)
            let delta = abs(bearing - heading.trueHeading).truncatingRemainder(dividingBy: 360)
            let angle = min(delta, 360 - delta)
            headingScore = max(0, cos(angle * .pi / 180))
        }

        let sequenceScore: Double = (routeIndex == focusedRouteIndex + 1) ? 0.25 : 0.0

        let cooldownScore: Double
        if let last = lastTriggeredAt, Date().timeIntervalSince(last) < 8 {
            cooldownScore = 0.0
        } else {
            cooldownScore = 0.2
        }

        return distanceScore + speedScore + headingScore + sequenceScore + cooldownScore
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isActive else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates(manager)
        case .denied, .restricted:
            deactivate()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading.trueHeading >= 0 ? newHeading : nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, let location = locations.last else { return }
        updateStandstillPowerState(location: location)
        evaluate(location: location, heading: currentHeading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastConfidence = 0
    }

    private func startLocationUpdates(_ manager: CLLocationManager) {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 3.0
        manager.headingFilter = 5.0
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    private func updateStandstillPowerState(location: CLLocation) {
        let now = Date()

        if let previous = lastMovementLocation {
            let moved = location.distance(from: previous)
            if moved > 2 {
                lastMovementLocation = location
                lastMovementAt = now
                if isSteppedDownForStandstill {
                    locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                    isSteppedDownForStandstill = false
                }
            }
        } else {
            lastMovementLocation = location
            lastMovementAt = now
        }

        if let lastMovementAt,
           now.timeIntervalSince(lastMovementAt) > 30,
           !isSteppedDownForStandstill {
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            isSteppedDownForStandstill = true
        }
    }

    private func evaluate(location: CLLocation, heading: CLHeading?) {
        guard let candidateContext = nextCandidate(from: location) else {
            lastConfidence = 0
            return
        }

        let confidence = computeConfidence(
            location: location,
            heading: heading,
            candidate: candidateContext.address,
            lastTriggeredAt: lastTriggeredAt,
            routeIndex: candidateContext.routeIndex,
            focusedRouteIndex: candidateContext.focusedRouteIndex
        )
        lastConfidence = confidence

        guard confidence >= 1.5 else { return }
        let addressID = candidateContext.address.id
        focusedAddressID = addressID
        highlightedAddressID = addressID
        lastTriggeredAt = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func nextCandidate(from location: CLLocation) -> (address: CampaignAddress, routeIndex: Int, focusedRouteIndex: Int)? {
        guard !route.isEmpty else { return nil }

        let focusedRouteIndex = focusedAddressID.flatMap { id in
            route.firstIndex(where: { $0.id == id })
        } ?? -1

        let nextIndex = route.indices.first { index in
            index > focusedRouteIndex && isNotContacted(route[index].id)
        }

        var nextCandidate: (address: CampaignAddress, routeIndex: Int)?
        if let nextIndex {
            nextCandidate = (route[nextIndex], nextIndex)
        }

        if let nextCandidate {
            let distance = location.distance(from: nextCandidate.address.clLocation)
            if distance <= 60 {
                return (nextCandidate.address, nextCandidate.routeIndex, focusedRouteIndex)
            }
        }

        let closest = route.enumerated()
            .filter { isNotContacted($0.element.id) }
            .map { item -> (address: CampaignAddress, routeIndex: Int, distance: CLLocationDistance) in
                (item.element, item.offset, location.distance(from: item.element.clLocation))
            }
            .filter { $0.distance <= 40 }
            .min { $0.distance < $1.distance }

        if let closest {
            return (closest.address, closest.routeIndex, focusedRouteIndex)
        }

        if let nextCandidate {
            return (nextCandidate.address, nextCandidate.routeIndex, focusedRouteIndex)
        }

        return nil
    }

    private func isNotContacted(_ addressID: UUID) -> Bool {
        guard let status = statuses[addressID] ?? statusProvider?(addressID) else { return true }
        return status == .none || status == .untouched
    }
}

extension CampaignAddress {
    var clLocation: CLLocation {
        guard let coordinate else {
            return CLLocation(latitude: 0, longitude: 0)
        }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension CLLocation {
    func bearing(to destination: CLLocation) -> Double {
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let lat2 = destination.coordinate.latitude * .pi / 180
        let lon2 = destination.coordinate.longitude * .pi / 180
        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }
}
