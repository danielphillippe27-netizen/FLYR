import Foundation
import CoreLocation
import Combine

/// Single address for flyer mode (proximity is per address, not per building).
struct FlyerAddress {
    let id: UUID
    let formatted: String
    let coordinate: CLLocationCoordinate2D
}

/// Manages flyer mode with direct proximity+dwell completion against address points.
@MainActor
final class FlyerModeManager: ObservableObject {
    static let proximityThresholdMeters: Double = 10.0
    static let maxProximityThresholdMeters: Double = 20.0
    static let dwellSeconds: TimeInterval = 5.0
    static let maxCompletionSpeedMPS: Double = 2.5

    @Published private(set) var currentAddress: FlyerAddress?
    @Published private(set) var addresses: [FlyerAddress] = []

    var onAddressCompleted: ((UUID, AddressStatus) -> Void)?
    var automaticStatusForAddress: ((UUID) -> AddressStatus)?

    private var locationCancellable: AnyCancellable?
    private var dwellTracker: [UUID: Date] = [:]

    func load(campaignId _: UUID, featuresService: MapFeaturesService) async {
        addresses = []
        currentAddress = nil

        let buildingFeatures = featuresService.buildings?.features ?? []
        let addressFeatures = featuresService.addresses?.features ?? []
        addresses = addressesFromFlyerTargets(
            CampaignTargetResolver.flyerTargets(buildings: buildingFeatures, addresses: addressFeatures)
        )

        currentAddress = nearestAddress(to: SessionManager.shared.currentLocation)
    }

    func load(targets: [ResolvedCampaignTarget]) {
        addresses = addressesFromFlyerTargets(targets)
        currentAddress = nearestAddress(to: SessionManager.shared.currentLocation)
    }

    func startObservingLocation() {
        locationCancellable = SessionManager.shared.$currentLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self = self, let location = location else { return }
                Task { @MainActor in
                    await self.checkProximity(location: location)
                }
            }
    }

    func stopObservingLocation() {
        locationCancellable = nil
    }

    func reset() {
        stopObservingLocation()
        addresses = []
        currentAddress = nil
        dwellTracker = [:]
    }

    private func addressesFromFlyerTargets(_ targets: [ResolvedCampaignTarget]) -> [FlyerAddress] {
        var seen = Set<UUID>()

        return targets.compactMap { target in
            let rawId = target.addressId ?? target.id
            guard let id = UUID(uuidString: rawId),
                  seen.insert(id).inserted else {
                return nil
            }

            return FlyerAddress(
                id: id,
                formatted: target.label,
                coordinate: target.coordinate
            )
        }
    }

    private func nearestAddress(to location: CLLocation?) -> FlyerAddress? {
        guard !addresses.isEmpty else { return nil }
        guard let location else { return addresses.first }
        return addresses.min(by: { lhs, rhs in
            let l = location.distance(from: CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude))
            let r = location.distance(from: CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude))
            return l < r
        })
    }

    private func checkProximity(location: CLLocation) async {
        guard !addresses.isEmpty else {
            currentAddress = nil
            dwellTracker = [:]
            return
        }

        // Drive-by guard: don't auto-complete while moving too fast.
        if location.speed >= 0, location.speed > Self.maxCompletionSpeedMPS {
            currentAddress = nearestAddress(to: location)
            return
        }

        let threshold = adaptiveThresholdMeters(for: location)
        currentAddress = nearestAddress(to: location)

        // Keep dwell state only for addresses still within proximity.
        dwellTracker = dwellTracker.filter { addressId, _ in
            guard let address = addresses.first(where: { $0.id == addressId }) else { return false }
            let addrLocation = CLLocation(latitude: address.coordinate.latitude, longitude: address.coordinate.longitude)
            return location.distance(from: addrLocation) <= threshold
        }

        guard let matchedIndex = addresses.firstIndex(where: { addr in
            let addrLocation = CLLocation(latitude: addr.coordinate.latitude, longitude: addr.coordinate.longitude)
            return location.distance(from: addrLocation) <= threshold
        }) else { return }

        let addressId = addresses[matchedIndex].id
        let now = Date()
        let enteredAt = dwellTracker[addressId] ?? now
        if dwellTracker[addressId] == nil {
            dwellTracker[addressId] = now
        }
        guard now.timeIntervalSince(enteredAt) >= Self.dwellSeconds else { return }

        guard let campaignId = SessionManager.shared.campaignId else { return }
        let sessionId = SessionManager.shared.sessionId
        let location = SessionManager.shared.currentLocation
        let completionStatus = automaticStatusForAddress?(addressId) ?? .delivered
        if completionStatus == .delivered {
            do {
                try await VisitsAPI.shared.updateStatus(
                    addressId: addressId,
                    campaignId: campaignId,
                    status: .delivered,
                    notes: nil,
                    sessionId: sessionId,
                    sessionTargetId: nil,
                    sessionEventType: .flyerLeft,
                    location: location
                )
            } catch {
                print("⚠️ [FlyerModeManager] Failed to persist flyer completion for \(addressId): \(error)")
                return
            }
        }

        onAddressCompleted?(addressId, completionStatus)

        addresses.remove(at: matchedIndex)
        dwellTracker[addressId] = nil
        currentAddress = nearestAddress(to: location)
    }

    private func adaptiveThresholdMeters(for location: CLLocation) -> Double {
        guard location.horizontalAccuracy > 0 else { return Self.proximityThresholdMeters }
        let scaled = location.horizontalAccuracy * 1.2
        return min(Self.maxProximityThresholdMeters, max(Self.proximityThresholdMeters, scaled))
    }
}
