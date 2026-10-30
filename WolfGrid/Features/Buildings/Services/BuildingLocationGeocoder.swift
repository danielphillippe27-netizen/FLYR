import Foundation
import CoreLocation
import GoogleMaps

extension AutomaticBuildingLocation {
    @MainActor
    static func reverseGeocode(_ payload: ManualAddressCreateOutboxPayload) async -> ManualAddressCreateOutboxPayload? {
        guard payload.addressProvenance == provenance else { return nil }
        return await BuildingLocationGeocodeRequest(payload: payload).resolve()
    }
}

/// Bound the lookup so an unavailable geocoder only briefly delays sync.
@MainActor
private final class BuildingLocationGeocodeRequest {
    private let payload: ManualAddressCreateOutboxPayload
    private let geocoder = GMSGeocoder()
    private var continuation: CheckedContinuation<ManualAddressCreateOutboxPayload?, Never>?
    private var timeout: Task<Void, Never>?

    init(payload: ManualAddressCreateOutboxPayload) { self.payload = payload }

    func resolve() async -> ManualAddressCreateOutboxPayload? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let coordinate = CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude)
            geocoder.reverseGeocodeCoordinate(coordinate) { [self] response, _ in
                Task { @MainActor in
                    guard let address = response?.firstResult(),
                          CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            .distance(from: CLLocation(latitude: address.coordinate.latitude, longitude: address.coordinate.longitude)) <= 80 else {
                        finish(nil)
                        return
                    }
                    finish(AutomaticBuildingLocation.resolvedPayload(
                        payload, thoroughfare: address.thoroughfare,
                        locality: address.locality, region: address.administrativeArea,
                        postalCode: address.postalCode, country: address.country
                    ))
                }
            }
            timeout = Task { [self] in
                do { try await Task.sleep(for: .seconds(8)) }
                catch { return }
                finish(nil)
            }
        }
    }

    private func finish(_ result: ManualAddressCreateOutboxPayload?) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(returning: result)
    }
}

