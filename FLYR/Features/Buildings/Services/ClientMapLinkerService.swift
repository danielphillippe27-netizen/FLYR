import Foundation
import CoreLocation

struct ClientBuildingAddressLink: Codable, Equatable, Sendable {
    let id: String
    let buildingId: String
    let addressId: String
    let matchType: String
    let confidence: Double
    let distanceMeters: Double
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
    private let proximityRadiusMeters = 75.0
    private let fallbackRadiusMeters = 125.0

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
        let prelinkedCount = preparedAddresses.filter { $0.existingBuildingId != nil }.count
        var processed = 0
        await progress?(ClientLinkingProgress(processed: 0, total: total, linked: prelinkedCount))

        for address in preparedAddresses {
            if Task.isCancelled { break }
            if address.existingBuildingId == nil,
               let match = bestMatch(for: address, buildings: preparedBuildings, parcels: preparedParcels) {
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
        parcels: [PreparedParcel]
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

        if let contained = nearby
            .filter({ $0.building.contains(address.coordinate) })
            .map({ candidate in
                candidate.with(
                    matchType: candidate.streetScore >= 0.40 ? "containment_verified" : "containment_suspect",
                    confidence: candidate.streetScore >= 0.40 ? containmentConfidence : 0.70
                )
            })
            .sorted(by: rankedBefore)
            .first {
            return contained
        }

        if let parcelMatch = parcelBridgeMatch(for: address, nearby: nearby, parcels: parcels) {
            return parcelMatch
        }

        if let semantic = nearby
            .filter({ $0.distance <= proximityRadiusMeters && $0.streetScore >= 0.40 })
            .map({ $0.with(matchType: "proximity_verified", confidence: proximityConfidence) })
            .sorted(by: rankedBefore)
            .first {
            return semantic
        }

        return nearby
            .map { candidate in
                candidate.with(
                    matchType: "proximity_fallback",
                    confidence: max(0.35, fallbackConfidence - min(candidate.distance / 500.0, 0.20))
                )
            }
            .sorted(by: rankedBefore)
            .first
    }

    private func parcelBridgeMatch(
        for address: PreparedAddress,
        nearby: [MatchCandidate],
        parcels: [PreparedParcel]
    ) -> MatchCandidate? {
        guard let parcel = parcels.first(where: { $0.contains(address.coordinate) }) else { return nil }
        return nearby
            .filter { parcel.contains($0.building.centroid) || $0.building.intersects(parcel.bbox) }
            .map { $0.with(matchType: "parcel_verified", confidence: parcelConfidence) }
            .sorted(by: rankedBefore)
            .first
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
        let raw = (value ?? "").lowercased()
        let replacements = [
            " street": " st",
            " avenue": " ave",
            " road": " rd",
            " drive": " dr",
            " crescent": " cres",
            " boulevard": " blvd",
            ".": "",
            ",": ""
        ]
        return replacements.reduce(raw) { partial, entry in
            partial.replacingOccurrences(of: entry.key, with: entry.value)
        }
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty && Int($0) == nil }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
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

    init?(feature: AddressFeature) {
        guard let id = feature.properties.id ?? feature.id,
              let point = feature.geometry.asPoint,
              point.count >= 2 else { return nil }
        self.id = id
        coordinate = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        formatted = feature.properties.formatted
        houseNumber = feature.properties.houseNumber
        streetName = feature.properties.streetName
        let existing = feature.properties.buildingGersId?.trimmingCharacters(in: .whitespacesAndNewlines)
        existingBuildingId = existing?.isEmpty == false ? existing : nil
    }
}

private struct PreparedBuilding {
    let id: String
    let rings: [[CLLocationCoordinate2D]]
    let bbox: CoordinateBbox
    let centroid: CLLocationCoordinate2D
    let streetName: String?
    let houseNumber: String?
    let addressText: String?

    init?(feature: BuildingFeature) {
        guard let id = feature.properties.canonicalBuildingIdentifier ?? feature.id else { return nil }
        let rings = Self.rings(from: feature.geometry)
        guard !rings.isEmpty else { return nil }
        self.id = id
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
