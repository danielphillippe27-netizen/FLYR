import Foundation
import CoreLocation
import Combine
import Supabase

/// Single address in the flyer route (ordered by cluster_id, sequence).
struct FlyerAddress {
    let id: UUID
    let formatted: String
    let clusterId: Int
    let coordinate: CLLocationCoordinate2D
    /// e.g. "Elm St Odd #" or "Main St Even #"
    let segmentLabel: String
}

/// Row from campaign_addresses for route ordering (cluster_id, sequence).
private struct CampaignAddressRouteRow: Codable {
    let id: UUID
    let clusterId: Int?
    let sequence: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case clusterId = "cluster_id"
        case sequence
    }
}

/// Manages flyer mode: loads route (cluster_id + sequence), observes GPS, and auto-marks addresses green when within proximity.
@MainActor
final class FlyerModeManager: ObservableObject {
    static let proximityThresholdMeters: Double = 15.0

    @Published private(set) var currentAddress: FlyerAddress?
    @Published private(set) var addresses: [FlyerAddress] = []

    var onAddressCompleted: ((UUID) -> Void)?

    private var currentIndex: Int = 0
    private var requiresOrderedProgression = true
    private var locationCancellable: AnyCancellable?
    private let client = SupabaseManager.shared.client

    func load(campaignId: UUID, featuresService: MapFeaturesService) async {
        addresses = []
        currentIndex = 0
        currentAddress = nil
        requiresOrderedProgression = true

        let routeRows: [CampaignAddressRouteRow]
        do {
            let response = try await client
                .from("campaign_addresses")
                .select("id, cluster_id, sequence")
                .eq("campaign_id", value: campaignId.uuidString)
                .order("cluster_id")
                .order("sequence")
                .execute()
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            routeRows = try decoder.decode([CampaignAddressRouteRow].self, from: response.data)
        } catch {
            return
        }

        let ordered = routeRows
            .filter { $0.clusterId != nil }
            .sorted { a, b in
                let c1 = a.clusterId!, c2 = b.clusterId!
                if c1 != c2 { return c1 < c2 }
                return (a.sequence ?? 0) < (b.sequence ?? 0)
            }

        guard let addressFeatures = featuresService.addresses?.features else {
            return
        }

        var idToFormatted: [UUID: String] = [:]
        var idToStreetName: [UUID: String] = [:]
        var idToHouseNumber: [UUID: String] = [:]
        var idToCoordinate: [UUID: CLLocationCoordinate2D] = [:]
        for feature in addressFeatures {
            guard let idStr = feature.properties.id ?? feature.id, let uuid = UUID(uuidString: idStr) else { continue }
            idToFormatted[uuid] = feature.properties.formatted ?? ""
            idToStreetName[uuid] = feature.properties.streetName ?? ""
            idToHouseNumber[uuid] = feature.properties.houseNumber ?? ""
            if let point = feature.geometry.asPoint, point.count >= 2 {
                idToCoordinate[uuid] = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
            }
        }

        if !ordered.isEmpty {
            var list: [FlyerAddress] = []
            for row in ordered {
                guard let clusterId = row.clusterId,
                      let coord = idToCoordinate[row.id] else { continue }
                list.append(FlyerAddress(
                    id: row.id,
                    formatted: idToFormatted[row.id] ?? "",
                    clusterId: clusterId,
                    coordinate: coord,
                    segmentLabel: ""
                ))
            }
            addresses = Self.assignSegmentLabels(to: list, idToStreetName: idToStreetName, idToHouseNumber: idToHouseNumber)
            requiresOrderedProgression = true
        } else {
            // Quick Start / no route clustering: proximity marks any remaining nearby address.
            let fallback = addressFeatures.compactMap { feature -> FlyerAddress? in
                guard let idStr = feature.properties.id ?? feature.id,
                      let id = UUID(uuidString: idStr),
                      let coord = idToCoordinate[id] else { return nil }
                return FlyerAddress(
                    id: id,
                    formatted: idToFormatted[id] ?? "",
                    clusterId: 0,
                    coordinate: coord,
                    segmentLabel: "Nearby"
                )
            }
            addresses = fallback
            requiresOrderedProgression = false
        }
        currentIndex = 0
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
        currentIndex = 0
        currentAddress = nil
        requiresOrderedProgression = true
    }

    private func checkProximity(location: CLLocation) async {
        guard !addresses.isEmpty else {
            currentAddress = nil
            return
        }

        let matchedIndex: Int?
        if requiresOrderedProgression {
            guard currentIndex < addresses.count else {
                currentAddress = nil
                return
            }
            let addr = addresses[currentIndex]
            let addrLocation = CLLocation(latitude: addr.coordinate.latitude, longitude: addr.coordinate.longitude)
            let distance = location.distance(from: addrLocation)
            matchedIndex = distance <= Self.proximityThresholdMeters ? currentIndex : nil
        } else {
            matchedIndex = addresses.firstIndex(where: { addr in
                let addrLocation = CLLocation(latitude: addr.coordinate.latitude, longitude: addr.coordinate.longitude)
                return location.distance(from: addrLocation) <= Self.proximityThresholdMeters
            })
        }

        guard let matchedIndex else { return }

        let addressId = addresses[matchedIndex].id
        onAddressCompleted?(addressId)

        guard let campaignId = SessionManager.shared.campaignId else { return }
        try? await VisitsAPI.shared.updateStatus(
            addressId: addressId,
            campaignId: campaignId,
            status: .delivered,
            notes: nil
        )

        if requiresOrderedProgression {
            currentIndex += 1
            currentAddress = currentIndex < addresses.count ? addresses[currentIndex] : nil
        } else {
            addresses.remove(at: matchedIndex)
            currentAddress = addresses.min(by: { lhs, rhs in
                let l = location.distance(from: CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude))
                let r = location.distance(from: CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude))
                return l < r
            })
        }
    }

    /// Fills segmentLabel for each address: "Street Name Odd #" or "Street Name Even #" per cluster.
    private static func assignSegmentLabels(to list: [FlyerAddress], idToStreetName: [UUID: String], idToHouseNumber: [UUID: String]) -> [FlyerAddress] {
        let byCluster = Dictionary(grouping: list, by: { $0.clusterId })
        var clusterToLabel: [Int: String] = [:]
        for (clusterId, addrs) in byCluster {
            let streetName = addrs.compactMap { idToStreetName[$0.id] }.first(where: { !$0.isEmpty }) ?? ""
            let houseNumbers = addrs.compactMap { idToHouseNumber[$0.id] }.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let oddCount = houseNumbers.filter { $0 % 2 != 0 }.count
            let evenCount = houseNumbers.filter { $0 % 2 == 0 }.count
            let oddEven: String
            if oddCount > evenCount {
                oddEven = " Odd #"
            } else if evenCount > oddCount {
                oddEven = " Even #"
            } else {
                oddEven = ""
            }
            let label = streetName.isEmpty ? "Segment \(clusterId)" : (streetName.trimmingCharacters(in: .whitespaces) + oddEven)
            clusterToLabel[clusterId] = label
        }
        return list.map { addr in
            FlyerAddress(
                id: addr.id,
                formatted: addr.formatted,
                clusterId: addr.clusterId,
                coordinate: addr.coordinate,
                segmentLabel: clusterToLabel[addr.clusterId] ?? "Segment \(addr.clusterId)"
            )
        }
    }
}
