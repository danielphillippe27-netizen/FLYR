import Foundation
import CoreLocation
import Supabase

private actor BuildingFetchDeduper {
    private var tasks: [String: Task<[BuildingFeature], Error>] = [:]

    func task(
        for campaignId: String,
        creating createTask: () -> Task<[BuildingFeature], Error>
    ) -> (task: Task<[BuildingFeature], Error>, isExisting: Bool) {
        let key = campaignId.lowercased()
        if let existing = tasks[key] {
            return (existing, true)
        }
        let task = createTask()
        tasks[key] = task
        return (task, false)
    }

    func clear(for campaignId: String) {
        tasks.removeValue(forKey: campaignId.lowercased())
    }
}

/// Service for fetching and managing building-address links
final class BuildingLinkService {
    static let shared = BuildingLinkService()
    
    private let supabaseClient: SupabaseClient
    private let baseURL: String
    private let campaignRepository = CampaignRepository.shared
    private let outboxRepository = OutboxRepository.shared
    private let buildingFetchDeduper = BuildingFetchDeduper()
    
    private init() {
        self.supabaseClient = SupabaseManager.shared.client
        self.baseURL = Config.backendAPIURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    // MARK: - Fetch Buildings (from S3 via API)
    
    /// Fetches building GeoJSON for a campaign from S3 snapshot
    func fetchBuildings(campaignId: String) async throws -> [BuildingFeature] {
        let taskResult = await buildingFetchDeduper.task(for: campaignId) { [self] in
            Task { [self] in
                try await fetchBuildingsUncoalesced(campaignId: campaignId)
            }
        }

        if taskResult.isExisting {
            print("🔗 [BuildingLinkService] Coalescing in-flight buildings fetch for campaign: \(campaignId)")
        }

        do {
            let features = try await taskResult.task.value
            if !taskResult.isExisting {
                await buildingFetchDeduper.clear(for: campaignId)
            }
            return features
        } catch {
            if !taskResult.isExisting {
                await buildingFetchDeduper.clear(for: campaignId)
            }
            throw error
        }
    }

    private func fetchBuildingsUncoalesced(campaignId: String) async throws -> [BuildingFeature] {
        if !NetworkMonitor.shared.isOnline {
            if let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
               !cachedBundle.buildings.features.isEmpty {
                print(
                    "📴 [BuildingLinkService] Loaded \(cachedBundle.buildings.features.count) " +
                    "cached building GeoJSON features while offline"
                )
                return cachedBundle.buildings.features
            }
            print("📴 [BuildingLinkService] No cached building GeoJSON for offline campaign \(campaignId)")
            throw BuildingLinkError.fetchFailed
        }

        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings") else {
            throw BuildingLinkError.invalidURL
        }

        let features: [BuildingFeature]
        do {
            features = try await fetchBuildings(from: url)
        } catch {
            if let bypassURL = cacheBypassURL(from: url) {
                print("⚠️ [BuildingLinkService] Buildings endpoint failed; retrying with cache bypass")
                let refreshedFeatures = try await fetchBuildings(from: bypassURL)
                let refreshedPolygonCount = Self.polygonBuildingCount(in: refreshedFeatures)
                print("🔗 [BuildingLinkService] Cache-bypass buildings geometry after failure: polygons=\(refreshedPolygonCount) nonPolygons=\(max(refreshedFeatures.count - refreshedPolygonCount, 0))")
                await persistBuildingGeoJSONCache(campaignId: campaignId, features: refreshedFeatures)
                return refreshedFeatures
            }
            throw error
        }

        let polygonCount = Self.polygonBuildingCount(in: features)
        if features.isEmpty, let bypassURL = cacheBypassURL(from: url) {
            print("⚠️ [BuildingLinkService] Buildings endpoint returned 0 features; retrying with cache bypass")
            let refreshedFeatures = try await fetchBuildings(from: bypassURL)
            let refreshedPolygonCount = Self.polygonBuildingCount(in: refreshedFeatures)
            print("🔗 [BuildingLinkService] Cache-bypass buildings geometry: polygons=\(refreshedPolygonCount) nonPolygons=\(max(refreshedFeatures.count - refreshedPolygonCount, 0))")
            await persistBuildingGeoJSONCache(campaignId: campaignId, features: refreshedFeatures)
            return refreshedFeatures
        }

        if polygonCount == 0, !features.isEmpty, let bypassURL = cacheBypassURL(from: url) {
            print("⚠️ [BuildingLinkService] Buildings endpoint returned \(features.count) non-polygon feature(s); retrying with cache bypass")
            let refreshedFeatures = try await fetchBuildings(from: bypassURL)
            let refreshedPolygonCount = Self.polygonBuildingCount(in: refreshedFeatures)
            print("🔗 [BuildingLinkService] Cache-bypass buildings geometry: polygons=\(refreshedPolygonCount) nonPolygons=\(max(refreshedFeatures.count - refreshedPolygonCount, 0))")
            await persistBuildingGeoJSONCache(campaignId: campaignId, features: refreshedFeatures)
            return refreshedFeatures
        }

        await persistBuildingGeoJSONCache(campaignId: campaignId, features: features)
        return features
    }

    private func persistBuildingGeoJSONCache(campaignId: String, features: [BuildingFeature]) async {
        guard !features.isEmpty else { return }
        await campaignRepository.upsertBuildings(campaignId: campaignId, features: features)
        print("📦 [BuildingLinkService] Cached \(features.count) building GeoJSON features for campaign \(campaignId)")
    }

    private func fetchBuildings(from url: URL) async throws -> [BuildingFeature] {
        print("🔗 [BuildingLinkService] Fetching buildings from: \(url)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add auth if available
        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("⚠️ [BuildingLinkService] GET buildings failed for \(url): \(error.localizedDescription)")
            throw error
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("⚠️ [BuildingLinkService] GET buildings returned a non-HTTP response for \(url)")
            throw BuildingLinkError.fetchFailed
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let preview = body.count > 500 ? String(body.prefix(500)) + "…" : body
            print("⚠️ [BuildingLinkService] GET buildings HTTP \(httpResponse.statusCode) for \(url). Body: \(preview)")
            throw BuildingLinkError.fetchFailed
        }
        
        // Decode FeatureCollection
        let featureCollection = try JSONDecoder().decode(BuildingFeatureCollection.self, from: data)
        if featureCollection.features.isEmpty, let body = String(data: data, encoding: .utf8) {
            print("⚠️ [BuildingLinkService] GET buildings returned 0 features (status=200). Response preview: \(body.prefix(400))...")
        }
        let polygonCount = Self.polygonBuildingCount(in: featureCollection.features)
        if polygonCount < featureCollection.features.count {
            print("✅ [BuildingLinkService] Fetched \(featureCollection.features.count) buildings (polygons=\(polygonCount), nonPolygons=\(featureCollection.features.count - polygonCount))")
        } else {
            print("✅ [BuildingLinkService] Fetched \(featureCollection.features.count) buildings")
        }
        return featureCollection.features
    }

    private func cacheBypassURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "cache" || $0.name == "refresh" }
        queryItems.append(URLQueryItem(name: "cache", value: "bypass"))
        components.queryItems = queryItems
        return components.url
    }

    private func encodedPathComponent(_ value: String) -> String {
        // Encode ':' so Overture ids (overture:building:{uuid}) survive proxies and Next.js routing.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private func embeddedBuildingUUID(from buildingId: String) -> String? {
        let pattern = #"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"#
        guard let range = buildingId.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(buildingId[range])
    }

    private static func polygonBuildingCount(in features: [BuildingFeature]) -> Int {
        features.filter { feature in
            let geometryType = feature.geometry.type.lowercased()
            return geometryType == "polygon" || geometryType == "multipolygon"
        }.count
    }

    /// Fetches campaign address GeoJSON from the backend. The backend returns DB/RPC addresses first,
    /// and falls back to the Silver snapshot only for non-Gold campaigns with no DB rows.
    func fetchCampaignAddresses(campaignId: String) async throws -> AddressFeatureCollection {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses") else {
            throw BuildingLinkError.invalidURL
        }

        print("🔗 [BuildingLinkService] Fetching addresses from: \(url)")

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BuildingLinkError.fetchFailed
        }

        let featureCollection = try Self.decodeAddressFeatureCollection(from: data)
        if featureCollection.features.isEmpty, let body = String(data: data, encoding: .utf8) {
            print("⚠️ [BuildingLinkService] GET addresses returned 0 features (status=200). Response preview: \(body.prefix(400))...")
        }
        print("✅ [BuildingLinkService] Fetched \(featureCollection.features.count) addresses")
        return featureCollection
    }

    /// Fetches campaign parcel polygons from the backend S3/PMTiles scoped endpoint.
    func fetchCampaignParcels(campaignId: String) async throws -> ParcelFeatureCollection {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/parcels") else {
            throw BuildingLinkError.invalidURL
        }

        print("🔗 [BuildingLinkService] Fetching parcels from: \(url)")

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BuildingLinkError.fetchFailed
        }

        let rows = try JSONDecoder().decode([CampaignParcelAPIResponse].self, from: data)
        let features = rows.compactMap(Self.parcelFeature(from:))
        print("✅ [BuildingLinkService] Fetched \(features.count) parcels")
        return ParcelFeatureCollection(type: "FeatureCollection", features: features)
    }

    /// Publishes locally generated auto-links back to the campaign so other clients can hydrate
    /// from campaign_addresses.building_gers_id without running the linker again.
    func publishClientGeneratedLinks(
        campaignId: String,
        links: [ClientBuildingAddressLink],
        assetSignature: String
    ) async throws {
        guard !links.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/client-links") else {
            throw BuildingLinkError.invalidURL
        }

        let body = ClientGeneratedLinksPublishRequest(
            assetSignature: assetSignature,
            links: links.map {
                ClientGeneratedLinkPayload(
                    buildingId: $0.buildingId,
                    addressId: $0.addressId,
                    matchType: $0.matchType,
                    confidence: $0.confidence,
                    distanceMeters: $0.distanceMeters
                )
            }
        )
        let data = try JSONEncoder().encode(body)
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
        print("☁️ [BuildingLinkService] Published \(links.count) client-generated campaign links")
    }

    private static func decodeAddressFeatureCollection(from data: Data) throws -> AddressFeatureCollection {
        let decoder = JSONDecoder()
        let firstNonWhitespaceByte = data.first { byte in
            byte != 32 && byte != 10 && byte != 9 && byte != 13
        }

        if firstNonWhitespaceByte == 91 { // [
            let features = try decoder.decode([AddressFeature].self, from: data)
            return AddressFeatureCollection(type: "FeatureCollection", features: features)
        }

        return try decoder.decode(AddressFeatureCollection.self, from: data)
    }

    private struct CampaignParcelAPIResponse: Codable {
        let id: String
        let externalId: String
        let geom: String
        let properties: [String: AnyCodable]?

        enum CodingKeys: String, CodingKey {
            case id
            case externalId = "external_id"
            case geom
            case properties
        }
    }

    private struct ClientGeneratedLinksPublishRequest: Encodable {
        let assetSignature: String
        let links: [ClientGeneratedLinkPayload]

        enum CodingKeys: String, CodingKey {
            case assetSignature = "asset_signature"
            case links
        }
    }

    private struct ClientGeneratedLinkPayload: Encodable {
        let buildingId: String
        let addressId: String
        let matchType: String
        let confidence: Double
        let distanceMeters: Double

        enum CodingKeys: String, CodingKey {
            case buildingId = "building_id"
            case addressId = "address_id"
            case matchType = "match_type"
            case confidence
            case distanceMeters = "distance_meters"
        }
    }

    private static func parcelFeature(from row: CampaignParcelAPIResponse) -> ParcelFeature? {
        guard let data = row.geom.data(using: .utf8),
              let geometry = try? JSONDecoder().decode(MapFeatureGeoJSONGeometry.self, from: data) else {
            return nil
        }

        let parcelId = row.properties?["parcel_id"]?.value as? String ?? row.externalId
        let addressId = row.properties?["address_id"]?.value as? String
        let source = row.properties?["source"]?.value as? String ?? "campaign_parcels"
        let area =
            row.properties?["area_sqm"]?.value as? Double ??
            (row.properties?["area_sqm"]?.value as? Int).map(Double.init)
        return ParcelFeature(
            type: "Feature",
            id: row.id,
            geometry: geometry,
            properties: ParcelProperties(
                id: row.id,
                parcelId: parcelId,
                externalId: row.externalId,
                source: source,
                areaSqm: area,
                addressId: addressId
            )
        )
    }
    
    // MARK: - Fetch Links (from Supabase)

    /// Get all building-address links for a campaign
    func fetchLinks(campaignId: String) async throws -> [BuildingAddressLink] {
        print("🔗 [BuildingLinkService] Fetching links for campaign: \(campaignId)")

        let rawLinks: [RawBuildingAddressLink] = try await supabaseClient
            .from("building_address_links")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value

        guard !rawLinks.isEmpty else {
            print("✅ [BuildingLinkService] Fetched 0 links")
            return []
        }

        let buildingIds = Array(Set(rawLinks.map(\.buildingId)))
        let buildingRows: [BuildingIdentityRow] = try await supabaseClient
            .from("buildings")
            .select("id, gers_id")
            .in("id", values: buildingIds)
            .execute()
            .value

        let publicIdsByRowId = Dictionary(
            uniqueKeysWithValues: buildingRows.map { row in
                (row.id.lowercased(), (row.gersId?.isEmpty == false ? row.gersId! : row.id))
            }
        )

        let links = Self.deduplicateLinksByAddress(rawLinks).map { link in
            let normalizedBuildingId =
                publicIdsByRowId[link.buildingId.lowercased()] ?? link.buildingId
            return BuildingAddressLink(
                id: link.id,
                buildingId: normalizedBuildingId,
                addressId: link.addressId,
                matchType: link.matchType,
                confidence: link.confidence,
                isMultiUnit: link.isMultiUnit,
                unitCount: link.unitCount
            )
        }

        if links.count < rawLinks.count {
            print("✅ [BuildingLinkService] Fetched \(links.count) unique address links (collapsed \(rawLinks.count - links.count) duplicate building assignments)")
        } else {
            print("✅ [BuildingLinkService] Fetched \(links.count) links")
        }
        return links
    }

    private static func deduplicateLinksByAddress(_ links: [RawBuildingAddressLink]) -> [RawBuildingAddressLink] {
        guard links.count > 1 else { return links }

        var orderedAddressIds: [String] = []
        var bestByAddressId: [String: RawBuildingAddressLink] = [:]

        for link in links {
            let addressKey = link.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !addressKey.isEmpty else { continue }

            if bestByAddressId[addressKey] == nil {
                orderedAddressIds.append(addressKey)
                bestByAddressId[addressKey] = link
                continue
            }

            if linkRank(link) > linkRank(bestByAddressId[addressKey]!) {
                bestByAddressId[addressKey] = link
            }
        }

        return orderedAddressIds.compactMap { bestByAddressId[$0] }
    }

    private static func linkRank(_ link: RawBuildingAddressLink) -> Double {
        let methodScore: Double
        switch link.matchType.lowercased() {
        case "manual":
            methodScore = 5
        case "containment_verified":
            methodScore = 4
        case "point_on_surface":
            methodScore = 3
        case "parcel_verified":
            methodScore = 2
        case "proximity_fallback":
            methodScore = 0
        default:
            methodScore = 1
        }

        return methodScore * 10 + link.confidence
    }
    
    /// Get link for specific building
    func fetchLinkForBuilding(campaignId: String, gersId: String) async throws -> BuildingAddressLink? {
        let links: [BuildingAddressLink] = try await supabaseClient
            .from("building_address_links")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .eq("building_id", value: gersId)
            .execute()
            .value
        
        return links.first
    }
    
    @discardableResult
    func linkAddressToBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D? = nil
    ) async throws -> BuildingAddressMutationResponse {
        await campaignRepository.upsertBuildingAddressLinkLocally(
            campaignId: campaignId,
            buildingId: buildingId,
            addressId: addressId.uuidString,
            coordinate: coordinate
        )
        let localResponse = BuildingAddressMutationResponse(
            linkedAddressIds: [addressId],
            includesLinkedAddressIds: false
        )

        try await enqueueLinkAddressToBuilding(
            campaignId: campaignId,
            buildingId: buildingId,
            addressId: addressId,
            coordinate: coordinate
        )
        return localResponse
    }

    @discardableResult
    func performRemoteLinkAddressToBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D? = nil
    ) async throws -> BuildingAddressMutationResponse {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await postLinkAddressToBuilding(
                campaignId: campaignId,
                buildingId: normalizedBuildingId,
                addressId: addressId,
                coordinate: coordinate
            )
        } catch {
            guard shouldRetryLinkWithEmbeddedBuildingUUID(buildingId: normalizedBuildingId, error: error),
                  let embeddedUUID = embeddedBuildingUUID(from: normalizedBuildingId),
                  embeddedUUID.caseInsensitiveCompare(normalizedBuildingId) != .orderedSame else {
                throw error
            }
            print("⚠️ [BuildingLinkService] Link failed for \(normalizedBuildingId); retrying with embedded UUID \(embeddedUUID)")
            return try await postLinkAddressToBuilding(
                campaignId: campaignId,
                buildingId: embeddedUUID,
                addressId: addressId,
                coordinate: coordinate
            )
        }
    }

    private func postLinkAddressToBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D?
    ) async throws -> BuildingAddressMutationResponse {
        let encodedCampaignId = encodedPathComponent(campaignId)
        let encodedBuildingId = encodedPathComponent(buildingId)
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/\(encodedBuildingId)/addresses") else {
            throw BuildingLinkError.invalidURL
        }

        var payload: [String: Any] = ["address_id": addressId.uuidString]
        if let coordinate {
            payload["longitude"] = coordinate.longitude
            payload["latitude"] = coordinate.latitude
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
        return try JSONDecoder.supabaseDates.decode(BuildingAddressMutationResponse.self, from: responseData)
    }

    private func shouldRetryLinkWithEmbeddedBuildingUUID(buildingId: String, error: Error) -> Bool {
        guard buildingId.contains(":") else { return false }
        if case ManualShapeServiceError.api(let message) = error {
            let normalized = message.lowercased()
            return normalized.contains("building not found") || normalized.contains("http 404")
        }
        if let linkError = error as? BuildingLinkError {
            if case .fetchFailed = linkError {
                return true
            }
        }
        return false
    }

    func fetchAddressCandidates(
        campaignId: String,
        buildingId: String,
        buildingIdentifiers: [String] = [],
        radiusMeters: Double = 60,
        limit: Int = 15,
        seedCoordinate: CLLocationCoordinate2D? = nil,
        forceReverseGeocode: Bool = false,
        includeLinkedCandidates: Bool = false
    ) async throws -> BuildingAddressCandidateResponse {
        if !NetworkMonitor.shared.isOnline, let seedCoordinate {
            return try await fallbackAddressCandidates(
                campaignId: campaignId,
                buildingId: buildingId,
                buildingIdentifiers: buildingIdentifiers,
                seedCoordinate: seedCoordinate,
                radiusMeters: radiusMeters,
                limit: limit,
                includeLinkedCandidates: includeLinkedCandidates
            )
        }

        let encodedCampaignId = encodedPathComponent(campaignId)
        let encodedBuildingId = encodedPathComponent(buildingId)
        var components = URLComponents(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/\(encodedBuildingId)/address-candidates")
        components?.queryItems = [
            URLQueryItem(name: "radius_m", value: String(Int(radiusMeters.rounded()))),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let seedCoordinate {
            components?.queryItems?.append(URLQueryItem(name: "seed_lat", value: String(seedCoordinate.latitude)))
            components?.queryItems?.append(URLQueryItem(name: "seed_lng", value: String(seedCoordinate.longitude)))
        }
        if forceReverseGeocode {
            components?.queryItems?.append(URLQueryItem(name: "force_reverse_geocode", value: "true"))
        }
        if includeLinkedCandidates {
            components?.queryItems?.append(URLQueryItem(name: "include_linked_candidates", value: "true"))
        }
        for identifier in Self.candidateBuildingIdentifiers(for: buildingId, additionalIdentifiers: buildingIdentifiers) {
            components?.queryItems?.append(URLQueryItem(name: "building_identifier", value: identifier))
        }
        guard let url = components?.url else {
            throw BuildingLinkError.invalidURL
        }

        do {
            let (data, response) = try await authorizedDataRequest(url: url, suppressHTTPWarning: true)
            try ensureSuccessfulResponse(response, data: data, logFailures: false)
            let remoteResponse = try JSONDecoder.supabaseDates.decode(BuildingAddressCandidateResponse.self, from: data)
            guard let seedCoordinate else {
                return remoteResponse
            }
            if !remoteResponse.candidates.isEmpty {
                if forceReverseGeocode,
                   !remoteResponse.candidates.contains(where: \.isReverseGeocode),
                   let reverseCandidate = try? await mapboxReverseGeocodeCandidate(at: seedCoordinate) {
                    return responseByAppendingReverseCandidate(
                        reverseCandidate,
                        to: remoteResponse,
                        buildingId: buildingId,
                        radiusMeters: radiusMeters
                    )
                }
                return remoteResponse
            }

            if forceReverseGeocode,
               let reverseCandidate = try? await mapboxReverseGeocodeCandidate(at: seedCoordinate) {
                return BuildingAddressCandidateResponse(
                    buildingId: buildingId,
                    radiusMeters: radiusMeters,
                    trustDecision: AddressCandidateTrustDecision(
                        usedReverseGeocode: true,
                        reason: "client_reverse_geocode",
                        nearestCandidateDistanceMeters: nil,
                        nearestCandidateRejectedReason: nil
                    ),
                    candidates: [reverseCandidate]
                )
            }
            return remoteResponse
        } catch {
            guard let seedCoordinate else {
                throw error
            }

            do {
                let localResponse = try await fallbackAddressCandidates(
                    campaignId: campaignId,
                    buildingId: buildingId,
                    buildingIdentifiers: buildingIdentifiers,
                    seedCoordinate: seedCoordinate,
                    radiusMeters: radiusMeters,
                    limit: limit,
                    includeLinkedCandidates: includeLinkedCandidates
                )
                if forceReverseGeocode,
                   !localResponse.candidates.contains(where: \.isReverseGeocode),
                   let reverseCandidate = try? await mapboxReverseGeocodeCandidate(at: seedCoordinate) {
                    return responseByAppendingReverseCandidate(
                        reverseCandidate,
                        to: localResponse,
                        buildingId: buildingId,
                        radiusMeters: radiusMeters
                    )
                }
                return localResponse
            } catch {
                if forceReverseGeocode,
                   let reverseCandidate = try? await mapboxReverseGeocodeCandidate(at: seedCoordinate) {
                    return BuildingAddressCandidateResponse(
                        buildingId: buildingId,
                        radiusMeters: radiusMeters,
                        trustDecision: AddressCandidateTrustDecision(
                            usedReverseGeocode: true,
                            reason: "client_reverse_geocode_after_server_unavailable",
                            nearestCandidateDistanceMeters: nil,
                            nearestCandidateRejectedReason: nil
                        ),
                        candidates: [reverseCandidate]
                    )
                }
                throw error
            }
        }
    }

    private func fallbackAddressCandidates(
        campaignId: String,
        buildingId: String,
        buildingIdentifiers: [String] = [],
        seedCoordinate: CLLocationCoordinate2D,
        radiusMeters: Double,
        limit: Int,
        allowRemoteFetch: Bool = true,
        includeLinkedCandidates: Bool = false
    ) async throws -> BuildingAddressCandidateResponse {
        let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId)
        let addressCollection: AddressFeatureCollection
        if let cachedAddresses = cachedBundle?.addresses, !cachedAddresses.features.isEmpty {
            addressCollection = cachedAddresses
        } else if allowRemoteFetch, NetworkMonitor.shared.isOnline {
            addressCollection = try await fetchCampaignAddresses(campaignId: campaignId)
        } else {
            return BuildingAddressCandidateResponse(
                buildingId: buildingId,
                radiusMeters: radiusMeters,
                trustDecision: nil,
                candidates: []
            )
        }

        let localLinks = await campaignRepository.getBuildingAddressLinks(campaignId: campaignId)
        let currentBuildingIdentifiers = Self.candidateBuildingIdentifiers(
            for: buildingId,
            additionalIdentifiers: buildingIdentifiers
        )
        let linkedAddressIds = Set(
            (localLinks.isEmpty && allowRemoteFetch && NetworkMonitor.shared.isOnline
                ? ((try? await fetchLinks(campaignId: campaignId)) ?? [])
                : localLinks)
                .filter { link in
                    if !includeLinkedCandidates { return true }
                    return currentBuildingIdentifiers.contains(link.buildingId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                }
                .map { $0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let directlyLinkedAddressIds = Self.directlyLinkedAddressIds(
            in: addressCollection,
            buildingIdentifiers: includeLinkedCandidates ? currentBuildingIdentifiers : nil
        )
        let activeOrphansByAddressId = Dictionary(
            await campaignRepository.getAddressOrphans(campaignId: campaignId)
                .filter { orphan in
                    let status = orphan.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return status == nil || status == "pending" || status == "pending_review" || status == "ambiguous_match"
                }
                .sorted { lhs, rhs in
                    (lhs.nearestDistance ?? .greatestFiniteMagnitude) < (rhs.nearestDistance ?? .greatestFiniteMagnitude)
                }
                .map { ($0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0) }
        ) { first, _ in first }
        let seedLocation = CLLocation(latitude: seedCoordinate.latitude, longitude: seedCoordinate.longitude)

        let candidates = addressCollection.features.compactMap { feature -> BuildingAddressCandidate? in
            let rawId = (feature.properties.id ?? feature.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let orphan = activeOrphansByAddressId[rawId.lowercased()]
            let orphanBuildingId = orphan?.nearestBuildingId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let orphanBelongsToCurrentBuilding = orphanBuildingId.map { currentBuildingIdentifiers.contains($0) } ?? false
            let resolvedCoordinate = CampaignTargetResolver.coordinate(for: feature.geometry)
                ?? orphan.flatMap { Self.coordinate(fromOrphanCoordinateJSON: $0.coordinateJSON) }
            guard let addressId = UUID(uuidString: rawId),
                  !linkedAddressIds.contains(rawId.lowercased()),
                  !directlyLinkedAddressIds.contains(rawId.lowercased()),
                  let coordinate = resolvedCoordinate else {
                return nil
            }

            let addressLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distanceMeters = addressLocation.distance(from: seedLocation)
            guard distanceMeters <= radiusMeters else { return nil }

            let distanceScore = max(0, 1 - distanceMeters / max(radiusMeters, 1))
            let sourceScore = feature.properties.source?.lowercased() == "manual" ? 0.05 : 0
            let score = min(1, distanceScore * 0.95 + sourceScore)

            return BuildingAddressCandidate(
                id: addressId,
                formatted: feature.properties.formatted,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName,
                source: feature.properties.source,
                coordinate: CandidateCoordinate(longitude: coordinate.longitude, latitude: coordinate.latitude),
                distanceMeters: (distanceMeters * 10).rounded() / 10,
                score: (score * 1000).rounded() / 1000,
                reason: orphanBelongsToCurrentBuilding ? "Nearby orphan address" : "Nearby campaign address",
                candidateReason: orphanBelongsToCurrentBuilding ? "pending_orphan_nearest_building" : nil,
                confidenceLabel: distanceMeters <= 25 ? "high" : distanceMeters <= 60 ? "medium" : "low",
                requiresConfirmation: distanceMeters > 60
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.distanceMeters != rhs.distanceMeters { return lhs.distanceMeters < rhs.distanceMeters }
            return lhs.displayAddress.localizedStandardCompare(rhs.displayAddress) == .orderedAscending
        }
        .prefix(limit)

        return BuildingAddressCandidateResponse(
            buildingId: buildingId,
            radiusMeters: radiusMeters,
            trustDecision: nil,
            candidates: Array(candidates)
        )
    }

    static func directlyLinkedAddressIds(
        in addressCollection: AddressFeatureCollection,
        buildingIdentifiers: Set<String>? = nil
    ) -> Set<String> {
        Set(
            addressCollection.features.compactMap { feature -> String? in
                let buildingId = feature.properties.buildingGersId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let buildingId, !buildingId.isEmpty else { return nil }
                if let buildingIdentifiers,
                   !buildingIdentifiers.contains(buildingId.lowercased()) {
                    return nil
                }
                return (feature.properties.id ?? feature.id)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
        )
    }

    private static func coordinate(fromOrphanCoordinateJSON value: String?) -> CLLocationCoordinate2D? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let coordinates: [Any]?
        if let dictionary = object as? [String: Any],
           (dictionary["type"] as? String)?.lowercased() == "point" {
            coordinates = dictionary["coordinates"] as? [Any]
        } else if let array = object as? [Any] {
            coordinates = array
        } else {
            coordinates = nil
        }

        guard let coordinates, coordinates.count >= 2 else { return nil }
        let longitude = Self.doubleValue(coordinates[0])
        let latitude = Self.doubleValue(coordinates[1])
        guard let longitude, let latitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func candidateBuildingIdentifiers(
        for buildingId: String,
        additionalIdentifiers: [String] = []
    ) -> Set<String> {
        var identifiers = Set<String>()
        let rawIdentifiers = [buildingId] + additionalIdentifiers
        let pattern = #"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"#
        for rawIdentifier in rawIdentifiers {
            let normalized = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            identifiers.insert(normalized)
            if let range = normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                identifiers.insert(String(normalized[range]))
            }
        }
        return identifiers
    }

    private func responseByAppendingReverseCandidate(
        _ reverseCandidate: BuildingAddressCandidate,
        to response: BuildingAddressCandidateResponse,
        buildingId: String,
        radiusMeters: Double
    ) -> BuildingAddressCandidateResponse {
        let currentDecision = response.trustDecision
        return BuildingAddressCandidateResponse(
            buildingId: response.buildingId.isEmpty ? buildingId : response.buildingId,
            radiusMeters: response.radiusMeters > 0 ? response.radiusMeters : radiusMeters,
            trustDecision: AddressCandidateTrustDecision(
                usedReverseGeocode: true,
                reason: currentDecision?.reason ?? "client_reverse_geocode",
                nearestCandidateDistanceMeters: currentDecision?.nearestCandidateDistanceMeters,
                nearestCandidateRejectedReason: currentDecision?.nearestCandidateRejectedReason
            ),
            candidates: response.candidates + [reverseCandidate]
        )
    }

    private func mapboxReverseGeocodeCandidate(
        at coordinate: CLLocationCoordinate2D
    ) async throws -> BuildingAddressCandidate? {
        let token = Config.mapboxAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mapbox.com"
        components.path = "/geocoding/v5/mapbox.places/\(coordinate.longitude),\(coordinate.latitude).json"
        components.queryItems = [
            URLQueryItem(name: "types", value: "address"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "access_token", value: token)
        ]
        guard let url = components.url else {
            throw BuildingLinkError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BuildingLinkError.fetchFailed
        }

        let decoded = try JSONDecoder().decode(MapboxReverseGeocodeResponse.self, from: data)
        guard let feature = decoded.features.first else { return nil }
        let center = feature.center
        let longitude = center?.first ?? coordinate.longitude
        let latitude = center?.dropFirst().first ?? coordinate.latitude
        let context = feature.context ?? []

        func contextText(prefix: String) -> String? {
            context.first { $0.id.hasPrefix(prefix) }?.text
        }

        let formatted = feature.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let street = feature.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BuildingAddressCandidate(
            id: UUID(),
            candidateType: "reverse_geocode",
            isSynthetic: true,
            formatted: formatted?.isEmpty == false ? formatted : "Dropped Pin",
            formattedAddress: formatted,
            houseNumber: feature.address,
            streetName: street?.isEmpty == false ? street : nil,
            street: street?.isEmpty == false ? street : nil,
            locality: contextText(prefix: "place"),
            region: contextText(prefix: "region"),
            postalCode: contextText(prefix: "postcode"),
            country: contextText(prefix: "country"),
            source: "mapbox_reverse",
            coordinate: CandidateCoordinate(longitude: longitude, latitude: latitude),
            distanceMeters: 0,
            score: 0.35,
            reason: "Estimated address from map",
            candidateReason: "client_fallback_reverse_geocode",
            confidenceLabel: "estimated",
            requiresConfirmation: true
        )
    }

    private struct MapboxReverseGeocodeResponse: Decodable {
        let features: [Feature]

        struct Feature: Decodable {
            let address: String?
            let text: String?
            let placeName: String?
            let center: [Double]?
            let context: [Context]?

            enum CodingKeys: String, CodingKey {
                case address
                case text
                case placeName = "place_name"
                case center
                case context
            }
        }

        struct Context: Decodable {
            let id: String
            let text: String
        }
    }

    func unlinkAddressFromBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID
    ) async throws -> BuildingAddressMutationResponse {
        try await unlinkAddressFromBuilding(
            campaignId: campaignId,
            buildingId: buildingId,
            addressId: addressId,
            deleteManualAddress: false
        )
    }

    func deleteManualUnitFromBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID
    ) async throws -> BuildingAddressMutationResponse {
        try await unlinkAddressFromBuilding(
            campaignId: campaignId,
            buildingId: buildingId,
            addressId: addressId,
            deleteManualAddress: true
        )
    }

    private func unlinkAddressFromBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        deleteManualAddress: Bool
    ) async throws -> BuildingAddressMutationResponse {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBuildingId.isEmpty else {
            throw BuildingLinkError.fetchFailed
        }

        let remainingAddressIds = await campaignRepository.unlinkAddressFromBuildingLocally(
            campaignId: campaignId,
            buildingId: normalizedBuildingId,
            addressId: addressId.uuidString,
            deleteManualAddress: deleteManualAddress
        )
        let localResponse = BuildingAddressMutationResponse(
            linkedAddressIds: remainingAddressIds,
            deleted: deleteManualAddress
        )

        if !NetworkMonitor.shared.isOnline {
            try await enqueueUnlinkAddressFromBuilding(
                campaignId: campaignId,
                buildingId: normalizedBuildingId,
                addressId: addressId,
                deleteManualAddress: deleteManualAddress
            )
            return localResponse
        }

        do {
            let response = try await performRemoteUnlinkAddressFromBuilding(
                campaignId: campaignId,
                buildingId: normalizedBuildingId,
                addressId: addressId,
                deleteManualAddress: deleteManualAddress
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
            return response
        } catch {
            try await enqueueUnlinkAddressFromBuilding(
                campaignId: campaignId,
                buildingId: normalizedBuildingId,
                addressId: addressId,
                deleteManualAddress: deleteManualAddress
            )
            return localResponse
        }
    }

    func performRemoteUnlinkAddressFromBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        deleteManualAddress: Bool
    ) async throws -> BuildingAddressMutationResponse {
        let encodedCampaignId = encodedPathComponent(campaignId)
        let encodedBuildingId = encodedPathComponent(buildingId)
        var components = URLComponents(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/\(encodedBuildingId)/addresses")
        var queryItems = [URLQueryItem(name: "address_id", value: addressId.uuidString)]
        if deleteManualAddress {
            queryItems.append(URLQueryItem(name: "mode", value: "delete_manual"))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw BuildingLinkError.invalidURL
        }

        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        try ensureSuccessfulResponse(response, data: data)
        return try JSONDecoder.supabaseDates.decode(BuildingAddressMutationResponse.self, from: data)
    }

    // MARK: - Manual Map Shapes

    @discardableResult
    func createManualAddress(
        campaignId: String,
        input: ManualAddressCreateInput
    ) async throws -> ManualAddressCreateResponse {
        let addressId = UUID()
        await campaignRepository.upsertManualAddressLocally(
            campaignId: campaignId,
            addressId: addressId,
            input: input
        )

        let localResponse = makeManualAddressCreateResponse(
            addressId: addressId,
            input: input
        )

        if !NetworkMonitor.shared.isOnline {
            try await enqueueCreateManualAddress(
                campaignId: campaignId,
                addressId: addressId,
                input: input
            )
            return localResponse
        }

        do {
            let response = try await performRemoteCreateManualAddress(
                campaignId: campaignId,
                input: input,
                addressId: addressId
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
            return response
        } catch {
            try await enqueueCreateManualAddress(
                campaignId: campaignId,
                addressId: addressId,
                input: input
            )
            return localResponse
        }
    }

    @discardableResult
    func performRemoteCreateManualAddress(
        campaignId: String,
        input: ManualAddressCreateInput,
        addressId: UUID? = nil
    ) async throws -> ManualAddressCreateResponse {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses/manual") else {
            throw BuildingLinkError.invalidURL
        }

        let payload: [String: Any?] = [
            "id": addressId?.uuidString,
            "address_id": addressId?.uuidString,
            "longitude": input.coordinate.longitude,
            "latitude": input.coordinate.latitude,
            "formatted": input.formatted,
            "house_number": input.houseNumber,
            "street_name": input.streetName,
            "locality": input.locality,
            "region": input.region,
            "postal_code": input.postalCode,
            "country": input.country,
            "building_id": input.buildingId,
            "address_provenance": input.addressProvenance,
            "user_confirmed": input.userConfirmed
        ]

        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
        let decoder = JSONDecoder.supabaseDates
        return try decoder.decode(ManualAddressCreateResponse.self, from: responseData)
    }

    @discardableResult
    func createManualBuilding(
        campaignId: String,
        input: ManualBuildingCreateInput
    ) async throws -> ManualBuildingCreateResponse {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings/manual") else {
            throw BuildingLinkError.invalidURL
        }

        let ring = input.polygon.map { [$0.longitude, $0.latitude] }
        let geometry: [String: Any] = [
            "type": "Polygon",
            "coordinates": [ring]
        ]
        let payload: [String: Any?] = [
            "geometry": geometry,
            "height_m": input.heightMeters,
            "units_count": input.unitsCount,
            "levels": input.levels,
            "address_ids": input.addressIds
        ]

        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
        let decoder = JSONDecoder.supabaseDates
        return try decoder.decode(ManualBuildingCreateResponse.self, from: responseData)
    }

    func deleteManualAddress(campaignId: String, addressId: UUID) async throws {
        try await deleteAddress(campaignId: campaignId, addressId: addressId)
    }

    func deleteAddress(campaignId: String, addressId: UUID) async throws {
        await campaignRepository.deleteAddressLocally(campaignId: campaignId, addressId: addressId.uuidString)

        if !NetworkMonitor.shared.isOnline {
            try await enqueueDeleteAddress(campaignId: campaignId, addressId: addressId)
            return
        }

        do {
            try await performRemoteDeleteAddress(campaignId: campaignId, addressId: addressId)
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
        } catch {
            try await enqueueDeleteAddress(campaignId: campaignId, addressId: addressId)
        }
    }

    func performRemoteDeleteManualAddress(campaignId: String, addressId: UUID) async throws {
        try await performRemoteDeleteAddress(campaignId: campaignId, addressId: addressId)
    }

    func performRemoteDeleteAddress(campaignId: String, addressId: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses/\(addressId.uuidString)") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        try ensureSuccessfulResponse(response, data: data)
    }

    func performRemoteDeleteManualAddressOnly(campaignId: String, addressId: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses/\(addressId.uuidString)/manual") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        try ensureSuccessfulResponse(response, data: data)
    }

    func deleteManualBuilding(campaignId: String, buildingId: String) async throws {
        let encodedCampaignId = encodedPathComponent(campaignId)
        let encodedBuildingId = encodedPathComponent(buildingId)
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/\(encodedBuildingId)/manual") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        try ensureSuccessfulResponse(response, data: data)
    }

    func moveAddress(
        campaignId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D
    ) async throws {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw BuildingLinkError.fetchFailed
        }

        await campaignRepository.moveAddressLocally(
            campaignId: campaignId,
            addressId: addressId.uuidString,
            coordinate: coordinate
        )

        if !NetworkMonitor.shared.isOnline {
            try await enqueueMoveAddress(campaignId: campaignId, addressId: addressId, coordinate: coordinate)
            return
        }

        do {
            try await performRemoteMoveAddress(
                campaignId: campaignId,
                addressId: addressId,
                coordinate: coordinate
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
        } catch {
            try await enqueueMoveAddress(campaignId: campaignId, addressId: addressId, coordinate: coordinate)
        }
    }

    func moveBuilding(
        campaignId: String,
        buildingId: String,
        geometry: MapFeatureGeoJSONGeometry
    ) async throws {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBuildingId.isEmpty else {
            throw BuildingLinkError.fetchFailed
        }

        await campaignRepository.moveBuildingLocally(
            campaignId: campaignId,
            buildingId: normalizedBuildingId,
            geometry: geometry
        )

        if !NetworkMonitor.shared.isOnline {
            try await enqueueMoveBuilding(campaignId: campaignId, buildingId: normalizedBuildingId, geometry: geometry)
            return
        }

        do {
            try await performRemoteMoveBuilding(
                campaignId: campaignId,
                buildingId: normalizedBuildingId,
                geometry: geometry
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
        } catch {
            try await enqueueMoveBuilding(campaignId: campaignId, buildingId: normalizedBuildingId, geometry: geometry)
        }
    }

    @discardableResult
    func createFallbackBuilding(
        campaignId: String,
        addressId: UUID
    ) async throws -> BuildingFeature {
        let alreadyExists = await campaignRepository.hasLocalFallbackBuilding(
            campaignId: campaignId,
            addressId: addressId
        )
        guard let feature = await campaignRepository.upsertFallbackBuildingLocally(
            campaignId: campaignId,
            addressId: addressId
        ) else {
            throw BuildingLinkError.fetchFailed
        }

        if !alreadyExists {
            try await enqueueFallbackBuildingCreated(
                campaignId: campaignId,
                addressId: addressId,
                fallbackBuildingId: feature.properties.canonicalBuildingIdentifier ?? feature.id ?? campaignRepository.fallbackBuildingId(addressId: addressId),
                geometry: feature.geometry
            )
        }
        return feature
    }

    func performRemoteCreateFallbackBuilding(
        campaignId: String,
        addressId: UUID,
        fallbackBuildingId: String,
        geometry: MapFeatureGeoJSONGeometry,
        clientMutationId: String?
    ) async throws {
        let encodedCampaignId = encodedPathComponent(campaignId)
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/manual") else {
            throw BuildingLinkError.invalidURL
        }
        guard let geometryObject = Self.geoJSONDictionary(from: geometry) else {
            throw BuildingLinkError.decodingFailed
        }
        var payload: [String: Any] = [
            "geometry": geometryObject,
            "address_ids": [addressId.uuidString],
            "fallback_building_id": fallbackBuildingId,
            "geometry_source": "manual_fallback",
            "source": "manual_fallback",
            "height_m": 8,
            "units_count": 1
        ]
        if let clientMutationId {
            payload["client_mutation_id"] = clientMutationId
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
    }

    func performRemoteMoveAddress(
        campaignId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses/\(addressId.uuidString)/manual") else {
            throw BuildingLinkError.invalidURL
        }
        let payload: [String: Any] = [
            "longitude": coordinate.longitude,
            "latitude": coordinate.latitude
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "PATCH", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
    }

    func performRemoteMoveBuilding(
        campaignId: String,
        buildingId: String,
        geometry: MapFeatureGeoJSONGeometry
    ) async throws {
        let encodedCampaignId = encodedPathComponent(campaignId)
        let encodedBuildingId = encodedPathComponent(buildingId)
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/\(encodedBuildingId)/manual") else {
            throw BuildingLinkError.invalidURL
        }
        guard let geometryObject = Self.geoJSONDictionary(from: geometry) else {
            throw BuildingLinkError.decodingFailed
        }
        let payload: [String: Any] = ["geometry": geometryObject]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "PATCH", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
    }

    private func enqueueMoveAddress(
        campaignId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D
    ) async throws {
        let outboxId = await outboxRepository.enqueue(
            entityType: "address",
            entityId: "\(campaignId.lowercased()):\(addressId.uuidString.lowercased())",
            operation: .moveAddress,
            payload: MoveAddressOutboxPayload(
                campaignId: campaignId,
                addressId: addressId.uuidString,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            dependencyKey: "address:\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        await OfflineSyncCoordinator.shared.refreshPendingCount()
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    private func enqueueMoveBuilding(
        campaignId: String,
        buildingId: String,
        geometry: MapFeatureGeoJSONGeometry
    ) async throws {
        guard let geometryJSON = OfflineJSONCodec.encode(geometry) else {
            throw BuildingLinkError.decodingFailed
        }
        let outboxId = await outboxRepository.enqueue(
            entityType: "building",
            entityId: "\(campaignId.lowercased()):\(buildingId.lowercased())",
            operation: .moveBuilding,
            payload: MoveBuildingOutboxPayload(
                campaignId: campaignId,
                buildingId: buildingId,
                geometryJSON: geometryJSON
            ),
            dependencyKey: "building:\(campaignId.lowercased()):\(buildingId.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        await OfflineSyncCoordinator.shared.refreshPendingCount()
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    private func enqueueFallbackBuildingCreated(
        campaignId: String,
        addressId: UUID,
        fallbackBuildingId: String,
        geometry: MapFeatureGeoJSONGeometry
    ) async throws {
        guard let geometryJSON = OfflineJSONCodec.encode(geometry) else {
            throw BuildingLinkError.decodingFailed
        }
        let dependencyKey = "fallback_building:\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        let outboxId = await outboxRepository.enqueue(
            entityType: "fallback_building",
            entityId: "\(campaignId.lowercased()):\(fallbackBuildingId.lowercased())",
            operation: .fallbackBuildingCreated,
            payload: FallbackBuildingCreatedOutboxPayload(
                campaignId: campaignId,
                addressId: addressId.uuidString,
                fallbackBuildingId: fallbackBuildingId,
                geometryJSON: geometryJSON,
                geometrySource: "manual_fallback",
                createdAt: OfflineDateCodec.string(from: Date())
            ),
            clientMutationId: dependencyKey,
            dependencyKey: dependencyKey
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        scheduleDeferredOutboxSync()
    }

    private func enqueueLinkAddressToBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        coordinate: CLLocationCoordinate2D?
    ) async throws {
        let outboxId = await outboxRepository.enqueue(
            entityType: "address",
            entityId: "\(campaignId.lowercased()):\(addressId.uuidString.lowercased())",
            operation: .linkAddressToBuilding,
            payload: LinkAddressToBuildingOutboxPayload(
                campaignId: campaignId,
                buildingId: buildingId,
                addressId: addressId.uuidString,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            ),
            dependencyKey: "address:\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        scheduleDeferredOutboxSync()
    }

    private func scheduleDeferredOutboxSync() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            await OfflineSyncCoordinator.shared.refreshPendingCount()
            if NetworkMonitor.shared.isOnline {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    private func enqueueCreateManualAddress(
        campaignId: String,
        addressId: UUID,
        input: ManualAddressCreateInput
    ) async throws {
        let outboxId = await outboxRepository.enqueue(
            entityType: "address",
            entityId: "\(campaignId.lowercased()):\(addressId.uuidString.lowercased())",
            operation: .createManualAddress,
            payload: ManualAddressCreateOutboxPayload(
                campaignId: campaignId,
                addressId: addressId.uuidString,
                formatted: input.formatted,
                houseNumber: input.houseNumber,
                streetName: input.streetName,
                locality: input.locality,
                region: input.region,
                postalCode: input.postalCode,
                country: input.country,
                buildingId: input.buildingId,
                addressProvenance: input.addressProvenance,
                userConfirmed: input.userConfirmed,
                latitude: input.coordinate.latitude,
                longitude: input.coordinate.longitude
            ),
            dependencyKey: "address:\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        await OfflineSyncCoordinator.shared.refreshPendingCount()
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    private func makeManualAddressCreateResponse(
        addressId: UUID,
        input: ManualAddressCreateInput
    ) -> ManualAddressCreateResponse {
        ManualAddressCreateResponse(
            address: CampaignAddressResponse(
                id: addressId,
                houseNumber: input.houseNumber,
                streetName: input.streetName,
                formatted: input.formatted,
                locality: input.locality,
                region: input.region,
                postalCode: input.postalCode,
                buildingGersId: input.buildingId
            ),
            linkedBuildingId: input.buildingId
        )
    }

    private func enqueueDeleteBuilding(
        campaignId: String,
        buildingId: String
    ) async throws {
        let outboxId = await outboxRepository.enqueue(
            entityType: "building",
            entityId: "\(campaignId.lowercased()):\(buildingId.lowercased())",
            operation: .deleteBuilding,
            payload: DeleteBuildingOutboxPayload(
                campaignId: campaignId,
                buildingId: buildingId
            ),
            dependencyKey: "building:\(campaignId.lowercased()):\(buildingId.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        await OfflineSyncCoordinator.shared.refreshPendingCount()
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    private func enqueueDeleteAddress(
        campaignId: String,
        addressId: UUID
    ) async throws {
        let outboxId = await outboxRepository.enqueue(
            entityType: "address",
            entityId: "\(campaignId.lowercased()):\(addressId.uuidString.lowercased())",
            operation: .deleteAddress,
            payload: DeleteAddressOutboxPayload(
                campaignId: campaignId,
                addressId: addressId.uuidString
            ),
            dependencyKey: "address:\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        await OfflineSyncCoordinator.shared.refreshPendingCount()
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    private func enqueueUnlinkAddressFromBuilding(
        campaignId: String,
        buildingId: String,
        addressId: UUID,
        deleteManualAddress: Bool
    ) async throws {
        let outboxId = await outboxRepository.enqueue(
            entityType: "address",
            entityId: "\(campaignId.lowercased()):\(addressId.uuidString.lowercased())",
            operation: .unlinkAddressFromBuilding,
            payload: UnlinkAddressFromBuildingOutboxPayload(
                campaignId: campaignId,
                buildingId: buildingId,
                addressId: addressId.uuidString,
                deleteManualAddress: deleteManualAddress
            ),
            dependencyKey: "address:\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        )
        guard outboxId != nil else {
            throw BuildingLinkError.fetchFailed
        }
        await OfflineSyncCoordinator.shared.refreshPendingCount()
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
    }

    func performRemoteDeleteBuildingAndAddresses(campaignId: String, buildingId: String) async throws {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBuildingId.isEmpty else {
            throw BuildingLinkError.fetchFailed
        }
        let encodedCampaignId = encodedPathComponent(campaignId)
        let encodedBuildingId = encodedPathComponent(normalizedBuildingId)
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(encodedCampaignId)/buildings/\(encodedBuildingId)") else {
            throw BuildingLinkError.invalidURL
        }

        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        do {
            try ensureSuccessfulResponse(response, data: data)
        } catch {
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 404 || Self.responseBodyLooksLikeHTML(String(data: data, encoding: .utf8) ?? "") else {
                throw error
            }

            print("⚠️ [BuildingLinkService] Building delete API unavailable, falling back to direct Supabase cleanup")
            try await deleteBuildingAndAddressesFallback(campaignId: campaignId, buildingId: normalizedBuildingId)
        }
    }

    func deleteBuildingAndAddresses(campaignId: String, buildingId: String) async throws {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBuildingId.isEmpty else {
            throw BuildingLinkError.fetchFailed
        }

        _ = await campaignRepository.deleteBuildingLocally(
            campaignId: campaignId,
            buildingId: normalizedBuildingId
        )

        if !NetworkMonitor.shared.isOnline {
            try await enqueueDeleteBuilding(campaignId: campaignId, buildingId: normalizedBuildingId)
            return
        }

        do {
            try await performRemoteDeleteBuildingAndAddresses(campaignId: campaignId, buildingId: normalizedBuildingId)
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
        } catch {
            try await enqueueDeleteBuilding(campaignId: campaignId, buildingId: normalizedBuildingId)
        }
    }
    
    // MARK: - Fetch Addresses
    
    func fetchAddresses(campaignId: String) async throws -> [CampaignAddress] {
        print("🔗 [BuildingLinkService] Fetching addresses for campaign: \(campaignId)")
        
        let addresses: [CampaignAddress] = try await supabaseClient
            .from("campaign_addresses")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value
        
        print("✅ [BuildingLinkService] Fetched \(addresses.count) addresses")
        return addresses
    }
    
    // MARK: - Fetch Building Stats (for colors)
    
    func fetchBuildingStats(campaignId: String) async throws -> [BuildingStats] {
        let stats: [BuildingStats] = try await supabaseClient
            .from("building_stats")
            .select("gers_id, status, scans_total")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value
        
        return stats
    }
    
    // MARK: - Fetch Building Units (for townhouses)
    
    func fetchBuildingUnits(campaignId: String, buildingGersId: String) async throws -> [BuildingUnit] {
        let units: [BuildingUnit] = try await supabaseClient
            .from("building_units")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .eq("parent_building_id", value: buildingGersId)
            .execute()
            .value
        
        return units
    }
    
    // MARK: - Combined Fetch
    
    /// Load all campaign data needed for building display
    func loadCampaignData(campaignId: String) async throws -> CampaignBuildingData {
        print("🔄 [BuildingLinkService] Loading all campaign data...")
        
        async let buildingsTask = fetchBuildings(campaignId: campaignId)
        async let linksTask = fetchLinks(campaignId: campaignId)
        async let addressesTask = fetchAddresses(campaignId: campaignId)
        async let statsTask = fetchBuildingStats(campaignId: campaignId)
        
        let (buildings, links, addresses, stats) = try await (buildingsTask, linksTask, addressesTask, statsTask)
        
        // Create lookup dictionaries
        let linksByBuildingId = Dictionary(uniqueKeysWithValues: links.map { ($0.buildingId, $0) })
        let addressesById = Dictionary(uniqueKeysWithValues: addresses.map { ($0.id.uuidString, $0) })
        let statsByGersId = Dictionary(uniqueKeysWithValues: stats.map { ($0.gersId, $0) })
        
        // Combine into BuildingWithAddress
        let buildingsWithData: [BuildingWithAddress] = buildings.map { building in
            let gersId = building.id ?? ""
            let link = linksByBuildingId[gersId]
            let address = link.flatMap { addressesById[$0.addressId] }
            let stat = statsByGersId[gersId]
            
            return BuildingWithAddress(
                building: building,
                link: link,
                address: address,
                stats: stat
            )
        }
        
        print("✅ [BuildingLinkService] Loaded \(buildingsWithData.count) buildings with data")
        
        return CampaignBuildingData(
            buildings: buildingsWithData,
            links: links,
            addresses: addresses,
            stats: statsByGersId
        )
    }
    
    // MARK: - Real-time Subscription
    
    /// Subscribe to building stats updates for real-time color changes
    func subscribeToBuildingStats(
        campaignId: String,
        onUpdate: @escaping @Sendable (BuildingStats) -> Void
    ) async throws -> RealtimeChannelV2 {
        let channel = supabaseClient.channel("building-stats-\(campaignId)")

        let updates = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "building_stats",
            filter: .eq("campaign_id", value: campaignId)
        )

        Task {
            for await action in updates {
                let record: [String: AnyJSON]
                switch action {
                case .insert(let insert):
                    record = insert.record
                case .update(let update):
                    record = update.record
                case .delete:
                    continue
                }

                guard let gersId = record["gers_id"]?.stringValue,
                      let status = record["status"]?.stringValue else {
                    continue
                }
                let scansTotal = record["scans_total"]?.intValue
                    ?? Int(record["scans_total"]?.doubleValue ?? 0)
                onUpdate(
                    BuildingStats(
                        gersId: gersId,
                        status: status,
                        scansTotal: scansTotal
                    )
                )
            }
        }

        try await channel.subscribeWithError()
        print("📡 [BuildingLinkService] Subscribed to building stats for campaign: \(campaignId)")

        return channel
    }

    // MARK: - HTTP Helpers

    private func authorizedDataRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        suppressHTTPWarning: Bool = false
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let result = try await URLSession.shared.data(for: request)
        if let httpResponse = result.1 as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode),
           !suppressHTTPWarning {
            print("⚠️ [BuildingLinkService] HTTP \(httpResponse.statusCode) \(method) \(url.absoluteString)")
        }
        return result
    }

    private func ensureSuccessfulResponse(_ response: URLResponse, data: Data, logFailures: Bool = true) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BuildingLinkError.fetchFailed
        }
        let statusCode = httpResponse.statusCode
        guard (200..<300).contains(statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               !apiError.error.isEmpty {
                if logFailures {
                    print("⚠️ [BuildingLinkService] HTTP \(statusCode) API error: \(apiError.error)")
                }
                throw ManualShapeServiceError.api(apiError.error)
            }
            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !responseText.isEmpty {
                let previewLen = 200
                let preview = String(responseText.prefix(previewLen))
                let suffix = responseText.count > previewLen ? "…" : ""
                if logFailures {
                    print("⚠️ [BuildingLinkService] HTTP \(statusCode) body preview: \(preview)\(suffix)")
                }

                if Self.responseBodyLooksLikeHTML(responseText) {
                    throw ManualShapeServiceError.api(
                        "The server returned a web page instead of data (HTTP \(statusCode)). The API may not be deployed yet, or the server URL may be wrong. Try again later or contact support."
                    )
                }

                let maxPlaintext = 400
                if responseText.count > maxPlaintext {
                    let truncated = String(responseText.prefix(maxPlaintext)) + "…"
                    throw ManualShapeServiceError.api("Request failed (HTTP \(statusCode)): \(truncated)")
                }
                throw ManualShapeServiceError.api(responseText)
            }
            throw BuildingLinkError.fetchFailed
        }
    }

    private func deleteBuildingAndAddressesFallback(campaignId: String, buildingId: String) async throws {
        guard (try? await supabaseClient.auth.session) != nil else {
            throw BuildingLinkError.notAuthenticated
        }

        let resolvedBuilding = try await resolveBuildingIdentity(buildingId: buildingId)
        let publicBuildingId = (resolvedBuilding?.gersId?.isEmpty == false ? resolvedBuilding?.gersId : resolvedBuilding?.id) ?? buildingId

        var linkedAddressIds: [String] = []

        if let rowId = resolvedBuilding?.id {
            let links: [RawBuildingAddressLink] = try await supabaseClient
                .from("building_address_links")
                .select("*")
                .eq("campaign_id", value: campaignId)
                .eq("building_id", value: rowId)
                .execute()
                .value

            linkedAddressIds.append(contentsOf: links.map(\.addressId))
        }

        let buildingAddresses: [FallbackAddressRow] = try await supabaseClient
            .from("campaign_addresses")
            .select("id")
            .eq("campaign_id", value: campaignId)
            .eq("building_gers_id", value: publicBuildingId)
            .execute()
            .value

        linkedAddressIds.append(contentsOf: buildingAddresses.map(\.id))
        linkedAddressIds = Array(Set(linkedAddressIds))

        do {
            try await supabaseClient
                .from("campaign_hidden_buildings")
                .upsert(
                    [
                        [
                            "campaign_id": campaignId,
                            "public_building_id": publicBuildingId
                        ]
                    ]
                )
                .execute()
        } catch {
            print("⚠️ [BuildingLinkService] Hidden building fallback skipped: \(error.localizedDescription)")
        }

        if !linkedAddressIds.isEmpty {
            try await supabaseClient
                .from("campaign_addresses")
                .delete()
                .eq("campaign_id", value: campaignId)
                .in("id", values: linkedAddressIds)
                .execute()
        }

        if let rowId = resolvedBuilding?.id {
            _ = try? await supabaseClient
                .from("building_address_links")
                .delete()
                .eq("campaign_id", value: campaignId)
                .eq("building_id", value: rowId)
                .execute()
        }

        _ = try? await supabaseClient
            .from("building_stats")
            .delete()
            .eq("campaign_id", value: campaignId)
            .eq("gers_id", value: publicBuildingId)
            .execute()

        _ = try? await supabaseClient
            .from("building_units")
            .delete()
            .eq("campaign_id", value: campaignId)
            .eq("parent_building_id", value: publicBuildingId)
            .execute()

        if let resolvedBuilding,
           resolvedBuilding.campaignId == campaignId {
            _ = try? await supabaseClient
                .from("buildings")
                .delete()
                .eq("id", value: resolvedBuilding.id)
                .execute()
        }
    }

    private func resolveBuildingIdentity(buildingId: String) async throws -> FallbackBuildingRow? {
        let normalized = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let allBuildings: [FallbackBuildingRow] = try await supabaseClient
            .from("buildings")
            .select("id, gers_id, campaign_id")
            .execute()
            .value

        return allBuildings.first { row in
            row.id.caseInsensitiveCompare(normalized) == .orderedSame ||
            row.gersId?.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    /// True when the body is almost certainly HTML (e.g. Next.js error/404 page) rather than an API JSON error.
    private static func responseBodyLooksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype html") { return true }
        if trimmed.hasPrefix("<html") { return true }
        if text.contains("/_next/static/") { return true }
        return false
    }

    private static func geoJSONDictionary(from geometry: MapFeatureGeoJSONGeometry) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(geometry),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        return object
    }
}

private struct RawBuildingAddressLink: Codable {
    let id: String
    let buildingId: String
    let addressId: String
    let matchType: String
    let confidence: Double
    let isMultiUnit: Bool
    let unitCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case buildingId = "building_id"
        case addressId = "address_id"
        case matchType = "match_type"
        case confidence
        case isMultiUnit = "is_multi_unit"
        case unitCount = "unit_count"
    }
}

private struct BuildingIdentityRow: Codable {
    let id: String
    let gersId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
    }
}

private struct FallbackBuildingRow: Codable {
    let id: String
    let gersId: String?
    let campaignId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
        case campaignId = "campaign_id"
    }
}

private struct FallbackAddressRow: Codable {
    let id: String
}

struct ManualAddressCreateInput {
    let coordinate: CLLocationCoordinate2D
    let formatted: String
    let houseNumber: String?
    let streetName: String?
    let locality: String?
    let region: String?
    let postalCode: String?
    let country: String?
    let buildingId: String?
    let addressProvenance: String?
    let userConfirmed: Bool

    init(
        coordinate: CLLocationCoordinate2D,
        formatted: String,
        houseNumber: String?,
        streetName: String?,
        locality: String?,
        region: String?,
        postalCode: String?,
        country: String?,
        buildingId: String?,
        addressProvenance: String? = nil,
        userConfirmed: Bool = true
    ) {
        self.coordinate = coordinate
        self.formatted = formatted
        self.houseNumber = houseNumber
        self.streetName = streetName
        self.locality = locality
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.buildingId = buildingId
        self.addressProvenance = addressProvenance
        self.userConfirmed = userConfirmed
    }
}

struct ManualBuildingCreateInput {
    let polygon: [CLLocationCoordinate2D]
    let heightMeters: Double
    let unitsCount: Int
    let levels: Int
    let addressIds: [String]
}

struct ManualAddressCreateResponse: Decodable {
    let address: CampaignAddressResponse
    let linkedBuildingId: String?

    enum CodingKeys: String, CodingKey {
        case address
        case linkedBuildingId = "linked_building_id"
    }

    init(address: CampaignAddressResponse, linkedBuildingId: String?) {
        self.address = address
        self.linkedBuildingId = linkedBuildingId
    }
}

struct ManualBuildingCreateResponse: Decodable {
    let building: ManualBuildingResponse
    let linkedAddressIds: [String]

    enum CodingKeys: String, CodingKey {
        case building
        case linkedAddressIds = "linked_address_ids"
    }
}

struct ManualBuildingResponse: Decodable {
    let id: String
    let rowId: String
    let source: String
    let heightMeters: Double?
    let unitsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case rowId = "row_id"
        case source
        case heightMeters = "height_m"
        case unitsCount = "units_count"
    }
}

struct BuildingAddressCandidateResponse: Decodable {
    let buildingId: String
    let radiusMeters: Double
    let trustDecision: AddressCandidateTrustDecision?
    let candidates: [BuildingAddressCandidate]

    enum CodingKeys: String, CodingKey {
        case buildingId = "building_id"
        case radiusMeters = "radius_meters"
        case trustDecision = "trust_decision"
        case candidates
    }
}

struct AddressCandidateTrustDecision: Decodable {
    let usedReverseGeocode: Bool
    let reason: String?
    let nearestCandidateDistanceMeters: Double?
    let nearestCandidateRejectedReason: String?

    enum CodingKeys: String, CodingKey {
        case usedReverseGeocode = "used_reverse_geocode"
        case reason
        case nearestCandidateDistanceMeters = "nearest_candidate_distance_m"
        case nearestCandidateRejectedReason = "nearest_candidate_rejected_reason"
    }
}

struct BuildingAddressCandidate: Identifiable, Decodable {
    let id: UUID
    let candidateType: String
    let isSynthetic: Bool
    let formatted: String?
    let formattedAddress: String?
    let houseNumber: String?
    let streetName: String?
    let street: String?
    let locality: String?
    let region: String?
    let postalCode: String?
    let country: String?
    let source: String?
    let coordinate: CandidateCoordinate
    let distanceMeters: Double
    let score: Double
    let reason: String
    let candidateReason: String?
    let confidenceLabel: String?
    let requiresConfirmation: Bool
    let trusted: Bool?
    let rejectedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case candidateType = "candidate_type"
        case isSynthetic = "is_synthetic"
        case formatted
        case formattedAddress = "formatted_address"
        case houseNumber = "house_number"
        case streetName = "street_name"
        case street
        case locality
        case region
        case postalCode = "postal_code"
        case country
        case source
        case coordinate
        case distanceMeters = "distance_meters"
        case score
        case reason
        case candidateReason = "candidate_reason"
        case confidenceLabel = "confidence_label"
        case requiresConfirmation = "requires_confirmation"
        case trusted
        case rejectedReason = "rejected_reason"
    }

    init(
        id: UUID,
        candidateType: String = "official",
        isSynthetic: Bool = false,
        formatted: String?,
        formattedAddress: String? = nil,
        houseNumber: String?,
        streetName: String?,
        street: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        postalCode: String? = nil,
        country: String? = nil,
        source: String?,
        coordinate: CandidateCoordinate,
        distanceMeters: Double,
        score: Double,
        reason: String,
        candidateReason: String? = nil,
        confidenceLabel: String? = nil,
        requiresConfirmation: Bool,
        trusted: Bool? = nil,
        rejectedReason: String? = nil
    ) {
        self.id = id
        self.candidateType = candidateType
        self.isSynthetic = isSynthetic
        self.formatted = formatted
        self.formattedAddress = formattedAddress
        self.houseNumber = houseNumber
        self.streetName = streetName
        self.street = street
        self.locality = locality
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.source = source
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.score = score
        self.reason = reason
        self.candidateReason = candidateReason
        self.confidenceLabel = confidenceLabel
        self.requiresConfirmation = requiresConfirmation
        self.trusted = trusted
        self.rejectedReason = rejectedReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedCandidateType = (try? container.decodeIfPresent(String.self, forKey: .candidateType)) ?? "official"
        let decodedIsSynthetic = (try? container.decodeIfPresent(Bool.self, forKey: .isSynthetic)) ?? false
        candidateType = decodedCandidateType
        isSynthetic = decodedIsSynthetic
        formatted = try? container.decodeIfPresent(String.self, forKey: .formatted)
        formattedAddress = try? container.decodeIfPresent(String.self, forKey: .formattedAddress)
        houseNumber = try? container.decodeIfPresent(String.self, forKey: .houseNumber)
        streetName = try? container.decodeIfPresent(String.self, forKey: .streetName)
        street = try? container.decodeIfPresent(String.self, forKey: .street)
        locality = try? container.decodeIfPresent(String.self, forKey: .locality)
        region = try? container.decodeIfPresent(String.self, forKey: .region)
        postalCode = try? container.decodeIfPresent(String.self, forKey: .postalCode)
        country = try? container.decodeIfPresent(String.self, forKey: .country)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        coordinate = try container.decode(CandidateCoordinate.self, forKey: .coordinate)
        distanceMeters = (try? container.decodeIfPresent(Double.self, forKey: .distanceMeters)) ?? 0
        score = (try? container.decodeIfPresent(Double.self, forKey: .score)) ?? 0
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? "Suggested address"
        candidateReason = try? container.decodeIfPresent(String.self, forKey: .candidateReason)
        confidenceLabel = try? container.decodeIfPresent(String.self, forKey: .confidenceLabel)
        requiresConfirmation = (try? container.decodeIfPresent(Bool.self, forKey: CodingKeys.requiresConfirmation))
            ?? (decodedCandidateType == "reverse_geocode" || decodedIsSynthetic)
        trusted = try? container.decodeIfPresent(Bool.self, forKey: .trusted)
        rejectedReason = try? container.decodeIfPresent(String.self, forKey: .rejectedReason)
    }

    var isReverseGeocode: Bool {
        candidateType == "reverse_geocode" || isSynthetic
    }

    var displayAddress: String {
        let text = ((isReverseGeocode ? reverseGeocodeStreetLine : nil)
            ?? formattedAddress
            ?? formatted
            ?? "\(houseNumber ?? "") \(streetName ?? street ?? "")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Address" : text
    }

    var resolvedStreetName: String? {
        let value = (streetName ?? street)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    var reverseGeocodeStreetLine: String? {
        let number = Self.cleanedAddressComponent(houseNumber)
        let street = Self.cleanedAddressComponent(resolvedStreetName)
        if let number, let street {
            return Self.streetLine(street, startsWithHouseNumber: number) ? street : "\(number) \(street)"
        }
        if let street {
            return street
        }
        guard let formatted = Self.cleanedAddressComponent(formattedAddress ?? formatted),
              let firstLine = formatted.split(separator: ",", maxSplits: 1).first else {
            return nil
        }
        return Self.cleanedAddressComponent(String(firstLine))
    }

    private static func cleanedAddressComponent(_ value: String?) -> String? {
        let cleaned = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func streetLine(_ street: String, startsWithHouseNumber houseNumber: String) -> Bool {
        street.range(
            of: #"^\#(NSRegularExpression.escapedPattern(for: houseNumber))(\b|\s)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

struct CandidateCoordinate: Decodable {
    let longitude: Double
    let latitude: Double

    enum CodingKeys: String, CodingKey {
        case longitude
        case latitude
        case lng
        case lat
    }

    init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lon = (try? container.decodeIfPresent(Double.self, forKey: .longitude))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .lng))
        let lat = (try? container.decodeIfPresent(Double.self, forKey: .latitude))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .lat))
        guard let lon, let lat else {
            throw DecodingError.keyNotFound(
                CodingKeys.longitude,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Candidate coordinate requires longitude/latitude or lng/lat")
            )
        }
        longitude = lon
        latitude = lat
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct BuildingAddressMutationResponse: Decodable {
    let linkedAddressIds: [UUID]
    let unitCount: Int
    let deleted: Bool?
    let includesLinkedAddressIds: Bool

    enum CodingKeys: String, CodingKey {
        case linkedAddressIds = "linked_address_ids"
        case unitCount = "unit_count"
        case deleted
    }

    init(
        linkedAddressIds: [UUID],
        unitCount: Int? = nil,
        deleted: Bool? = nil,
        includesLinkedAddressIds: Bool = true
    ) {
        self.linkedAddressIds = linkedAddressIds
        self.unitCount = unitCount ?? linkedAddressIds.count
        self.deleted = deleted
        self.includesLinkedAddressIds = includesLinkedAddressIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includesLinkedAddressIds = container.contains(.linkedAddressIds)
        linkedAddressIds = (try? container.decodeIfPresent([UUID].self, forKey: .linkedAddressIds)) ?? []
        unitCount = (try? container.decodeIfPresent(Int.self, forKey: .unitCount)) ?? max(linkedAddressIds.count, 0)
        deleted = try? container.decodeIfPresent(Bool.self, forKey: .deleted)
    }
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum ManualShapeServiceError: LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message):
            return message
        }
    }
}

// MARK: - Supporting Types

enum BuildingLinkError: LocalizedError {
    case invalidURL
    case fetchFailed
    case decodingFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The app couldn't build the request URL."
        case .fetchFailed:
            return "The request couldn't be completed."
        case .decodingFailed:
            return "The server response couldn't be read."
        case .notAuthenticated:
            return "You need to sign in again before making this change."
        }
    }
}
