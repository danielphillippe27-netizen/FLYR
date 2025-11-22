import Foundation
import CoreLocation
import Combine

@MainActor
final class UseStreetAddresses: ObservableObject {
    @Published var isWorking = false
    @Published var error: String?
    @Published var streetName: String?
    @Published var previewCount: Int?

    /// Resolve the subject street and count addresses (no list)
    func previewCount(for subjectAddress: CampaignAddress, radiusMeters: Double = 800) async {
        isWorking = true; error = nil; previewCount = nil; streetName = nil
        defer { isWorking = false }
        do {
            let center: CLLocationCoordinate2D
            if let lat = subjectAddress.lat, let lon = subjectAddress.lon {
                center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else {
                // Forward geocode the address to get coordinates
                let geocode = try await GeoAPI.shared.forwardGeocodeSeed(subjectAddress.address)
                center = geocode.coordinate
            }
            let (name, midpoint) = try await GeoAPI.shared.reverseStreet(at: center)
            streetName = name
            let items = try await GeoAPI.shared.addressesOnStreetJSON(streetName: name, center: midpoint, radiusMeters: radiusMeters)
            previewCount = items.count
        } catch { self.error = "\(error)" }
    }

    /// Fetch and insert all street addresses
    func addEntireStreet(to campaignID: UUID, subjectAddress: CampaignAddress, radiusMeters: Double = 800) async -> Int? {
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            let center: CLLocationCoordinate2D
            if let lat = subjectAddress.lat, let lon = subjectAddress.lon {
                center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else {
                // Forward geocode the address to get coordinates
                let geocode = try await GeoAPI.shared.forwardGeocodeSeed(subjectAddress.address)
                center = geocode.coordinate
            }
            let (name, midpoint) = try await GeoAPI.shared.reverseStreet(at: center)
            let items = try await GeoAPI.shared.addressesOnStreetJSON(streetName: name, center: midpoint, radiusMeters: radiusMeters)
            let inserted = try await CampaignsAPI.shared.bulkAddAddresses(campaignID: campaignID, records: items)
            previewCount = inserted
            streetName = name
            return inserted
        } catch { self.error = "\(error)"; return nil }
    }
}
