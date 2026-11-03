import Foundation
import CoreLocation

struct ClientBuildingAddressLink: Codable, Equatable, Sendable {
    let id: String
    let buildingId: String
    let addressId: String
    let matchType: String
    let confidence: Double
    let distanceMeters: Double

    enum CodingKeys: String, CodingKey {
        case id
        case buildingId
        case addressId
        case matchType
        case confidence
        case distanceMeters
    }

    enum SnakeCodingKeys: String, CodingKey {
        case id
        case buildingId = "building_id"
        case addressId = "address_id"
        case matchType = "match_type"
        case confidence
        case distanceMeters = "distance_meters"
    }

    init(
        id: String,
        buildingId: String,
        addressId: String,
        matchType: String,
        confidence: Double,
        distanceMeters: Double
    ) {
        self.id = id
        self.buildingId = buildingId
        self.addressId = addressId
        self.matchType = matchType
        self.confidence = confidence
        self.distanceMeters = distanceMeters
    }

    init(from decoder: Decoder) throws {
        if let snake = try? decoder.container(keyedBy: SnakeCodingKeys.self),
           let buildingId = try? snake.decode(String.self, forKey: .buildingId),
           let addressId = try? snake.decode(String.self, forKey: .addressId) {
            self.id = (try? snake.decode(String.self, forKey: .id))
                ?? "\(buildingId.lowercased()):\(addressId.lowercased())"
            self.buildingId = buildingId
            self.addressId = addressId
            self.matchType = (try? snake.decode(String.self, forKey: .matchType)) ?? "auto"
            self.confidence = (try? snake.decode(Double.self, forKey: .confidence)) ?? 0.5
            self.distanceMeters = (try? snake.decode(Double.self, forKey: .distanceMeters)) ?? 0
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        buildingId = try container.decode(String.self, forKey: .buildingId)
        addressId = try container.decode(String.self, forKey: .addressId)
        matchType = (try? container.decode(String.self, forKey: .matchType)) ?? "auto"
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0.5
        distanceMeters = (try? container.decode(Double.self, forKey: .distanceMeters)) ?? 0
    }
}

struct ClientLinkingProgress: Equatable, Sendable {
    let processed: Int
    let total: Int
    let linked: Int

    var percent: Int {
        guard total > 0 else { return 100 }
        return min(100, max(0, Int((Double(processed) / Double(total) * 100).rounded())))
    }

    var isOptimizing: Bool {
        total > 0 && processed < total
    }

    static let idle = ClientLinkingProgress(processed: 0, total: 0, linked: 0)
}

struct ClientLinkingSummary: Equatable, Sendable {
    let links: [ClientBuildingAddressLink]
    let progress: ClientLinkingProgress
}

final class ClientMapLinkerService: Sendable {
    static let shared = ClientMapLinkerService()

    private let containmentConfidence = 1.0
    private let parcelConfidence = 0.95
    private let proximityConfidence = 0.80
    private let fallbackConfidence = 0.50
    // Keep offline semantic linking aligned with the server's detached-neighbourhood
    // policy. Candidate discovery stays broad for authoritative parcel evidence.
    private let proximityRadiusMeters = 10.0
    private let fallbackRadiusMeters = 75.0
    private let minimumSemanticProximityScore = 0.65

    private init() {}

    func link(
        buildings: BuildingFeatureCollection,
        addresses: AddressFeatureCollection,
        parcels: ParcelFeatureCollection?,
        progress: ((ClientLinkingProgress) async -> Void)? = nil
    ) async -> ClientLinkingSummary {
        let preparedBuildings = buildings.features.compactMap(PreparedBuilding.init(feature:))
        let preparedParcels = (parcels?.features ?? []).compactMap(PreparedParcel.init(feature:))
        let preparedAddresses = addresses.features.compactMap(PreparedAddress.init(feature:))
        let total = preparedAddresses.count
        guard total > 0, !preparedBuildings.isEmpty else {
            let done = ClientLinkingProgress(processed: total, total: total, linked: 0)
            await progress?(done)
            return ClientLinkingSummary(links: [], progress: done)
        }

        var links: [ClientBuildingAddressLink] = []
        let prelinkedBuildingIds = Set(
            preparedAddresses
                .compactMap(\.existingBuildingId)
                .map { $0.lowercased() }
        )
        let claimedSingleUnitBuildingIds = Set(
            preparedBuildings
                .filter { $0.hasExistingAssignments || !$0.identifierCandidates.isDisjoint(with: prelinkedBuildingIds) }
                .flatMap(\.identifierCandidates)
        )
        let prelinkedCount = preparedAddresses.filter { $0.existingBuildingId != nil }.count
        await progress?(ClientLinkingProgress(processed: 0, total: total, linked: prelinkedCount))
        // Propose before claiming: iteration order must not choose a winner or
        // redirect a losing address onto a neighboring home.
        let proposals: [(PreparedAddress, MatchCandidate)] = preparedAddresses.compactMap { address in
            guard !Task.isCancelled, address.existingBuildingId == nil, !address.hasCanonicalPlacement,
                let match = bestMatch(for: address, buildings: preparedBuildings,
                    parcels: preparedParcels,
                    allAddresses: preparedAddresses) else { return nil }
            return (address, match)
        }
        let claims = Dictionary(grouping: proposals, by: { $0.1.building.id.lowercased() })
        var accepted: [String: MatchCandidate] = [:]
        for group in claims.values {
            guard let first = group.first,
                first.1.building.identifierCandidates.isDisjoint(with: claimedSingleUnitBuildingIds) else { continue }
            func tier(_ match: MatchCandidate) -> Int {
                match.matchType.hasPrefix("containment") ? 0 : match.matchType == "parcel_verified" ? 1 : 2
            }
            let bestTier = group.map { tier($0.1) }.min() ?? 2
            let strongest = group.filter { tier($0.1) == bestTier }
            if strongest.count == 1 { accepted[strongest[0].0.id] = strongest[0].1 }
        }
        var processed = 0

        for address in preparedAddresses {
            if Task.isCancelled { break }
            if let match = accepted[address.id] {
                links.append(ClientBuildingAddressLink(
                    id: "\(match.building.id.lowercased()):\(address.id.lowercased())",
                    buildingId: match.building.id,
                    addressId: address.id,
                    matchType: match.matchType,
                    confidence: match.confidence,
                    distanceMeters: match.distance
                ))
            }
            processed += 1
            if processed == total || processed % 25 == 0 {
                await progress?(ClientLinkingProgress(processed: processed, total: total, linked: prelinkedCount + links.count))
            }
        }

        let finalProgress = ClientLinkingProgress(processed: processed, total: total, linked: prelinkedCount + links.count)
        await progress?(finalProgress)
        return ClientLinkingSummary(links: links, progress: finalProgress)
    }

    private func bestMatch(
        for address: PreparedAddress,
        buildings: [PreparedBuilding],
        parcels: [PreparedParcel],
        allAddresses: [PreparedAddress]
    ) -> MatchCandidate? {
        let nearby = buildings
            .filter { $0.expandedBbox(meters: fallbackRadiusMeters).contains(address.coordinate) }
            .map { building in
                MatchCandidate(
                    building: building,
                    matchType: "proximity_fallback",
                    confidence: fallbackConfidence,
                    distance: distanceMeters(address.coordinate, building.centroid),
                    streetScore: streetScore(address: address, building: building)
                )
            }
            .filter { $0.distance <= fallbackRadiusMeters }

        guard !nearby.isEmpty else { return nil }

        let contained = nearby
            .filter({ $0.building.contains(address.coordinate) })
            .map({ candidate in
                candidate.with(
                    matchType: candidate.streetScore >= 0.40 ? "containment_verified" : "containment_suspect",
                    confidence: candidate.streetScore >= 0.40 ? containmentConfidence : 0.70
                )
            })
            .sorted(by: rankedBefore)
        if !contained.isEmpty { return contained.count == 1 ? contained[0] : nil }

        if let parcelMatch = parcelBridgeMatch(for: address, nearby: nearby, parcels: parcels, buildings: buildings, allAddresses: allAddresses) {
            return parcelMatch
        }

        // A shared/ambiguous parcel cannot be retried as a distance-only match.
        let owners = parcels.filter { $0.contains(address.coordinate) }
        if owners.count > 1 { return nil }
        if let owner = owners.first {
            if allAddresses.filter({ owner.contains($0.coordinate) }).count != 1 ||
                buildings.filter({ $0.intersects(owner.bbox) }).count != 1 { return nil }
        }
        let semantic = nearby
            .filter({ $0.distance <= proximityRadiusMeters && $0.streetScore >= minimumSemanticProximityScore && !hasStreetConflict(address, $0.building) })
            .map({ $0.with(matchType: "proximity_verified", confidence: proximityConfidence) })
            .sorted(by: rankedBefore)
        if semantic.count == 1 { return semantic[0] }

        return nil
    }

    private func parcelBridgeMatch(
        for address: PreparedAddress,
        nearby: [MatchCandidate],
        parcels: [PreparedParcel],
        buildings: [PreparedBuilding],
        allAddresses: [PreparedAddress]
    ) -> MatchCandidate? {
        let owners = parcels.filter { $0.contains(address.coordinate) }
        guard owners.count == 1, let parcel = owners.first,
            allAddresses.filter({ parcel.contains($0.coordinate) }).count == 1,
            buildings.filter({ $0.intersects(parcel.bbox) }).count == 1 else { return nil }
        let candidates = nearby.filter { parcel.contains($0.building.centroid) }
        guard candidates.count == 1, !hasStreetConflict(address, candidates[0].building) else { return nil }
        return candidates[0].with(matchType: "parcel_verified", confidence: parcelConfidence)
    }

    private func hasStreetConflict(_ address: PreparedAddress, _ building: PreparedBuilding) -> Bool {
        let a = normalizeStreet(address.streetName ?? "")
        let b = normalizeStreet(building.streetName ?? "")
        return !a.isEmpty && !b.isEmpty && a != b
    }

    private func rankedBefore(_ lhs: MatchCandidate, _ rhs: MatchCandidate) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.streetScore != rhs.streetScore { return lhs.streetScore > rhs.streetScore }
        return lhs.distance < rhs.distance
    }

    private func streetScore(address: PreparedAddress, building: PreparedBuilding) -> Double {
        let addressStreet = normalizeStreet(address.streetName ?? address.formatted)
        let buildingStreet = normalizeStreet(building.streetName ?? building.addressText)
        var score = 0.0
        if !addressStreet.isEmpty, !buildingStreet.isEmpty {
            if addressStreet == buildingStreet {
                score += 0.65
            } else if addressStreet.contains(buildingStreet) || buildingStreet.contains(addressStreet) {
                score += 0.45
            }
        }
        if let house = address.houseNumber, !house.isEmpty {
            let buildingHouse = building.houseNumber ?? building.addressText ?? ""
            if normalizeHouseNumber(buildingHouse) == normalizeHouseNumber(house) {
                score += 0.35
            }
        }
        return min(score, 1.0)
    }

    private func normalizeStreet(_ value: String?) -> String {
        if let identity = AddressMatcher.identity(houseNumber: nil, streetName: nil, formatted: value),
           let street = identity.split(separator: "|").dropFirst().first {
            return String(street)
        }
        return AddressMatcher.streetKey(value) ?? ""
    }

    private func normalizeHouseNumber(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func distanceMeters(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}

private struct MatchCandidate {
    let building: PreparedBuilding
    let matchType: String
    let confidence: Double
    let distance: Double
    let streetScore: Double

    func with(matchType: String, confidence: Double) -> MatchCandidate {
        MatchCandidate(
            building: building,
            matchType: matchType,
            confidence: confidence,
            distance: distance,
            streetScore: streetScore
        )
    }
}

private struct PreparedAddress {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let formatted: String?
    let houseNumber: String?
    let streetName: String?
    let existingBuildingId: String?
    let hasCanonicalPlacement: Bool

    init?(feature: AddressFeature) {
        // A canonical parcel placement is already resolved by the server.
        // Do not reinterpret its display point as new address/building evidence.
        guard let id = feature.properties.id ?? feature.id,
              let point = feature.geometry.asPoint,
              point.count >= 2 else { return nil }
        self.id = id
        let source = (feature.properties.source ?? "").lowercased()
        hasCanonicalPlacement = feature.properties.pinPlacement != nil || source.contains("manual") || source.hasPrefix("field_")
        coordinate = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        formatted = feature.properties.formatted
        houseNumber = feature.properties.houseNumber
        streetName = feature.properties.streetName
        let existing = (feature.properties.buildingGersId ?? feature.properties.linkedBuildingId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        existingBuildingId = existing?.isEmpty == false ? existing : nil
    }
}

private struct PreparedBuilding {
    let id: String
    let identifierCandidates: Set<String>
    let hasExistingAssignments: Bool
    let rings: [[CLLocationCoordinate2D]]
    let bbox: CoordinateBbox
    let centroid: CLLocationCoordinate2D
    let streetName: String?
    let houseNumber: String?
    let addressText: String?

    init?(feature: BuildingFeature) {
        let buildingType = (feature.properties.buildingType ?? "").lowercased()
        guard !["garage", "shed", "carport", "outbuilding", "accessory", "auxiliary"]
            .contains(where: buildingType.contains),
              let id = feature.properties.canonicalBuildingIdentifier ?? feature.id else { return nil }
        let rings = Self.rings(from: feature.geometry)
        guard !rings.isEmpty else { return nil }
        self.id = id
        hasExistingAssignments = feature.properties.addressId != nil || !feature.properties.addressIds.isEmpty
        identifierCandidates = Set(([id] + feature.properties.buildingIdentifierCandidates).map { $0.lowercased() })
        self.rings = rings
        bbox = CoordinateBbox(coordinates: rings.flatMap { $0 })
        centroid = Self.centroid(for: rings[0]) ?? bbox.center
        streetName = feature.properties.streetName
        houseNumber = feature.properties.houseNumber
        addressText = feature.properties.addressText

    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard bbox.contains(coordinate) else { return false }
        return rings.contains { ringContains(coordinate, ring: $0) }
    }

    func intersects(_ other: CoordinateBbox) -> Bool {
        bbox.intersects(other)
    }

    func expandedBbox(meters: Double) -> CoordinateBbox {
        bbox.expanded(meters: meters)
    }

    private static func rings(from geometry: MapFeatureGeoJSONGeometry) -> [[CLLocationCoordinate2D]] {
        if let polygon = geometry.asPolygon {
            return polygon.map(Self.coordinates)
        }
        if let multi = geometry.asMultiPolygon {
            return multi.flatMap { $0.map(Self.coordinates) }
        }
        return []
    }

    private static func coordinates(_ ring: [[Double]]) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    private static func centroid(for ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        let usable = ring.dropLast()
        guard !usable.isEmpty else { return nil }
        let lat = usable.reduce(0) { $0 + $1.latitude } / Double(usable.count)
        let lon = usable.reduce(0) { $0 + $1.longitude } / Double(usable.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private struct PreparedParcel {
    let rings: [[CLLocationCoordinate2D]]
    let bbox: CoordinateBbox

    init?(feature: ParcelFeature) {
        let rings: [[CLLocationCoordinate2D]]
        if let polygon = feature.geometry.asPolygon {
            rings = polygon.map(Self.coordinates)
        } else if let multi = feature.geometry.asMultiPolygon {
            rings = multi.flatMap { $0.map(Self.coordinates) }
        } else {
            return nil
        }
        guard !rings.isEmpty else { return nil }
        self.rings = rings
        bbox = CoordinateBbox(coordinates: rings.flatMap { $0 })
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard bbox.contains(coordinate) else { return false }
        return rings.contains { ringContains(coordinate, ring: $0) }
    }

    private static func coordinates(_ ring: [[Double]]) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }
}

private struct CoordinateBbox {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    init(coordinates: [CLLocationCoordinate2D]) {
        minLon = coordinates.map(\.longitude).min() ?? 0
        minLat = coordinates.map(\.latitude).min() ?? 0
        maxLon = coordinates.map(\.longitude).max() ?? 0
        maxLat = coordinates.map(\.latitude).max() ?? 0
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude >= minLon &&
            coordinate.longitude <= maxLon &&
            coordinate.latitude >= minLat &&
            coordinate.latitude <= maxLat
    }

    func intersects(_ other: CoordinateBbox) -> Bool {
        !(other.minLon > maxLon || other.maxLon < minLon || other.minLat > maxLat || other.maxLat < minLat)
    }

    func expanded(meters: Double) -> CoordinateBbox {
        let latDelta = meters / 111_320.0
        let lonDelta = meters / max(cos(center.latitude * .pi / 180) * 111_320.0, 0.0001)
        return CoordinateBbox(
            minLon: minLon - lonDelta,
            minLat: minLat - latDelta,
            maxLon: maxLon + lonDelta,
            maxLat: maxLat + latDelta
        )
    }

    private init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }
}

private func ringContains(_ coordinate: CLLocationCoordinate2D, ring: [CLLocationCoordinate2D]) -> Bool {
    guard ring.count >= 3 else { return false }
    var inside = false
    var j = ring.count - 1
    for i in 0..<ring.count {
        let yi = ring[i].latitude
        let yj = ring[j].latitude
        let xi = ring[i].longitude
        let xj = ring[j].longitude
        if ((yi > coordinate.latitude) != (yj > coordinate.latitude)) &&
            (coordinate.longitude < (xj - xi) * (coordinate.latitude - yi) / (yj - yi) + xi) {
            inside.toggle()
        }
        j = i
    }
    return inside
}
