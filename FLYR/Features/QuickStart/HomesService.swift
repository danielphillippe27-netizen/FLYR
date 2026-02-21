import Foundation
import CoreLocation
import Supabase

struct NearbyHome: Identifiable, Codable {
    let addressId: UUID
    let lat: Double
    let lng: Double
    let displayAddress: String
    let distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case addressId = "address_id"
        case lat
        case lng
        case displayAddress = "display_address"
        case distanceM = "distance_m"
    }

    var id: UUID { addressId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

@MainActor
final class HomesService {
    static let shared = HomesService()

    private let client = SupabaseManager.shared.client

    private init() {}

    func fetchNearbyHomes(
        center: CLLocationCoordinate2D,
        radiusMeters: Int = 500,
        limit: Int = 300,
        workspaceId: UUID?
    ) async throws -> [NearbyHome] {
        var params: [String: AnyCodable] = [
            "lat": AnyCodable(center.latitude),
            "lng": AnyCodable(center.longitude),
            "radius_m": AnyCodable(radiusMeters),
            "limit_n": AnyCodable(limit)
        ]
        if let workspaceId {
            params["p_workspace_id"] = AnyCodable(workspaceId.uuidString)
        }

        let response = try await client
            .rpc("homes_nearby", params: params)
            .execute()

        let decoder = JSONDecoder()
        let homes = try decoder.decode([NearbyHome].self, from: response.data)
        if homes.isEmpty {
            return try await fetchNearbyHomesSilverFallback(
                center: center,
                radiusMeters: radiusMeters,
                limit: limit
            )
        }
        return homes.sorted {
            let lhs = $0.distanceM ?? CLLocation(latitude: center.latitude, longitude: center.longitude)
                .distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))
            let rhs = $1.distanceM ?? CLLocation(latitude: center.latitude, longitude: center.longitude)
                .distance(from: CLLocation(latitude: $1.lat, longitude: $1.lng))
            if lhs == rhs {
                return $0.addressId.uuidString < $1.addressId.uuidString
            }
            return lhs < rhs
        }
    }

    private func fetchNearbyHomesSilverFallback(
        center: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int
    ) async throws -> [NearbyHome] {
        let candidates = try await GeoAPI.shared.nearbyAddresses(
            around: center,
            limit: max(limit, 50)
        )
        let radius = Double(max(1, radiusMeters))
        let filtered = candidates
            .filter { $0.distanceMeters <= radius }
            .prefix(limit)
            .map { candidate in
                NearbyHome(
                    addressId: candidate.id,
                    lat: candidate.coordinate.latitude,
                    lng: candidate.coordinate.longitude,
                    displayAddress: candidate.address,
                    distanceM: candidate.distanceMeters
                )
            }
        return Array(filtered)
    }

    func createQuickStartCampaign(
        center: CLLocationCoordinate2D,
        radiusMeters: Int,
        homes: [NearbyHome],
        workspaceId: UUID
    ) async throws -> CampaignV2 {
        let addresses = homes.map {
            CampaignAddress(address: $0.displayAddress, coordinate: $0.coordinate)
        }

        let name = quickStartCampaignName(radiusMeters: radiusMeters)
        let description = String(
            format: "source=quick_start radius_m=%d center_lat=%.6f center_lng=%.6f",
            radiusMeters,
            center.latitude,
            center.longitude
        )

        let payload = CampaignCreatePayloadV2(
            name: name,
            description: description,
            type: .doorKnock,
            addressSource: .closestHome,
            addressTargetCount: addresses.count,
            seedQuery: "Quick Start",
            seedLon: center.longitude,
            seedLat: center.latitude,
            tags: "quick_start",
            addressesJSON: addresses,
            workspaceId: workspaceId
        )

        print("🌐 [QuickStart] Creating campaign with \(addresses.count) homes")
        let campaign = try await CampaignsAPI.shared.createV2(payload)

        // Best-effort: link quick-start addresses to Gold buildings so map can use the same building path.
        let polygonGeoJSON = quickStartPolygonGeoJSON(center: center, radiusMeters: radiusMeters)
        let linkParams: [String: AnyCodable] = [
            "p_campaign_id": AnyCodable(campaign.id.uuidString),
            "p_polygon_geojson": AnyCodable(polygonGeoJSON)
        ]
        do {
            _ = try await client.rpc("link_campaign_addresses_gold", params: linkParams).execute()
        } catch {
            print("⚠️ [QuickStart] Gold linking skipped: \(error)")
        }

        // Run the same building-materialization path used by campaign map workflows.
        do {
            let campaignAddresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaign.id)
            if !campaignAddresses.isEmpty {
                let ensure = try await BuildingsAPI.shared.ensureBuildingPolygons(addresses: campaignAddresses)
                print("✅ [QuickStart] Building ensure complete: matched=\(ensure.matched) proxies=\(ensure.proxies) addresses=\(ensure.addresses)")
                if let features = ensure.features, !features.isEmpty {
                    MapFeaturesService.shared.primeBuildingPolygons(
                        campaignId: campaign.id.uuidString,
                        features: features
                    )
                }

                // Warm building fetch using campaign path, then fallback to address-id path if needed.
                let byCampaign = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaign.id)
                if byCampaign.features.isEmpty {
                    let byAddress = try await BuildingsAPI.shared.fetchBuildingPolygons(addressIds: campaignAddresses.map(\.id))
                    print("✅ [QuickStart] Address-id building fallback loaded \(byAddress.features.count) features")
                } else {
                    print("✅ [QuickStart] Campaign building fetch loaded \(byCampaign.features.count) features")
                }
            } else {
                print("⚠️ [QuickStart] No campaign addresses found to ensure buildings")
            }
        } catch {
            print("⚠️ [QuickStart] Building ensure/fetch skipped: \(error)")
        }

        return campaign
    }

    private func quickStartCampaignName(radiusMeters: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return "Quick Start - \(formatter.string(from: Date())) - \(radiusMeters)m"
    }

    private func quickStartPolygonGeoJSON(
        center: CLLocationCoordinate2D,
        radiusMeters: Int,
        segments: Int = 32
    ) -> String {
        let radius = max(Double(radiusMeters), 1)
        let latDelta = radius / 111_320.0
        let metersPerLonDegree = max(111_320.0 * cos(center.latitude * .pi / 180.0), 1e-6)
        let lonDelta = radius / metersPerLonDegree

        var ring: [[Double]] = []
        ring.reserveCapacity(segments + 1)
        for index in 0...segments {
            let angle = (2.0 * Double.pi * Double(index)) / Double(segments)
            let lon = center.longitude + (lonDelta * cos(angle))
            let lat = center.latitude + (latDelta * sin(angle))
            ring.append([lon, lat])
        }

        let geojson: [String: Any] = [
            "type": "Polygon",
            "coordinates": [ring]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: geojson),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"Polygon\",\"coordinates\":[]}"
        }
        return text
    }
}
