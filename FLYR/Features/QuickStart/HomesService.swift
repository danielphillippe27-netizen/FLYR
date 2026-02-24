import Foundation
import CoreLocation

@MainActor
final class HomesService {
    static let shared = HomesService()

    private init() {}

    func createQuickStartCampaign(
        center: CLLocationCoordinate2D,
        radiusMeters: Int,
        limitHomes: Int,
        workspaceId: UUID
    ) async throws -> CampaignV2 {
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
            addressTargetCount: limitHomes,
            seedQuery: "Quick Start",
            seedLon: center.longitude,
            seedLat: center.latitude,
            tags: "quick_start",
            addressesJSON: [],
            workspaceId: workspaceId
        )

        print("🌐 [QuickStart] Creating campaign shell for closest-home flow")
        let campaign = try await CampaignsAPI.shared.createV2(payload)

        let polygonGeoJSON = quickStartPolygonGeoJSON(center: center, radiusMeters: radiusMeters)
        try await CampaignsAPI.shared.updateTerritoryBoundary(
            campaignId: campaign.id,
            polygonGeoJSON: polygonGeoJSON
        )

        let provision = try await CampaignsAPI.shared.provisionCampaign(campaignId: campaign.id)
        let state = try await CampaignsAPI.shared.waitForProvisionReady(campaignId: campaign.id)

        if state.provisionStatus == "failed" {
            let detail = provision?.message ?? "Provision status failed"
            throw NSError(
                domain: "QuickStart",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Quick Start provisioning failed: \(detail)"]
            )
        }

        if state.provisionStatus != "ready" {
            print("⚠️ [QuickStart] Provision status did not reach ready: \(state.provisionStatus ?? "unknown")")
        }

        let campaignAddresses = try await fetchCampaignAddressesWithRetry(campaignId: campaign.id)
        guard !campaignAddresses.isEmpty else {
            throw NSError(
                domain: "QuickStart",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No homes were found within \(radiusMeters)m of your current location."]
            )
        }

        // Best-effort building prewarm so quick start lands with populated map layers.
        do {
            let byCampaign = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaign.id)
            if !byCampaign.features.isEmpty {
                MapFeaturesService.shared.primeBuildingPolygons(
                    campaignId: campaign.id.uuidString,
                    features: byCampaign.features
                )
                print("✅ [QuickStart] Campaign building fetch loaded \(byCampaign.features.count) features")
            } else {
                print("⚠️ [QuickStart] Campaign building fetch empty, trying address-id fallback")
                let byAddress = try await BuildingsAPI.shared.fetchBuildingPolygons(addressIds: campaignAddresses.map(\.id))
                if !byAddress.features.isEmpty {
                    MapFeaturesService.shared.primeBuildingPolygons(
                        campaignId: campaign.id.uuidString,
                        features: byAddress.features
                    )
                }
                print("✅ [QuickStart] Address-id building fallback loaded \(byAddress.features.count) features")
            }
        } catch {
            print("⚠️ [QuickStart] Building prewarm skipped: \(error)")
        }

        return campaign
    }

    private func fetchCampaignAddressesWithRetry(
        campaignId: UUID,
        attempts: Int = 8,
        delayMs: UInt64 = 350
    ) async throws -> [CampaignAddressRow] {
        var lastError: Error?

        for attempt in 1...max(attempts, 1) {
            do {
                let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaignId)
                if !addresses.isEmpty {
                    print("✅ [QuickStart] Loaded \(addresses.count) addresses after provision (attempt \(attempt))")
                    return addresses
                }
                print("⚠️ [QuickStart] No addresses yet for campaign \(campaignId) (attempt \(attempt)/\(attempts))")
            } catch {
                lastError = error
                print("⚠️ [QuickStart] Address fetch attempt \(attempt)/\(attempts) failed: \(error)")
            }

            if attempt < attempts {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }

        if let lastError {
            throw lastError
        }
        return []
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
