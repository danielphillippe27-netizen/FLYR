import Foundation
import CoreLocation
import Combine

/// Single address for flyer mode (proximity is per address, not per building).
struct FlyerAddress {
    let id: UUID
    let formatted: String
    let coordinate: CLLocationCoordinate2D
}

/// Manages flyer mode: uses campaign addresses from map features, observes GPS, and auto-marks addresses delivered (green) when within proximity.
@MainActor
final class FlyerModeManager: ObservableObject {
    static let proximityThresholdMeters: Double = 10.0

    @Published private(set) var currentAddress: FlyerAddress?
    @Published private(set) var addresses: [FlyerAddress] = []

    var onAddressCompleted: ((UUID) -> Void)?

    private var locationCancellable: AnyCancellable?

    func load(campaignId: UUID, featuresService: MapFeaturesService) async {
        addresses = []
        currentAddress = nil

        guard let addressFeatures = featuresService.addresses?.features else {
            return
        }

        var idToFormatted: [UUID: String] = [:]
        var idToCoordinate: [UUID: CLLocationCoordinate2D] = [:]
        for feature in addressFeatures {
            guard let idStr = feature.properties.id ?? feature.id, let uuid = UUID(uuidString: idStr) else { continue }
            idToFormatted[uuid] = feature.properties.formatted ?? ""
            if let point = feature.geometry.asPoint, point.count >= 2 {
                idToCoordinate[uuid] = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
            }
        }

        addresses = addressFeatures.compactMap { feature -> FlyerAddress? in
            guard let idStr = feature.properties.id ?? feature.id,
                  let id = UUID(uuidString: idStr),
                  let coord = idToCoordinate[id] else { return nil }
            return FlyerAddress(
                id: id,
                formatted: idToFormatted[id] ?? "",
                coordinate: coord
            )
        }
        currentAddress = addresses.first
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
    }

    private func checkProximity(location: CLLocation) async {
        guard !addresses.isEmpty else {
            currentAddress = nil
            return
        }

        guard let matchedIndex = addresses.firstIndex(where: { addr in
            let addrLocation = CLLocation(latitude: addr.coordinate.latitude, longitude: addr.coordinate.longitude)
            return location.distance(from: addrLocation) <= Self.proximityThresholdMeters
        }) else { return }

        let addressId = addresses[matchedIndex].id
        onAddressCompleted?(addressId)

        guard let campaignId = SessionManager.shared.campaignId else { return }
        try? await VisitsAPI.shared.updateStatus(
            addressId: addressId,
            campaignId: campaignId,
            status: .delivered,
            notes: nil
        )

        addresses.remove(at: matchedIndex)
        currentAddress = addresses.min(by: { lhs, rhs in
            let l = location.distance(from: CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude))
            let r = location.distance(from: CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude))
            return l < r
        })
    }
}
