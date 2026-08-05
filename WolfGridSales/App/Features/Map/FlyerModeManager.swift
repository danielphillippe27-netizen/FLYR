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
    static let proximityThresholdMeters: Double = 15.0
    static let maxProximityThresholdMeters: Double = 25.0
    static let dwellSeconds: TimeInterval = 5.0
    static let maxCompletionSpeedMPS: Double = 2.5

    @Published private(set) var currentAddress: FlyerAddress?
    @Published private(set) var addresses: [FlyerAddress] = []

    var onAddressCompleted: ((UUID, AddressStatus) -> Void)?
    var automaticStatusForAddress: ((UUID) -> AddressStatus)?
    var renderedTargetProvider: ((CLLocation, Double) async -> FlyerAddress?)?

    private var locationCancellable: AnyCancellable?
    private var dwellTimerCancellable: AnyCancellable?
    private var dwellTracker: [UUID: Date] = [:]
    private var completedAddressIds = Set<UUID>()
    private var parcelAutoCompleteTargets: [SessionParcelAutoCompleteTarget] = []

    func load(campaignId _: UUID, featuresService: MapFeaturesService) async {
        addresses = []
        currentAddress = nil

        let buildingFeatures = featuresService.buildings?.features ?? []
        let addressFeatures = featuresService.addresses?.features ?? []
        addresses = addressesFromFlyerTargets(
            CampaignTargetResolver.flyerTargets(buildings: buildingFeatures, addresses: addressFeatures)
        )
        addresses.removeAll { completedAddressIds.contains($0.id) }

        currentAddress = nearestAddress(to: SessionManager.shared.currentLocation)
    }

    func load(targets: [ResolvedCampaignTarget]) {
        addresses = addressesFromFlyerTargets(targets)
        addresses.removeAll { completedAddressIds.contains($0.id) }
        currentAddress = nearestAddress(to: SessionManager.shared.currentLocation)
    }

    func startObservingLocation() {
        stopObservingLocation()
        locationCancellable = SessionManager.shared.$currentLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self = self, let location = location else { return }
                Task { @MainActor in
                    await self.checkProximity(location: location)
                }
            }

        dwellTimerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self,
                      SessionManager.shared.sessionId != nil,
                      SessionManager.shared.sessionMode == .flyer,
                      let location = SessionManager.shared.currentLocation else { return }
                Task { @MainActor in
                    await self.checkProximity(location: location)
                }
            }

        if let location = SessionManager.shared.currentLocation {
            Task { @MainActor in
                await self.checkProximity(location: location)
            }
        }
    }

    func stopObservingLocation() {
        locationCancellable = nil
        dwellTimerCancellable = nil
    }

    func reset() {
        stopObservingLocation()
        addresses = []
        currentAddress = nil
        dwellTracker = [:]
        completedAddressIds = []
        parcelAutoCompleteTargets = []
    }

    func configureParcelAutoCompleteTargets(_ targets: [SessionParcelAutoCompleteTarget]) {
        parcelAutoCompleteTargets = targets
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
        let threshold = adaptiveThresholdMeters(for: location)
        let renderedAddress = await renderedTargetProvider?(location, threshold)
        var candidateAddresses = addresses
        if let renderedAddress,
           !completedAddressIds.contains(renderedAddress.id),
           !candidateAddresses.contains(where: { $0.id == renderedAddress.id }) {
            candidateAddresses.insert(renderedAddress, at: 0)
        }

        guard !candidateAddresses.isEmpty else {
            currentAddress = nil
            dwellTracker = [:]
            return
        }

        // Drive-by guard: don't auto-complete while moving too fast.
        if location.speed >= 0, location.speed > Self.maxCompletionSpeedMPS {
            currentAddress = nearestAddress(to: location, within: candidateAddresses)
            return
        }

        let parcelMatchedAddress = parcelAutoCompleteAddress(
            containing: location.coordinate,
            among: candidateAddresses
        )
        currentAddress = parcelMatchedAddress ?? nearestAddress(to: location, within: candidateAddresses)

        // Keep dwell state only for addresses still within proximity or the current linked parcel.
        let parcelMatchedAddressId = parcelMatchedAddress?.id
        dwellTracker = dwellTracker.filter { addressId, _ in
            if addressId == parcelMatchedAddressId {
                return true
            }
            guard let address = candidateAddresses.first(where: { $0.id == addressId }) else { return false }
            let addrLocation = CLLocation(latitude: address.coordinate.latitude, longitude: address.coordinate.longitude)
            return location.distance(from: addrLocation) <= threshold
        }

        let matchedAddress = parcelMatchedAddress ?? renderedAddress.flatMap { rendered -> FlyerAddress? in
            guard !completedAddressIds.contains(rendered.id) else { return nil }
            return rendered
        } ?? candidateAddresses.first(where: { addr in
            let addrLocation = CLLocation(latitude: addr.coordinate.latitude, longitude: addr.coordinate.longitude)
            return location.distance(from: addrLocation) <= threshold
        })

        guard let matchedAddress else { return }

        let addressId = matchedAddress.id
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
        completedAddressIds.insert(addressId)

        addresses.removeAll { $0.id == addressId }
        dwellTracker[addressId] = nil
        currentAddress = nearestAddress(to: location)
    }

    func parcelAutoCompleteAddress(
        containing coordinate: CLLocationCoordinate2D,
        among candidates: [FlyerAddress]
    ) -> FlyerAddress? {
        guard !parcelAutoCompleteTargets.isEmpty,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        var candidatesById: [UUID: FlyerAddress] = [:]
        for candidate in candidates where !completedAddressIds.contains(candidate.id) {
            candidatesById[candidate.id] = candidate
        }
        var matchedAddresses: [UUID: FlyerAddress] = [:]

        for target in parcelAutoCompleteTargets where target.contains(coordinate) {
            let activeAddressIds = target.addressIds.filter { addressId in
                !completedAddressIds.contains(addressId) && candidatesById[addressId] != nil
            }
            guard activeAddressIds.count == 1,
                  let address = candidatesById[activeAddressIds[0]] else {
                continue
            }
            matchedAddresses[address.id] = address
        }

        guard matchedAddresses.count == 1 else {
            if matchedAddresses.count > 1 {
                print("⏭️ [FlyerModeManager] Skipping parcel auto-complete: multiple linked flyer targets contain GPS point")
            }
            return nil
        }

        return matchedAddresses.values.first
    }

    private func adaptiveThresholdMeters(for location: CLLocation) -> Double {
        guard location.horizontalAccuracy > 0 else { return Self.proximityThresholdMeters }
        let scaled = location.horizontalAccuracy * 1.2
        return min(Self.maxProximityThresholdMeters, max(Self.proximityThresholdMeters, scaled))
    }

    private func nearestAddress(to location: CLLocation?, within candidates: [FlyerAddress]) -> FlyerAddress? {
        guard !candidates.isEmpty else { return nil }
        guard let location else { return candidates.first }
        return candidates.min(by: { lhs, rhs in
            let l = location.distance(from: CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude))
            let r = location.distance(from: CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude))
            return l < r
        })
    }
}
