import Foundation
import UIKit
import CoreLocation
import MapboxMaps
import Combine

/// A suggestion belongs to source geometry, never to the geocoder's returned point.
struct FarmLiveAddressTarget {
    let id: String
    let parcelId: String?
    let buildingId: String?
    let geometry: MapFeatureGeoJSONGeometry
    let coordinate: CLLocationCoordinate2D
    let lookupCoordinate: CLLocationCoordinate2D?
    let showsTemporaryPin: Bool

    init(id: String, parcelId: String?, buildingId: String?, geometry: MapFeatureGeoJSONGeometry,
         coordinate: CLLocationCoordinate2D, lookupCoordinate: CLLocationCoordinate2D? = nil,
         showsTemporaryPin: Bool = true) {
        self.id = id
        self.parcelId = parcelId
        self.buildingId = buildingId
        self.geometry = geometry
        self.coordinate = coordinate
        self.lookupCoordinate = lookupCoordinate
        self.showsTemporaryPin = showsTemporaryPin
    }
}

/// Camera positions are presentation state, not new matching evidence.
enum FarmLiveMatchWork {
    static func key(sourceRevision: String, completionRevision: Int, candidateIDs: [String], readyIDs: Set<String>) -> String {
        sourceRevision + "|" + String(completionRevision) + "|" + candidateIDs.sorted().joined(separator: ",") + "|" + readyIDs.sorted().joined(separator: ",")
    }

    static func preparationBounds(viewport: [Double]) -> [Double] {
        guard viewport.count == 4 else { return viewport }
        let x = max(0.00015, (viewport[2] - viewport[0]) * 0.25)
        let y = max(0.00015, (viewport[3] - viewport[1]) * 0.25)
        return [viewport[0] - x, viewport[1] - y, viewport[2] + x, viewport[3] + y]
    }
}

enum FarmLiveAddressNumberMatcher {
    static func readyTargets(_ completed: [FarmLiveAddressTarget], pending: [FarmLiveAddressTarget]) -> Set<String> {
        // Geometry validation already associates each result with its property.
        // Only a shared roof needs its sibling results to disambiguate house numbers.
        Set(completed.filter { target in
            !pending.contains { other in
                target.id != other.id && target.buildingId != nil &&
                target.buildingId?.lowercased() == other.buildingId?.lowercased()
            }
        }.map(\.id))
    }

    static func normalized(_ number: String?) -> String? {
        guard let value = number?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !value.isEmpty else { return nil }
        return value
    }

    static func uniquePairs(targets: [(String, String?)], addresses: [(UUID, String?)]) -> [(String, UUID)] {
        let targetGroups = Dictionary(grouping: targets.compactMap { id, identity in
            identity.map { ($0, id) }
        }, by: { $0.0 })
        let addressGroups = Dictionary(grouping: addresses.compactMap { id, identity in
            identity.map { ($0, id) }
        }, by: { $0.0 })
        return targetGroups.compactMap { key, targetGroup in
            guard targetGroup.count == 1, let addressGroup = addressGroups[key], addressGroup.count == 1 else { return nil }
            return (targetGroup[0].1, addressGroup[0].1)
        }
    }

}

enum FarmLiveAddressGeometry {
    static func intersects(_ geometry: MapFeatureGeoJSONGeometry, bounds: [Double]) -> Bool {
        guard bounds.count == 4 else { return false }
        let rings = geometry.asPolygon ?? geometry.asMultiPolygon?.flatMap { $0 } ?? []
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for ring in rings { for point in ring where point.count >= 2 {
            minX = min(minX, point[0]); minY = min(minY, point[1])
            maxX = max(maxX, point[0]); maxY = max(maxY, point[1])
        } }
        return minX <= bounds[2] && maxX >= bounds[0] && minY <= bounds[3] && maxY >= bounds[1]
    }

    /// Decode a polygon once for all bounds, containment and anchor calculations.
    struct PreparedShape {
        let native: CanonicalWKBGeometry
        let polygons: [[[[Double]]]]
        let bounds: [Double]

        init?(_ geometry: MapFeatureGeoJSONGeometry) {
            guard let native = geometry.nativeGeometry else { return nil }
            self.native = native
            switch native {
            case .polygon(let rings): polygons = [rings]
            case .multiPolygon(let children):
                polygons = children.compactMap { child in
                    if case .polygon(let rings) = child { return rings }
                    return nil
                }
            default: return nil
            }
            var minX = Double.infinity, minY = Double.infinity
            var maxX = -Double.infinity, maxY = -Double.infinity
            for polygon in polygons { for ring in polygon { for point in ring where point.count >= 2 {
                minX = min(minX, point[0]); minY = min(minY, point[1])
                maxX = max(maxX, point[0]); maxY = max(maxY, point[1])
            } } }
            guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
            bounds = [minX, minY, maxX, maxY]
        }

        func contains(_ point: CLLocationCoordinate2D) -> Bool {
            point.longitude >= bounds[0] && point.longitude <= bounds[2] &&
            point.latitude >= bounds[1] && point.latitude <= bounds[3] &&
            CanonicalParcelFieldGeometry.contains([point.longitude, point.latitude], in: native)
        }

        /// Local metre projection, used only within a small property neighbourhood.
        func distance(to point: CLLocationCoordinate2D) -> Double {
            if contains(point) { return 0 }
            let scaleX = 111_320 * cos(point.latitude * .pi / 180)
            var best = Double.infinity
            for polygon in polygons { for ring in polygon {
                for (a, b) in zip(ring, ring.dropFirst()) where a.count >= 2 && b.count >= 2 {
                    let ax = (a[0] - point.longitude) * scaleX
                    let ay = (a[1] - point.latitude) * 111_320
                    let dx = (b[0] - a[0]) * scaleX
                    let dy = (b[1] - a[1]) * 111_320
                    let length = dx * dx + dy * dy
                    let t = length > 0 ? min(1, max(0, -(ax * dx + ay * dy) / length)) : 0
                    best = min(best, hypot(ax + t * dx, ay + t * dy))
                }
            } }
            return best
        }

        var interiorPoint: CLLocationCoordinate2D? {
            if let outer = polygons.first?.first, outer.count > 1 {
                let points = outer.dropLast().filter { $0.count >= 2 }
                if !points.isEmpty {
                    let center = CLLocationCoordinate2D(latitude: points.reduce(0) { $0 + $1[1] } / Double(points.count),
                        longitude: points.reduce(0) { $0 + $1[0] } / Double(points.count))
                    if contains(center) { return center }
                }
            }
            // Scan lines handle concave footprints and holes without changing the polygon.
            for rings in polygons {
                guard let outer = rings.first, outer.count >= 4 else { continue }
                let ys = outer.compactMap { $0.count >= 2 ? $0[1] : nil }.sorted()
                for (a, b) in zip(ys, ys.dropFirst()) where b > a {
                    let y = (a + b) / 2
                    var xs: [Double] = []
                    for ring in rings {
                        for (p, q) in zip(ring, ring.dropFirst()) where p.count >= 2 && q.count >= 2 {
                            if (p[1] > y) != (q[1] > y) { xs.append(p[0] + (y - p[1]) * (q[0] - p[0]) / (q[1] - p[1])) }
                        }
                    }
                    xs.sort()
                    for index in stride(from: 0, to: max(0, xs.count - 1), by: 2) {
                        let point = CLLocationCoordinate2D(latitude: y, longitude: (xs[index] + xs[index + 1]) / 2)
                        if contains(point) { return point }
                    }
                }
            }
            return nil
        }
    }

    static func interiorPoint(_ geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        PreparedShape(geometry)?.interiorPoint
    }

    static func covers(_ preparedBounds: [Double], viewport: [Double]) -> Bool {
        guard preparedBounds.count == 4, viewport.count == 4 else { return false }
        return preparedBounds[0] <= viewport[0] && preparedBounds[1] <= viewport[1] &&
            preparedBounds[2] >= viewport[2] && preparedBounds[3] >= viewport[3]
    }

    static func eligibleBuilding(_ building: BuildingFeature) -> Bool {
        let p = building.properties
        let excluded = ["garage", "shed", "barn", "storage", "commercial", "industrial", "warehouse", "school", "church", "utility"]
        let type = (p.buildingType ?? "").lowercased()
        return !(p.areaSqm.map { $0 < 30 } ?? false) && !excluded.contains(where: type.contains)
            && !["address_proxy", "field_manual_pin", "manual_pin"].contains(p.source ?? "")
    }

    static func candidate(data: Data, target: FarmLiveAddressTarget, association: FarmLiveAddressAssociation? = nil) throws -> BuildingAddressCandidate? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let feature = response.features.first else {
            PerfTrace.event("farm_live", "suggestion_rejected_no_result")
            return nil
        }
        guard let number = feature.properties.context?.address?.addressNumber, !number.isEmpty,
              let street = feature.properties.context?.address?.streetName, !street.isEmpty else {
            PerfTrace.event("farm_live", "suggestion_rejected_missing_civic_address")
            return nil
        }
        guard ["rooftop", "parcel", "point"].contains(feature.properties.coordinates?.accuracy ?? ""),
              feature.geometry.coordinates.count >= 2 else {
            PerfTrace.event("farm_live", "suggestion_rejected_accuracy")
            return nil
        }
        let point = CLLocationCoordinate2D(latitude: feature.geometry.coordinates[1], longitude: feature.geometry.coordinates[0])
        let inside = CampaignMapEditPlanner.contains(target.geometry, point)
        guard inside || association?.uniquelyAssociates(point, with: target) == true else {
            PerfTrace.event("farm_live", "suggestion_rejected_outside_property")
            return nil
        }
        PerfTrace.event("farm_live", inside ? "suggestion_accepted" : "suggestion_accepted_street_point")
        let p = feature.properties
        return BuildingAddressCandidate(
            id: UUID(), candidateType: "reverse_geocode", isSynthetic: true,
            formatted: "\(number) \(street)", houseNumber: number, streetName: street,
            locality: p.context?.place?.name, region: p.context?.region?.regionCode,
            postalCode: p.context?.postcode?.name, country: p.context?.country?.countryCode,
            source: "mapbox_temporary", coordinate: CandidateCoordinate(longitude: target.coordinate.longitude, latitude: target.coordinate.latitude),
            distanceMeters: 0, score: p.coordinates?.accuracy == "point" ? 0.6 : 0.9, reason: "Suggested address · confirm before saving",
            confidenceLabel: "suggested", requiresConfirmation: true)
    }

    private struct Response: Decodable {
        let features: [Feature]
        struct Feature: Decodable {
            let geometry: Geometry
            let properties: Properties
        }
        struct Geometry: Decodable { let coordinates: [Double] }
        struct Properties: Decodable { let context: Context?; let coordinates: Accuracy? }
        struct Accuracy: Decodable { let accuracy: String? }
        struct Context: Decodable {
            let address: Address?; let place: Part?; let region: Part?; let postcode: Part?; let country: Part?
        }
        struct Address: Decodable {
            let addressNumber: String?; let streetName: String?
            enum CodingKeys: String, CodingKey { case addressNumber = "address_number", streetName = "street_name" }
        }
        struct Part: Decodable {
            let name: String?; let regionCode: String?; let countryCode: String?
            enum CodingKeys: String, CodingKey { case name, regionCode = "region_code", countryCode = "country_code" }
        }
    }

}

enum FarmLiveSuggestionDisplay {
    static func uniqueIDs(_ candidates: [(String, BuildingAddressCandidate)]) -> [String] {
        var groups: [String: [(String, BuildingAddressCandidate)]] = [:]
        var kept: [String] = []
        for (id, candidate) in candidates.sorted(by: { $0.0 < $1.0 }) {
            guard let identity = UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: candidate.houseNumber, streetName: candidate.resolvedStreetName,
                postalCode: candidate.postalCode, formatted: candidate.displayAddress) else {
                kept.append(id); continue
            }
            let duplicate = (groups[identity] ?? []).contains { _, other in
                UnlinkedHomeAddressResolver.addressesMatch(
                    reverseHouseNumber: candidate.houseNumber, reverseStreetName: candidate.resolvedStreetName,
                    reversePostalCode: candidate.postalCode, reverseFormatted: candidate.displayAddress,
                    candidateHouseNumber: other.houseNumber, candidateStreetName: other.resolvedStreetName,
                    candidatePostalCode: other.postalCode, candidateFormatted: other.displayAddress)
            }
            if !duplicate { groups[identity, default: []].append((id, candidate)); kept.append(id) }
        }
        return kept
    }
}

enum FarmLiveStreetAliasVerifier {
    static func verifiedRoadName(data: Data, candidateStreet: String?) throws -> String? {
        struct Response: Decodable {
            struct Feature: Decodable {
                struct Properties: Decodable {
                    struct Query: Decodable { let distance: Double }
                    let name: String?
                    let tilequery: Query
                }
                let properties: Properties
            }
            let features: [Feature]
        }
        var roads: [String: (name: String, distance: Double)] = [:]
        for feature in try JSONDecoder().decode(Response.self, from: data).features {
            let p = feature.properties
            guard p.tilequery.distance.isFinite, p.tilequery.distance >= 0,
                  let name = p.name, let identity = UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                    houseNumber: "1", streetName: name) else { continue }
            if p.tilequery.distance < (roads[identity]?.distance ?? .infinity) { roads[identity] = (name, p.tilequery.distance) }
        }
        let ranked = roads.sorted { $0.value.distance < $1.value.distance }
        guard let nearest = ranked.first, nearest.value.distance <= 12,
              ranked.count == 1 || ranked[1].value.distance - nearest.value.distance >= 5,
              nearest.key == UnlinkedHomeAddressResolver.normalizedAddressIdentity(houseNumber: "1", streetName: candidateStreet)
        else { return nil }
        return nearest.value.name
    }

    /// Temporary road context is held only in the open map's memory. We retain
    /// the native source's civic fields when saving a geometry correction.
    static func verify(_ check: FarmLiveMatchIndex.StreetAliasCheck) async throws -> String? {
        let point = check.entry.coordinate
        var components = URLComponents(string: "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/\(point.longitude),\(point.latitude).json")!
        components.queryItems = [
            .init(name: "radius", value: "25"), .init(name: "limit", value: "10"),
            .init(name: "dedupe", value: "true"), .init(name: "geometry", value: "linestring"),
            .init(name: "layers", value: "road"), .init(name: "access_token", value: Config.mapboxAccessToken)
        ]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try verifiedRoadName(data: data, candidateStreet: check.candidate.resolvedStreetName)
    }
}

/// Owned by a single open map. No database, outbox, disk cache or permanent requests.
@MainActor
final class FarmLiveAddressSuggestions: ObservableObject {
    private(set) var status = "Zoom in for address suggestions"
    private var lastReportedStatus: String?
    private(set) var completionRevision = 0
    var onCompletion: (() -> Void)?
    func showStatus(_ message: String) {
        if lastReportedStatus != message {
            status = message
            lastReportedStatus = message
            let reason: String
            switch message {
            case "Zoom in for address suggestions": reason = "suggestions_blocked_zoom"
            case "Address suggestions paused while editing": reason = "suggestions_blocked_editing"
            case "Address suggestions unavailable in pin mode": reason = "suggestions_blocked_pin_mode"
            case "No unlinked properties in view": reason = "suggestions_no_targets"
            case "Connect to find address suggestions": reason = "suggestions_blocked_offline"
            default: reason = "suggestions_status_changed"
            }
            PerfTrace.event("farm_live", reason, fields: ["zoom": map?.mapboxMap.cameraState.zoom ?? -1])
            print("[FarmLiveSuggestions] \(message) requests=\(requestCount)")
        }
    }
    // The default campaign property view is zoom 16. Lookups and their labels
    // must activate together there, rather than silently waiting for another zoom.
    static let minimumZoom: Double = 16
    private static let sourceID = "farm-live-address-suggestions"
    private static let layerID = "farm-live-address-numbers"
    private static let pinSourceID = "farm-live-address-pins-source"
    private static let pinLayerID = "farm-live-address-pins"
    private let session: URLSession
    private weak var map: MapView?
    private var targets: [String: FarmLiveAddressTarget] = [:]
    private var visibleIDs = Set<String>()
    private var results: [String: BuildingAddressCandidate] = [:]
    private var resultTimes: [String: TimeInterval] = [:]
    private var attempted = Set<String>()
    private var retryAfter: [String: Date] = [:]
    private var running: [String: Task<Void, Never>] = [:]
    private var requestIDs: [String: UUID] = [:]
    private var queue: [String] = []
    private var association: FarmLiveAddressAssociation?
    private var closed = false
    private var renderedSignature: String?
    private var publishedIDs: [String] = []
    private var renderTask: Task<Void, Never>?
    private var networkRetryAfter = Date.distantPast
    private(set) var requestCount = 0

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        self.session = session ?? URLSession(configuration: configuration)
    }

    func update(targets input: [FarmLiveAddressTarget], map: MapView, online: Bool, association: FarmLiveAddressAssociation? = nil) {
        self.association = association
        closed = false
        self.map = map
        visibleIDs = Set(input.map(\.id))
        for target in input {
            if let previous = targets[target.id],
               abs(previous.coordinate.latitude - target.coordinate.latitude) > 0.000001 ||
               abs(previous.coordinate.longitude - target.coordinate.longitude) > 0.000001 ||
               abs((previous.lookupCoordinate ?? previous.coordinate).latitude - (target.lookupCoordinate ?? target.coordinate).latitude) > 0.000001 ||
               abs((previous.lookupCoordinate ?? previous.coordinate).longitude - (target.lookupCoordinate ?? target.coordinate).longitude) > 0.000001 {
                attempted.remove(target.id); results.removeValue(forKey: target.id)
                running.removeValue(forKey: target.id)?.cancel(); requestIDs.removeValue(forKey: target.id)
            }
            targets[target.id] = target
        }
        for id in Array(running.keys) where !visibleIDs.contains(id) || !online {
            running.removeValue(forKey: id)?.cancel()
            requestIDs.removeValue(forKey: id)
        }
        queue = online ? input.map(\.id).filter { !attempted.contains($0) && running[$0] == nil && (retryAfter[$0] ?? .distantPast) <= Date() } : []
        pump()
        scheduleRender()
    }

    /// Start the row's lookups together while preserving the existing request limit.
    func prefetch(_ input: [FarmLiveAddressTarget]) {
        guard !closed else { return }
        var priority: [String] = []
        for target in input {
            targets[target.id] = target
            visibleIDs.insert(target.id)
            guard results[target.id] == nil, !attempted.contains(target.id),
                  running[target.id] == nil,
                  (retryAfter[target.id] ?? .distantPast) <= Date(),
                  !priority.contains(target.id) else { continue }
            priority.append(target.id)
        }
        let priorityIDs = Set(priority)
        queue.removeAll { priorityIDs.contains($0) }
        queue.insert(contentsOf: priority, at: 0)
        pump()
    }

    func resolve(_ target: FarmLiveAddressTarget) async -> BuildingAddressCandidate? {
        guard !closed else { return nil }
        targets[target.id] = target
        visibleIDs.insert(target.id)
        if !attempted.contains(target.id) && running[target.id] == nil {
            queue.removeAll { $0 == target.id }; queue.insert(target.id, at: 0); pump()
        }
        while !closed && !Task.isCancelled && !attempted.contains(target.id) {
            if let task = running[target.id] { await task.value; break }
            guard queue.contains(target.id), let first = running.values.first else { break }
            await first.value
        }
        return results[target.id]
    }

    /// A lookup elsewhere in the viewport must not block an unrelated property.
    /// Shared roofs wait for siblings; independent properties match on arrival.
    func completedCandidates(for targets: [FarmLiveAddressTarget]) -> [(FarmLiveAddressTarget, BuildingAddressCandidate)]? {
        let pending = targets.filter { !attempted.contains($0.id) }
        let completed = targets.compactMap { target in results[target.id].map { (target, $0) } }
        let readyIDs = FarmLiveAddressNumberMatcher.readyTargets(completed.map(\.0), pending: pending)
        return readyIDs.isEmpty ? nil : completed
    }

    func readyTargetIDs(for targets: [FarmLiveAddressTarget]) -> Set<String> {
        FarmLiveAddressNumberMatcher.readyTargets(
            targets.filter { attempted.contains($0.id) && results[$0.id] != nil },
            pending: targets.filter { !attempted.contains($0.id) })
    }

    func candidate(for id: String) -> BuildingAddressCandidate? { results[id] }
    func target(at point: CGPoint) -> FarmLiveAddressTarget? {
        guard let map, map.mapboxMap.cameraState.zoom >= Self.minimumZoom else { return nil }
        return publishedIDs.compactMap { id -> (FarmLiveAddressTarget, CGFloat)? in
            guard results[id] != nil, let target = targets[id] else { return nil }
            let screen = map.mapboxMap.point(for: target.coordinate)
            let distance = hypot(screen.x - point.x, screen.y - point.y)
            return distance <= 22 ? (target, distance) : nil
        }.min { $0.1 < $1.1 }?.0
    }

    func recordAutomaticCommit(_ ids: [String]) {
        let now = ProcessInfo.processInfo.systemUptime
        let times = ids.compactMap { resultTimes[$0].map { (now - $0) * 1000 } }
        PerfTrace.event("farm_live", "result_to_local_link", fields: ["count": ids.count, "max_ms": times.max() ?? 0])
    }

    func remove(_ id: String) { remove([id]) }

    func remove(_ ids: [String]) {
        let removed = Set(ids)
        for id in removed {
            visibleIDs.remove(id); results.removeValue(forKey: id); resultTimes.removeValue(forKey: id)
            running.removeValue(forKey: id)?.cancel(); requestIDs.removeValue(forKey: id)
        }
        queue.removeAll { removed.contains($0) }
        pump()
        // Clear the estimate before the real marker is queued, so the handoff
        // cannot leave both markers visible until the next debounce tick.
        renderTask?.cancel(); renderTask = nil
        render()
    }

    func close() {
        onCompletion = nil
        closed = true
        lastReportedStatus = nil
        association = nil
        renderTask?.cancel(); renderTask = nil
        running.values.forEach { $0.cancel() }
        running.removeAll(); requestIDs.removeAll(); queue.removeAll(); results.removeAll()
        targets.removeAll(); resultTimes.removeAll(); attempted.removeAll(); retryAfter.removeAll(); visibleIDs.removeAll()
        render(); map = nil; requestCount = 0; renderedSignature = nil; networkRetryAfter = .distantPast
    }

    private func pump() {
        guard networkRetryAfter <= Date(), !Config.mapboxAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        while !closed && running.count < 4 && !queue.isEmpty {
            let id = queue.removeFirst()
            guard let target = targets[id], visibleIDs.contains(id), !attempted.contains(id), running[id] == nil else { continue }
            let requestID = UUID()
            requestIDs[id] = requestID
            running[id] = Task { [weak self] in
                guard let self else { return }
                do {
                    var url = URLComponents(string: "https://api.mapbox.com/search/geocode/v6/reverse")!
                    let lookupPoint = target.lookupCoordinate ?? target.coordinate
                    url.queryItems = [
                        .init(name: "longitude", value: String(lookupPoint.longitude)),
                        .init(name: "latitude", value: String(lookupPoint.latitude)),
                        .init(name: "types", value: "address"), .init(name: "limit", value: "1"),
                        .init(name: "permanent", value: "false"),
                        .init(name: "access_token", value: Config.mapboxAccessToken)
                    ]
                    requestCount += 1
                    let requestTrace = PerfTrace.begin("farm_live", "temporary_lookup")
                    let (data, response): (Data, URLResponse)
                    do {
                        (data, response) = try await session.data(from: url.url!)
                        requestTrace.end(status: "response")
                    } catch {
                        requestTrace.end(status: "failed")
                        throw error
                    }
                    try Task.checkCancellation()
                    guard requestIDs[id] == requestID else { return }
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    if http.statusCode == 401 || http.statusCode == 403 { networkRetryAfter = .distantFuture }
                    if http.statusCode == 429 || http.statusCode >= 500 { networkRetryAfter = Date().addingTimeInterval(60) }
                    guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                    results[id] = try FarmLiveAddressGeometry.candidate(data: data, target: target, association: association)
                    resultTimes[id] = ProcessInfo.processInfo.systemUptime
                    attempted.insert(id)
                    completionRevision &+= 1
                    onCompletion?()
                } catch {
                    guard requestIDs[id] == requestID else { return }
                    if !Task.isCancelled { retryAfter[id] = Date().addingTimeInterval(30) }
                }
                guard requestIDs[id] == requestID else { return }
                running.removeValue(forKey: id); requestIDs.removeValue(forKey: id)
                // Keep all request slots busy before doing any map/UI work.
                pump(); scheduleRender()
            }
        }
    }

    /// Merge a burst of responses into one source update and one SwiftUI notification.
    private func scheduleRender() {
        guard !closed, renderTask == nil else { return }
        renderTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            guard let self else { return }
            // Network work continues during panning; geometry publication waits for idle.
            while let map = self.map,
                  map.gestures.panGestureRecognizer.state == .began || map.gestures.panGestureRecognizer.state == .changed {
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            }
            guard !Task.isCancelled, !self.closed else { return }
            self.renderTask = nil
            self.render()
        }
    }

    private func render() {
        let trace = PerfTrace.begin("farm_live", "suggestion_publish")
        defer { trace.end() }
        let displayedIDs = FarmLiveSuggestionDisplay.uniqueIDs(visibleIDs.compactMap { id in results[id].map { (id, $0) } })
        publishedIDs = displayedIDs
        let shown = displayedIDs.count
        let pending = visibleIDs.filter { !attempted.contains($0) }.count
        if !visibleIDs.isEmpty {
            if networkRetryAfter == .distantFuture { showStatus("Address lookup unavailable · check access") }
            else if networkRetryAfter > Date() { showStatus("Address lookup paused · retrying shortly") }
            else if shown > 0 { showStatus("\(shown) suggested addresses · tap to save") }
            else if pending > 0 { showStatus("Finding addresses for \(visibleIDs.count) properties…") }
            else { showStatus("No suitable address suggestions here") }
        }
        guard let map, map.mapboxMap.isStyleLoaded else { return }
        let signature = displayedIDs.compactMap { id -> String? in
            guard let target = targets[id], let number = results[id]?.houseNumber else { return nil }
            return "\(id):\(number):\(target.coordinate.latitude):\(target.coordinate.longitude):\(target.showsTemporaryPin)"
        }.joined(separator: "|")
        guard signature != renderedSignature || !map.mapboxMap.sourceExists(withId: Self.sourceID) ||
                !map.mapboxMap.layerExists(withId: Self.layerID) else { return }
        let features = displayedIDs.compactMap { id -> Feature? in
            guard let target = targets[id], let number = results[id]?.houseNumber else { return nil }
            var feature = Feature(geometry: .point(Point(target.coordinate)))
            feature.identifier = .string(id)
            feature.properties = ["house_number_label": .string(number), "status": .string("not_visited"),
                "label_visibility_mode": .string("all_modes"), "label_priority": .number(100)]
            return feature
        }
        let collection = FeatureCollection(features: features)
        do {
            if !map.mapboxMap.sourceExists(withId: Self.sourceID) {
                var source = GeoJSONSource(id: Self.sourceID)
                source.data = .featureCollection(collection)
                try map.mapboxMap.addSource(source)
            } else { map.mapboxMap.updateGeoJSONSource(withId: Self.sourceID, geoJSON: .featureCollection(collection)) }
            let pinFeatures = features.filter { feature in
                guard case .string(let id)? = feature.identifier else { return false }
                return targets[id]?.showsTemporaryPin == true
            }
            let pinData = try MapLayerManager.temporaryAddressPinGeometry(JSONEncoder().encode(FeatureCollection(features: pinFeatures)))
            let pinGeometry = try JSONDecoder().decode(GeoJSONObject.self, from: pinData)
            if !map.mapboxMap.sourceExists(withId: Self.pinSourceID) {
                var source = GeoJSONSource(id: Self.pinSourceID)
                source.data = .featureCollection(try JSONDecoder().decode(FeatureCollection.self, from: pinData))
                try map.mapboxMap.addSource(source)
            } else { map.mapboxMap.updateGeoJSONSource(withId: Self.pinSourceID, geoJSON: pinGeometry) }
            try MapLayerManager.installTemporaryAddressLayers(on: map.mapboxMap,
                pinSource: Self.pinSourceID, labelSource: Self.sourceID,
                pinID: Self.pinLayerID, labelID: Self.layerID)
            renderedSignature = signature
            PerfTrace.event("farm_live", "labels_published", fields: ["count": features.count, "temporaryPins": pinFeatures.count])
        } catch { /* A style transition will install the overlay on the next idle event. */ }
    }
}

extension FarmLiveAddressGeometry {
    /// Only separate lots on the exact same roof qualify; never neighboring buildings.
    static func townhouseSiblings(of selected: FarmLiveAddressTarget, targets: [FarmLiveAddressTarget]) -> [FarmLiveAddressTarget] {
        guard let building = selected.buildingId?.lowercased(), selected.parcelId != nil else { return [] }
        var seen = Set<String>()
        return targets.filter {
            guard $0.id != selected.id, let parcel = $0.parcelId?.lowercased(),
                  parcel != selected.parcelId?.lowercased(), $0.buildingId?.lowercased() == building else { return false }
            return seen.insert(parcel).inserted
        }
    }

    /// Index addresses/buildings into small cells so a large farm is not a parcels × addresses scan.
    static func targets(parcels: [ParcelFeature], buildings: [BuildingFeature], addresses: [AddressFeature], reviewableAddressIDs: Set<String> = [],
                        repairableAddressIDs: Set<String> = [], repairParcelIDs: Set<String> = []) -> [FarmLiveAddressTarget] {
        let cellSize = 0.002
        func cell(_ point: CLLocationCoordinate2D) -> String { "\(Int(floor(point.longitude / cellSize))):\(Int(floor(point.latitude / cellSize)))" }
        func keys(_ shape: PreparedShape) -> [String] {
            let box = shape.bounds
            let left = Int(floor(box[0] / cellSize)), right = Int(floor(box[2] / cellSize))
            let bottom = Int(floor(box[1] / cellSize)), top = Int(floor(box[3] / cellSize))
            guard (right-left+1) * (top-bottom+1) <= 50_000 else { return [] }
            return (left...right).flatMap { x in (bottom...top).map { "\(x):\($0)" } }
        }
        func protectedAddresses(repairing: Bool) -> [AddressFeature] {
            addresses.filter {
                let id = ($0.properties.id ?? $0.id ?? "").lowercased()
                return !reviewableAddressIDs.contains(id) && !(repairing && repairableAddressIDs.contains(id))
            }
        }
        let normalAddresses = protectedAddresses(repairing: false)
        let repairAddresses = protectedAddresses(repairing: true)
        func protectedOwners(_ ids: [String], repairing: Bool = false) -> Bool {
            ids.contains { !reviewableAddressIDs.contains($0.lowercased()) && !(repairing && repairableAddressIDs.contains($0.lowercased())) }
        }
        func pointIndex(_ input: [AddressFeature]) -> [String: [CLLocationCoordinate2D]] {
            let points = input.compactMap { feature -> CLLocationCoordinate2D? in
                let p = feature.properties
                guard p.hasBuildingLink == true || p.hasParcelLink == true || p.buildingGersId != nil ||
                        p.linkedBuildingId != nil || p.parcelId != nil || p.campaignParcelId != nil else { return nil }
                return CampaignMapEditPlanner.center(feature.geometry)
            }
            return Dictionary(grouping: points, by: cell)
        }
        let normalPoints = pointIndex(normalAddresses), repairPoints = pointIndex(repairAddresses)
        func occupied(_ shape: PreparedShape, repairing: Bool = false) -> Bool {
            let index = repairing ? repairPoints : normalPoints
            return keys(shape).contains { key in (index[key] ?? []).contains { shape.contains($0) } }
        }
        func parcelLinks(_ input: [AddressFeature]) -> Set<String> {
            Set(input.flatMap { [$0.properties.parcelId, $0.properties.campaignParcelId].compactMap { $0?.lowercased() } })
        }
        func buildingLinks(_ input: [AddressFeature]) -> Set<String> {
            Set(input.flatMap { [$0.properties.buildingGersId, $0.properties.linkedBuildingId].compactMap { $0?.lowercased() } })
        }
        let normalParcels = parcelLinks(normalAddresses), repairParcels = parcelLinks(repairAddresses)
        let normalBuildings = buildingLinks(normalAddresses), repairBuildings = buildingLinks(repairAddresses)
        let pendingStops = addresses.filter(FarmLiveMatchIndex.isPendingGeometryStop)
        let pendingParcels = parcelLinks(pendingStops), pendingBuildings = buildingLinks(pendingStops)
        func linked(_ building: BuildingFeature, repairing: Bool = false) -> Bool {
            let p = building.properties
            let owners = p.addressIds + [p.addressId].compactMap { $0 }
            let links = repairing ? repairBuildings : normalBuildings
            return protectedOwners(owners, repairing: repairing) || (p.effectiveIsLinked && owners.isEmpty) ||
                p.buildingIdentifierCandidates.contains { links.contains($0.lowercased()) }
        }
        let roofs = buildings.compactMap { building -> (BuildingFeature, CLLocationCoordinate2D, PreparedShape)? in
            guard let shape = PreparedShape(building.geometry), let point = shape.interiorPoint else { return nil }
            return (building, point, shape)
        }
        // Index the entire footprint: a shared townhouse roof can span several lots.
        var roofsByCell: [String: [(BuildingFeature, CLLocationCoordinate2D, PreparedShape)]] = [:]
        for roof in roofs {
            for key in keys(roof.2) { roofsByCell[key, default: []].append(roof) }
        }
        var ownedBuildings = Set<String>()
        var output: [FarmLiveAddressTarget] = []
        for parcel in parcels {
            guard !Task.isCancelled else { return [] }
            let aliases = [parcel.id, parcel.properties.id, parcel.properties.parcelId, parcel.properties.externalId].compactMap { $0 }
            guard let id = aliases.first else { continue }
            guard let parcelShape = PreparedShape(parcel.geometry), let point = parcelShape.interiorPoint else { continue }
            var seenRoofs = Set<String>()
            let children = keys(parcelShape).flatMap { roofsByCell[$0] ?? [] }.filter {
                guard let roofID = $0.0.properties.canonicalBuildingIdentifier,
                      seenRoofs.insert(roofID).inserted else { return false }
                return parcelShape.contains($0.1) || $0.2.contains(point)
            }
            for child in children { ownedBuildings.formUnion(child.0.properties.buildingIdentifierCandidates.map { $0.lowercased() }) }
            let repairing = aliases.contains { repairParcelIDs.contains($0.lowercased()) }
            let linkedParcels = repairing ? repairParcels : normalParcels
            guard !protectedOwners((parcel.properties.addressIds ?? []) + [parcel.properties.addressId].compactMap { $0 }, repairing: repairing),
                  !aliases.contains(where: { linkedParcels.contains($0.lowercased()) }),
                  !children.contains(where: { linked($0.0, repairing: repairing) && parcelShape.contains($0.1) }),
                  !occupied(parcelShape, repairing: repairing) else { continue }
            let eligible = children.filter { eligibleBuilding($0.0) }
            let roof = eligible.max { ($0.0.properties.areaSqm ?? 0) < ($1.0.properties.areaSqm ?? 0) }
            // Reverse geocoding an empty yard can return the neighbouring home.
            // Prefer the roof interior when it is inside this lot; a shared roof
            // whose interior is on a sibling lot retains this parcel's own point.
            // Anchor the temporary number there too so it stays on its building.
            let lookupPoint = roof.flatMap { parcelShape.contains($0.1) ? $0.1 : nil } ?? point
            output.append(.init(id: "parcel:\(id.lowercased())", parcelId: id,
                buildingId: roof?.0.properties.canonicalBuildingIdentifier,
                geometry: parcel.geometry, coordinate: lookupPoint, lookupCoordinate: lookupPoint,
                showsTemporaryPin: !aliases.contains { pendingParcels.contains($0.lowercased()) }))
        }
        // A roof outside parcel coverage is still eligible. A roof on a covered parcel never adds a second target.
        for (building, point, shape) in roofs {
            guard !Task.isCancelled else { return [] }
            let p = building.properties
            guard eligibleBuilding(building), !linked(building), !occupied(shape),
                  !p.buildingIdentifierCandidates.contains(where: { ownedBuildings.contains($0.lowercased()) }),
                  let id = p.canonicalBuildingIdentifier else { continue }
            output.append(.init(id: "building:\(id.lowercased())", parcelId: nil, buildingId: id,
                                geometry: building.geometry, coordinate: point,
                                showsTemporaryPin: !p.buildingIdentifierCandidates.contains { pendingBuildings.contains($0.lowercased()) }))
        }
        var seenIDs = Set<String>()
        var seenCenters = Set<String>()
        return output.filter { target in
            let center = "\(Int((target.coordinate.longitude * 10_000_000).rounded())):\(Int((target.coordinate.latitude * 10_000_000).rounded()))"
            return seenIDs.insert(target.id).inserted && seenCenters.insert(center).inserted
        }
    }
}

/// Immutable index prepared off the main thread and reused for the geometry revision.
struct FarmLiveMatchIndex {
    struct Entry {
        let id: UUID
        let identity: String
        let feature: AddressFeature
        let coordinate: CLLocationCoordinate2D
    }
    struct Placement {
        let addressID: UUID
        let target: FarmLiveAddressTarget
        let coordinate: CLLocationCoordinate2D
        var supersededAddressIDs: Set<UUID> = []
    }
    private var byIdentity: [String: [Entry]] = [:]
    private var byHouse: [String: [Entry]] = [:]
    private(set) var verifiedStreetAliases: [UUID: String] = [:]
    private var buildings: [BuildingFeature]
    private var parcelOwners: [String: Set<UUID>] = [:]
    private var buildingOwners: [String: Set<UUID>] = [:]
    private var unusedPendingIDs = Set<UUID>()
    private var pendingGeometryStops: [UUID: AddressFeature] = [:]
    private var parcelFeatures: [String: ParcelFeature] = [:]
    private(set) var existingLinkCandidates: [(FarmLiveAddressTarget, BuildingAddressCandidate)] = []
    private var fixedParcels: [UUID: String] = [:]
    private var parcelAliases: [String: String] = [:]
    private var parcelShapes: [String: FarmLiveAddressGeometry.PreparedShape] = [:]
    private(set) var reviewableAddressIDs = Set<String>()
    private(set) var lookupAddressIDs = Set<String>()
    var repairParcelIDs: Set<String> { Set(fixedParcels.values) }
    private(set) var normalizedIdentities: [UUID: String] = [:]

    init(addresses: [AddressFeature], buildings: [BuildingFeature], edits: CampaignMapEditState? = nil,
         evidence: [FarmLiveLinkEvidence] = [], parcels: [ParcelFeature] = [],
         normalizedIdentities: [UUID: String] = [:], unusedGeometryStopIDs: Set<UUID> = [],
         verifiedStreetAliases: [UUID: String] = [:]) {
        self.normalizedIdentities = normalizedIdentities
        self.verifiedStreetAliases = verifiedStreetAliases
        self.buildings = buildings
        for parcel in parcels {
            let aliases = [parcel.id, parcel.properties.id, parcel.properties.parcelId, parcel.properties.externalId].compactMap { $0?.lowercased() }
            if let canonical = aliases.first {
                for alias in aliases { parcelAliases[alias] = canonical }
                parcelShapes[canonical] = FarmLiveAddressGeometry.PreparedShape(parcel.geometry)
                parcelFeatures[canonical] = parcel
            }
        }
        let evidenceByID = Dictionary(grouping: evidence, by: { $0.addressID.lowercased() })
        for feature in addresses {
            let p = feature.properties
            guard let id = UUID(uuidString: p.id ?? feature.id ?? "") else { continue }
            let key = id.uuidString.lowercased()
            let edit = edits?.features[CampaignMapEdits.addressItem(feature).id]
            guard edit?.hidden != true else { continue }
            let building = edit?.buildingLinkSet == true ? edit?.buildingId : (p.buildingGersId ?? p.linkedBuildingId)
            let parcel = edit?.parcelLinkSet == true ? edit?.parcelId : (p.parcelId ?? p.campaignParcelId)
            let buildingLinked = edit?.buildingLinkSet == true ? building != nil : (building != nil || p.hasBuildingLink == true)
            let parcelLinked = edit?.parcelLinkSet == true ? parcel != nil : (parcel != nil || p.hasParcelLink == true)
            if let building { buildingOwners[building.lowercased(), default: []].insert(id) }
            if let parcel { parcelOwners[parcelAliases[parcel.lowercased()] ?? parcel.lowercased(), default: []].insert(id) }
            // A pending stop is not a civic match. Only freshly checked, untouched
            // placeholders may yield to an existing, fully matching civic address.
            if Self.isPendingGeometryStop(feature) {
                lookupAddressIDs.insert(key)
                let protectedLink = (evidenceByID[key] ?? []).contains { !$0.canRepair }
                if unusedGeometryStopIDs.contains(id), edit == nil, !protectedLink {
                    unusedPendingIDs.insert(id)
                    pendingGeometryStops[id] = feature
                }
                continue
            }
            let rows = evidenceByID[key] ?? []
            let protectedEdit = edit?.geometry != nil || edit?.buildingLinkSet == true || edit?.parcelLinkSet == true
            // Old parcel-only corrections may still inherit an unrelated base building.
            let incompleteParcel = edit?.parcelLinkSet == true && parcel != nil &&
                edit?.buildingLinkSet != true
            let automatic = !rows.isEmpty && rows.allSatisfy(\.canRepair)
            guard incompleteParcel || (!protectedEdit && (!buildingLinked && !parcelLinked || automatic)),
                  let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry),
                  let identity = verifiedStreetAliases[id].flatMap({ UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                    houseNumber: p.houseNumber ?? p.houseNumberLabel, streetName: $0, postalCode: p.postalCode, formatted: p.formatted, unit: p.unit) }) ?? normalizedIdentities[id] ?? UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                    houseNumber: p.houseNumber ?? p.houseNumberLabel, streetName: p.streetName,
                    postalCode: p.postalCode, formatted: p.formatted, unit: p.unit) else { continue }
            self.normalizedIdentities[id] = identity
            if incompleteParcel, let parcel { fixedParcels[id] = parcelAliases[parcel.lowercased()] ?? parcel.lowercased() }
            reviewableAddressIDs.insert(key)
            if incompleteParcel || (!buildingLinked && !parcelLinked) { lookupAddressIDs.insert(key) }
            let entry = Entry(id: id, identity: identity, feature: feature, coordinate: coordinate)
            byIdentity[identity, default: []].append(entry)
            if let house = identity.split(separator: "|").first { byHouse[String(house), default: []].append(entry) }
        }
        // Geometry ownership can carry addresses missing from the address payload.
        for building in buildings {
            let owners = (building.properties.addressIds + [building.properties.addressId].compactMap { $0 }).compactMap(UUID.init(uuidString:))
            for alias in building.properties.buildingIdentifierCandidates {
                for owner in owners {
                    let edit = edits?.features[CampaignMapItem(.address, owner.uuidString).id]
                    if edit?.hidden == true || edit?.buildingLinkSet == true { continue }
                    buildingOwners[alias.lowercased(), default: []].insert(owner)
                }
            }
        }
        for parcel in parcels {
            guard let alias = [parcel.id, parcel.properties.id, parcel.properties.parcelId, parcel.properties.externalId].compactMap({ $0 }).first else { continue }
            for owner in ((parcel.properties.addressIds ?? []) + [parcel.properties.addressId].compactMap { $0 }).compactMap(UUID.init(uuidString:)) {
                let edit = edits?.features[CampaignMapItem(.address, owner.uuidString).id]
                if edit?.hidden == true || edit?.parcelLinkSet == true { continue }
                parcelOwners[alias.lowercased(), default: []].insert(owner)
            }
        }
        existingLinkCandidates = makeExistingLinkCandidates()
    }

    /// A native civic row and an empty generated stop on the same single-home
    /// roof are one home, not a townhouse. Existing native links supply proof;
    /// no reverse geocode or new address row is needed.
    private func makeExistingLinkCandidates() -> [(FarmLiveAddressTarget, BuildingAddressCandidate)] {
        var roofs: [String: BuildingFeature] = [:]
        for building in buildings {
            for alias in building.properties.buildingIdentifierCandidates { roofs[alias.lowercased()] = building }
        }
        return pendingGeometryStops.compactMap { pendingID, stop in
            let p = stop.properties
            guard let roofID = (p.buildingGersId ?? p.linkedBuildingId)?.lowercased(),
                  let roof = roofs[roofID], let owners = buildingOwners[roofID], owners.count == 2,
                  owners.contains(pendingID),
                  let nativeID = owners.subtracting(unusedPendingIDs).first,
                  let identity = normalizedIdentities[nativeID],
                  let entry = byIdentity[identity]?.first(where: { $0.id == nativeID }),
                  let lot = (p.parcelId ?? p.campaignParcelId).map({ parcelAliases[$0.lowercased()] ?? $0.lowercased() }),
                  let parcel = parcelFeatures[lot], let shape = parcelShapes[lot],
                  let point = FarmLiveAddressGeometry.PreparedShape(roof.geometry)?.interiorPoint, shape.contains(point),
                  (parcelOwners[lot] ?? []).subtracting([pendingID, nativeID]).isEmpty else { return nil }
            let native = entry.feature.properties
            if let linkedLot = native.parcelId ?? native.campaignParcelId,
               (parcelAliases[linkedLot.lowercased()] ?? linkedLot.lowercased()) != lot { return nil }
            let target = FarmLiveAddressTarget(id: "parcel:\(lot)", parcelId: lot, buildingId: roofID,
                geometry: parcel.geometry, coordinate: point, showsTemporaryPin: false)
            let candidate = BuildingAddressCandidate(id: nativeID, candidateType: "existing_campaign_address", isSynthetic: false,
                formatted: native.formatted, houseNumber: native.houseNumber ?? native.houseNumberLabel,
                streetName: native.streetName, locality: native.locality, region: nil,
                postalCode: native.postalCode, country: nil, source: "existing_campaign_address",
                coordinate: CandidateCoordinate(longitude: point.longitude, latitude: point.latitude), distanceMeters: 0,
                score: 1, reason: "Existing home link", confidenceLabel: "confirmed", requiresConfirmation: false)
            return (target, candidate)
        }
    }

    func renderFeatures(for placements: [Placement], confirmedAddresses: [AddressFeature]? = nil) -> [AddressFeature] {
        // A picker selection is explicit authorization to move an existing row,
        // including one that is deliberately ineligible for automatic matching.
        let requested = Set(placements.map { $0.addressID.uuidString.lowercased() })
        let originals = confirmedAddresses?.filter { requested.contains(($0.properties.id ?? $0.id ?? "").lowercased()) } ?? placements.compactMap { placement -> AddressFeature? in
            guard let identity = normalizedIdentities[placement.addressID] else { return nil }
            return byIdentity[identity]?.first { $0.id == placement.addressID }?.feature
        }
        let changes = placements.map { placement in
            CampaignMapEditPlanner.addressPlacement(addressId: placement.addressID.uuidString,
                coordinate: placement.coordinate, buildingId: placement.target.buildingId,
                parcelId: placement.target.parcelId, state: .init(), sourceRevision: nil)
        }
        return CampaignMapEdits.snapshot(buildings: [], addresses: originals, parcels: [],
            state: CampaignMapEditState().applying(changes)).addresses
    }

    /// Recompute relationships only for the old and new properties. Retain the
    /// complete address list so other occupants of a shared roof are preserved.
    static func advancingSnapshot(buildings: [BuildingFeature], addresses: [AddressFeature],
                                  parcels: [ParcelFeature], replacements: [AddressFeature],
                                  hiddenAddressIDs: Set<UUID> = []) -> CampaignMapEditSnapshot {
        let moved = Set(replacements.map { CampaignMapEdits.addressItem($0).featureID })
        let previous = addresses.filter { moved.contains(CampaignMapEdits.addressItem($0).featureID) }
        let affected = previous + replacements
        let roofs = Set(affected.flatMap { [$0.properties.buildingGersId, $0.properties.linkedBuildingId].compactMap { $0?.lowercased() } })
        let lots = Set(affected.flatMap { [$0.properties.parcelId, $0.properties.campaignParcelId].compactMap { $0?.lowercased() } })
        let buildingIndices = buildings.indices.filter { index in
            let p = buildings[index].properties
            return !roofs.isDisjoint(with: p.buildingIdentifierCandidates.map { $0.lowercased() }) ||
                !moved.isDisjoint(with: (p.addressIds + [p.addressId].compactMap { $0 }).map { $0.lowercased() })
        }
        let parcelIndices = parcels.indices.filter { index in
            let p = parcels[index]
            return !lots.isDisjoint(with: [p.id, p.properties.id, p.properties.parcelId, p.properties.externalId].compactMap { $0?.lowercased() }) ||
                !moved.isDisjoint(with: ((p.properties.addressIds ?? []) + [p.properties.addressId].compactMap { $0 }).map { $0.lowercased() })
        }
        let byID = Dictionary(replacements.map { (CampaignMapEdits.addressItem($0).featureID, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(addresses.map { CampaignMapEdits.addressItem($0).featureID })
        let updatedAddresses = addresses.map { byID[CampaignMapEdits.addressItem($0).featureID] ?? $0 } +
            replacements.filter { !existing.contains(CampaignMapEdits.addressItem($0).featureID) }
        // Link flags in this state also clear old ownership during relocations.
        var changes = replacements.compactMap { feature -> CampaignMapEditChange? in
            guard let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else { return nil }
            return CampaignMapEditPlanner.addressPlacement(addressId: CampaignMapEdits.addressItem(feature).featureID,
                coordinate: coordinate, buildingId: feature.properties.buildingGersId ?? feature.properties.linkedBuildingId,
                parcelId: feature.properties.parcelId ?? feature.properties.campaignParcelId, state: .init(), sourceRevision: nil)
        }
        changes += hiddenAddressIDs.map { CampaignMapEditChange(CampaignMapItem(.address, $0.uuidString), value: .init(hidden: true)) }
        let corrected = CampaignMapEdits.snapshot(buildings: buildingIndices.map { buildings[$0] },
            addresses: updatedAddresses, parcels: parcelIndices.map { parcels[$0] },
            state: CampaignMapEditState().applying(changes))
        var nextBuildings = buildings, nextParcels = parcels
        for (index, feature) in zip(buildingIndices, corrected.buildings) { nextBuildings[index] = feature }
        for (index, feature) in zip(parcelIndices, corrected.parcels) { nextParcels[index] = feature }
        return .init(buildings: nextBuildings, addresses: corrected.addresses, parcels: nextParcels)
    }

    func previousBuildingIDs(for placements: [Placement]) -> Set<String> {
        Set(placements.flatMap { placement -> [String] in
            guard let identity = normalizedIdentities[placement.addressID],
                  let feature = byIdentity[identity]?.first(where: { $0.id == placement.addressID })?.feature else { return [] }
            return [feature.properties.buildingGersId, feature.properties.linkedBuildingId].compactMap { $0?.lowercased() }
        })
    }

    func parcelRenderAliases(_ parcel: String) -> [String] {
        let canonical = parcelAliases[parcel.lowercased()] ?? parcel.lowercased()
        return Array(Set([parcel.lowercased(), canonical] + parcelAliases.compactMap { $0.value == canonical ? $0.key : nil }))
    }

    /// Address placements do not change parcel/roof shapes. Advance ownership and
    /// remove resolved identities without rebuilding the farm's geometry or index.
    func applying(_ placements: [Placement]) -> Self {
        var updated = self
        let superseded = Set(placements.flatMap(\.supersededAddressIDs))
        let moved = Set(placements.map(\.addressID)).union(superseded)
        updated.unusedPendingIDs.subtract(superseded)
        for id in superseded { updated.pendingGeometryStops.removeValue(forKey: id) }
        updated.existingLinkCandidates.removeAll { movedIDs in placements.contains { $0.addressID == movedIDs.1.id } }
        updated.lookupAddressIDs.subtract(superseded.map { $0.uuidString.lowercased() })
        updated.byIdentity = byIdentity.compactMapValues { entries in
            let remaining = entries.filter { !moved.contains($0.id) }
            return remaining.isEmpty ? nil : remaining
        }
        updated.byHouse = byHouse.compactMapValues { entries in
            let remaining = entries.filter { !moved.contains($0.id) }
            return remaining.isEmpty ? nil : remaining
        }
        updated.parcelOwners = parcelOwners.compactMapValues { owners in
            let remaining = owners.subtracting(moved)
            return remaining.isEmpty ? nil : remaining
        }
        updated.buildingOwners = buildingOwners.compactMapValues { owners in
            let remaining = owners.subtracting(moved)
            return remaining.isEmpty ? nil : remaining
        }
        for placement in placements {
            updated.reviewableAddressIDs.remove(placement.addressID.uuidString.lowercased())
            updated.lookupAddressIDs.remove(placement.addressID.uuidString.lowercased())
            updated.fixedParcels.removeValue(forKey: placement.addressID)
            if let parcel = placement.target.parcelId?.lowercased() {
                updated.parcelOwners[parcelAliases[parcel] ?? parcel, default: []].insert(placement.addressID)
            }
            if let building = placement.target.buildingId?.lowercased() {
                updated.buildingOwners[building, default: []].insert(placement.addressID)
            }
        }
        return updated
    }

    static func isPendingGeometryStop(_ feature: AddressFeature) -> Bool {
        let p = feature.properties
        guard p.gersId?.lowercased().hasPrefix("synthetic:geometry-target:") == true else { return false }
        // Placeholder text must never be parsed as if "Address" were a house
        // number and "pending" a street. Confirmed geometry stops carry civic fields.
        return UnlinkedHomeAddressResolver.normalizedAddressIdentity(
            houseNumber: p.houseNumber ?? p.houseNumberLabel, streetName: p.streetName,
            postalCode: p.postalCode, formatted: nil) == nil
    }

    func updatingBuildings(_ buildings: [BuildingFeature]) -> Self {
        var updated = self
        updated.buildings = buildings
        return updated
    }

    func shortlist(_ candidates: [(FarmLiveAddressTarget, BuildingAddressCandidate)]) -> [Entry] {
        var selected: [UUID: Entry] = [:]
        for (_, candidate) in candidates {
            guard let identity = UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: candidate.houseNumber, streetName: candidate.resolvedStreetName,
                postalCode: candidate.postalCode, formatted: candidate.displayAddress) else { continue }
            for entry in byIdentity[identity] ?? [] {
                selected[entry.id] = entry
            }
        }
        return Array(selected.values)
    }

    struct StreetAliasCheck {
        let entry: Entry
        let candidate: BuildingAddressCandidate
        var key: String { entry.id.uuidString + ":" + (candidate.resolvedStreetName ?? "") }
    }

    /// A plural spelling difference is only a request for independent geographic
    /// verification, never an address match by itself. Directions/types stay exact.
    static func needsLocalStreetVerification(_ first: String, _ second: String) -> Bool {
        let a = first.split(separator: " ").map(String.init), b = second.split(separator: " ").map(String.init)
        guard a.count == b.count else { return false }
        let different = a.indices.filter { a[$0] != b[$0] }
        guard different.count == 1, let i = different.first else { return false }
        let reserved: Set<String> = ["north", "south", "east", "west", "northeast", "northwest", "southeast", "southwest",
            "street", "road", "avenue", "boulevard", "drive", "court", "crescent", "lane", "place", "trail", "parkway", "highway"]
        guard !reserved.contains(a[i]), !reserved.contains(b[i]), min(a[i].count, b[i].count) >= 4 else { return false }
        return a[i] == b[i] + "s" || b[i] == a[i] + "s"
    }

    func streetAliasChecks(_ candidates: [(FarmLiveAddressTarget, BuildingAddressCandidate)]) -> [StreetAliasCheck] {
        var checks: [UUID: StreetAliasCheck] = [:]
        for (target, candidate) in candidates {
            guard let identity = UnlinkedHomeAddressResolver.normalizedAddressIdentity(houseNumber: candidate.houseNumber,
                streetName: candidate.resolvedStreetName), byIdentity[identity] == nil else { continue }
            let parts = identity.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let postal = candidate.postalCode, !postal.isEmpty else { continue }
            let nearby = (byHouse[parts[0]] ?? []).filter { entry in
                guard verifiedStreetAliases[entry.id] == nil,
                      entry.feature.properties.postalCode?.caseInsensitiveCompare(postal) == .orderedSame,
                      let street = entry.identity.split(separator: "|", maxSplits: 1).last,
                      Self.needsLocalStreetVerification(String(street), parts[1]) else { return false }
                return CLLocation(latitude: entry.coordinate.latitude, longitude: entry.coordinate.longitude)
                    .distance(from: CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)) <= 100
            }
            if nearby.count == 1, let entry = nearby.first { checks[entry.id] = .init(entry: entry, candidate: candidate) }
        }
        return checks.values.sorted { $0.key < $1.key }
    }

    func acceptingStreetAliases(_ aliases: [UUID: String]) -> Self {
        var updated = self
        for (id, street) in aliases {
            guard let old = byHouse.values.lazy.flatMap({ $0 }).first(where: { $0.id == id }),
                  let identity = UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                    houseNumber: old.feature.properties.houseNumber ?? old.feature.properties.houseNumberLabel, streetName: street,
                    postalCode: old.feature.properties.postalCode, formatted: old.feature.properties.formatted, unit: old.feature.properties.unit) else { continue }
            updated.byIdentity[old.identity]?.removeAll { $0.id == id }
            if updated.byIdentity[old.identity]?.isEmpty == true { updated.byIdentity.removeValue(forKey: old.identity) }
            updated.byIdentity[identity, default: []].append(.init(id: id, identity: identity, feature: old.feature, coordinate: old.coordinate))
            updated.normalizedIdentities[id] = identity
            updated.verifiedStreetAliases[id] = street
        }
        return updated
    }

    func placements(candidates: [(FarmLiveAddressTarget, BuildingAddressCandidate)], visibleEntries: [Entry], readyTargetIDs: Set<String>? = nil) -> [Placement] {
        let targetByID = Dictionary(candidates.map { ($0.0.id, $0.0) }, uniquingKeysWith: { first, _ in first })
        let candidateByID = Dictionary(candidates.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
        let featureByID = Dictionary(visibleEntries.map { ($0.id, $0.feature) }, uniquingKeysWith: { first, _ in first })
        let addresses: [(UUID, String?)] = visibleEntries.map { ($0.id, $0.identity) }
        let pairs = FarmLiveAddressNumberMatcher.uniquePairs(
            targets: candidates.map { ($0.0.id, UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: $0.1.houseNumber, streetName: $0.1.resolvedStreetName,
                postalCode: $0.1.postalCode, formatted: $0.1.displayAddress)) }, addresses: addresses)
        PerfTrace.event("farm_live", "match_pairs", fields: ["accepted": candidates.count, "visible": visibleEntries.count, "matches": pairs.count])
        var placements: [Placement] = []
        let wantedBuildings = Set(pairs.compactMap { targetByID[$0.0]?.buildingId?.lowercased() })
        var footprints: [String: FarmLiveAddressGeometry.PreparedShape] = [:]
        if !wantedBuildings.isEmpty {
            for building in buildings {
                let matches = building.properties.buildingIdentifierCandidates.map { $0.lowercased() }.filter { wantedBuildings.contains($0) }
                guard !matches.isEmpty, let shape = FarmLiveAddressGeometry.PreparedShape(building.geometry) else { continue }
                for id in matches { footprints[id] = shape }
            }
        }
        for (targetID, addressID) in pairs {
            guard readyTargetIDs?.contains(targetID) != false else { continue }
            guard let target = targetByID[targetID],
                  let suggestion = candidateByID[targetID],
                  let feature = featureByID[addressID],
                  UnlinkedHomeAddressResolver.campaignAddressMatches(
                    reverseCandidate: suggestion, houseNumber: feature.properties.houseNumber ?? feature.properties.houseNumberLabel,
                    streetName: verifiedStreetAliases[addressID] ?? feature.properties.streetName, postalCode: feature.properties.postalCode,
                    formatted: feature.properties.formatted) else {
                PerfTrace.event("farm_live", "match_rejected_civic_validation")
                continue
            }
            if let fixed = fixedParcels[addressID] {
                guard let parcel = target.parcelId, (parcelAliases[parcel.lowercased()] ?? parcel.lowercased()) == fixed,
                      target.buildingId != nil else { continue }
            }
            let point: CLLocationCoordinate2D
            if let building = target.buildingId {
                guard let footprint = footprints[building.lowercased()], let roofPoint = footprint.interiorPoint,
                      let targetShape = FarmLiveAddressGeometry.PreparedShape(target.geometry) else { continue }
                // Keep the pin inside both the parcel and roof for shared buildings.
                guard let interior = (0...100).lazy.map({ step in
                    let fraction = Double(step) / 100.0
                    return CLLocationCoordinate2D(
                        latitude: target.coordinate.latitude + (roofPoint.latitude - target.coordinate.latitude) * fraction,
                        longitude: target.coordinate.longitude + (roofPoint.longitude - target.coordinate.longitude) * fraction)
                }).first(where: { targetShape.contains($0) && footprint.contains($0) }) else { continue }
                point = interior
            } else {
                guard target.parcelId != nil, CampaignMapEditPlanner.contains(target.geometry, target.coordinate) else { continue }
                point = target.coordinate
            }
            let parcelKey = target.parcelId.map { parcelAliases[$0.lowercased()] ?? $0.lowercased() }
            let occupants = parcelKey.map { parcelOwners[$0] ?? [] }
                ?? (target.buildingId.flatMap { buildingOwners[$0.lowercased()] } ?? [])
            placements.append(Placement(addressID: addressID, target: target, coordinate: point,
                supersededAddressIDs: occupants.intersection(unusedPendingIDs)))
        }
        // Resolve relocation chains as one journal transaction. If an occupant has no
        // verified destination, remove the dependent move; repeat to a fixed point.
        var accepted = Dictionary(placements.map { ($0.addressID, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = true
        while changed {
            changed = false
            for placement in Array(accepted.values) {
                let parcel = placement.target.parcelId.map { parcelAliases[$0.lowercased()] ?? $0.lowercased() }
                let roof = placement.target.buildingId?.lowercased()
                let parcelConflicts = parcel.map { parcelOwners[$0] ?? [] } ?? []
                let roofConflicts = roof.map { buildingOwners[$0] ?? [] } ?? []
                let blockedParcel = parcelConflicts.subtracting([placement.addressID]).contains { owner in
                    if placement.supersededAddressIDs.contains(owner) { return false }
                    guard let move = accepted[owner] else { return true }
                    return move.target.parcelId.map { parcelAliases[$0.lowercased()] ?? $0.lowercased() } == parcel
                }
                let blockedRoof = roofConflicts.subtracting([placement.addressID]).contains { owner in
                    if placement.supersededAddressIDs.contains(owner) { return false }
                    // A known distinct parcel can legitimately share a townhouse roof.
                    if let parcel, let roof, let footprint = footprints[roof],
                       parcelOwners.contains(where: { other in
                           guard other.key != parcel, other.value.contains(owner), let shape = parcelShapes[other.key] else { return false }
                           return footprint.interiorPoint.map(shape.contains) == true || shape.interiorPoint.map(footprint.contains) == true
                       }) { return false }
                    guard let move = accepted[owner] else { return true }
                    if move.target.buildingId?.lowercased() != roof { return false }
                    guard let parcel, let destination = move.target.parcelId else { return true }
                    return (parcelAliases[destination.lowercased()] ?? destination.lowercased()) == parcel
                }
                if blockedParcel || blockedRoof { accepted.removeValue(forKey: placement.addressID); changed = true }
            }
        }
        return placements.filter { accepted[$0.addressID] != nil }
    }
}

/// Fresh backend provenance; missing protection fields fail closed.
struct FarmLiveLinkEvidence: Decodable {
    let addressID: String
    let linkSource: String?
    let userConfirmed: Bool?
    let locked: Bool?
    var canRepair: Bool {
        ["auto", "auto_parcel", "client_auto_expired"].contains(linkSource ?? "") && userConfirmed == false && locked == false
    }
    enum CodingKeys: String, CodingKey {
        case addressID = "address_id", linkSource = "link_source", userConfirmed = "user_confirmed", locked
    }
}

/// Includes linked neighbours too: a lookup must never borrow their address.
struct FarmLiveAddressAssociation {
    private struct Property {
        let aliases: Set<String>
        let shape: FarmLiveAddressGeometry.PreparedShape
    }
    private var properties: [Property] = []

    init(parcels: [ParcelFeature], buildings: [BuildingFeature]) {
        for parcel in parcels {
            guard let shape = FarmLiveAddressGeometry.PreparedShape(parcel.geometry) else { continue }
            let aliases = [parcel.id, parcel.properties.id, parcel.properties.parcelId, parcel.properties.externalId]
                .compactMap { $0 }.map { "parcel:" + $0.lowercased() }
            properties.append(Property(aliases: Set(aliases), shape: shape))
        }
        for building in buildings {
            guard let shape = FarmLiveAddressGeometry.PreparedShape(building.geometry) else { continue }
            properties.append(Property(aliases: Set(building.properties.buildingIdentifierCandidates.map { "building:" + $0.lowercased() }), shape: shape))
        }
    }

    func uniquelyAssociates(_ point: CLLocationCoordinate2D, with target: FarmLiveAddressTarget) -> Bool {
        guard CLLocationCoordinate2DIsValid(point), let shape = FarmLiveAddressGeometry.PreparedShape(target.geometry) else { return false }
        let distance = shape.distance(to: point)
        guard distance.isFinite, distance <= 25 else { return false }
        let ownIDs = Set([target.parcelId.map { "parcel:" + $0.lowercased() },
                          target.buildingId.map { "building:" + $0.lowercased() }].compactMap { $0 })
        // Require actual target coverage in this snapshot, not an empty comparison set.
        guard properties.contains(where: { !$0.aliases.isDisjoint(with: ownIDs) }) else { return false }
        for property in properties where property.aliases.isDisjoint(with: ownIDs) {
            // Bounds cheaply discard distant properties before testing their edges.
            let box = property.shape.bounds
            let dx = max(box[0] - point.longitude, 0, point.longitude - box[2]) * 111_320 * cos(point.latitude * .pi / 180)
            let dy = max(box[1] - point.latitude, 0, point.latitude - box[3]) * 111_320
            if hypot(dx, dy) >= distance + 3 { continue }
            if property.shape.distance(to: point) < distance + 3 { return false }
        }
        return true
    }
}
