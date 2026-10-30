import Foundation
import CoreLocation

enum CampaignMapItemKind: String, Codable, CaseIterable {
    case address, building, parcel
    var title: String { rawValue.capitalized }
}

struct CampaignMapItem: Codable, Hashable, Identifiable {
    let kind: CampaignMapItemKind
    let featureID: String
    var id: String { "\(kind.rawValue):\(featureID)" }
    init(_ kind: CampaignMapItemKind, _ id: String) {
        self.kind = kind
        featureID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct CampaignMapEditValue: Codable, Equatable {
    var hidden: Bool?
    var geometry: MapFeatureGeoJSONGeometry?
    // A set flag with no ID is an intentional unlink, not a missing match.
    var buildingLinkSet: Bool?
    var buildingId: String?
    var parcelLinkSet: Bool?
    var parcelId: String?
    var sourceRevision: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hidden == rhs.hidden && lhs.geometry?.nativeGeometry == rhs.geometry?.nativeGeometry &&
        lhs.buildingLinkSet == rhs.buildingLinkSet && lhs.buildingId == rhs.buildingId &&
        lhs.parcelLinkSet == rhs.parcelLinkSet && lhs.parcelId == rhs.parcelId && lhs.sourceRevision == rhs.sourceRevision
    }
}

struct CampaignMapEditChange: Codable, Equatable {
    let kind: CampaignMapItemKind
    let id: String
    let value: CampaignMapEditValue?
    var item: CampaignMapItem { CampaignMapItem(kind, id) }
    init(_ item: CampaignMapItem, value: CampaignMapEditValue?) { kind = item.kind; id = item.featureID; self.value = value }
    enum CodingKeys: String, CodingKey { case kind, id, value }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(id, forKey: .id)
        // Null removes an override atomically and is required for undo.
        try c.encode(value, forKey: .value)
    }
}

struct CampaignMapEditState: Codable, Equatable {
    var revision = 0
    var features: [String: CampaignMapEditValue] = [:]
    var conflict: Bool?
    func applying(_ changes: [CampaignMapEditChange]) -> Self {
        var result = self
        for change in changes { result.features[change.item.id] = change.value }
        return result
    }
}

struct CampaignMapEditRequest: Codable {
    var clientMutationId: String
    var baseRevision: Int
    var changes: [CampaignMapEditChange]
}

struct CampaignMapEditCommand: Codable {
    var request: CampaignMapEditRequest
    let title: String
    let previous: [CampaignMapEditChange]
}

struct CampaignMapEditArchive: Codable {
    var scope: String?
    var campaignId: String?
    var server = CampaignMapEditState()
    var pending: [CampaignMapEditCommand] = []
    var history: [CampaignMapEditCommand] = []
    var effective: CampaignMapEditState { pending.reduce(server) { $0.applying($1.request.changes) } }
}

struct CampaignMapEditSnapshot {
    let buildings: [BuildingFeature]
    let addresses: [AddressFeature]
    let parcels: [ParcelFeature]
}

struct CampaignMapEditorDrag {
    let item: CampaignMapItem
    let geometry: MapFeatureGeoJSONGeometry
    let start: CLLocationCoordinate2D
    let snapshot: CampaignMapEditSnapshot
    let state: CampaignMapEditState
}

struct PendingCampaignMapEditProposal: Identifiable {
    let id = UUID()
    let proposal: CampaignMapEditProposal
}

enum CampaignMapEditError: LocalizedError {
    case unavailable(String), conflict, changedSinceUndo, invalidSelection
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .conflict: return "A teammate changed the same map item. Review the changes before syncing."
        case .changedSinceUndo: return "This item changed since your last edit. Review it before undoing."
        case .invalidSelection: return "Select between 1 and 500 map items."
        }
    }
}

/// Pure corrections logic shared by rendering, hit testing, and field targets.
enum CampaignMapEdits {
    static func validGeometry(_ geometry: MapFeatureGeoJSONGeometry, for kind: CampaignMapItemKind) -> Bool {
        func point(_ p: [Double]) -> Bool { p.count == 2 && p.allSatisfy(\.isFinite) && abs(p[0]) <= 180 && abs(p[1]) <= 90 }
        func polygon(_ rings: [[[Double]]]) -> Bool {
            !rings.isEmpty && rings.allSatisfy { ring in ring.count >= 4 && ring.allSatisfy(point) && ring.first == ring.last }
        }
        if kind == .address { return geometry.type == "Point" && geometry.asPoint.map(point) == true }
        if let rings = geometry.asPolygon, geometry.type == "Polygon" { return polygon(rings) }
        if let polygons = geometry.asMultiPolygon, geometry.type == "MultiPolygon" { return !polygons.isEmpty && polygons.allSatisfy(polygon) }
        return false
    }
    static func buildingItem(_ feature: BuildingFeature) -> CampaignMapItem {
        CampaignMapItem(.building, feature.properties.canonicalBuildingIdentifier ?? feature.id ?? feature.properties.id)
    }
    static func addressItem(_ feature: AddressFeature) -> CampaignMapItem {
        CampaignMapItem(.address, feature.properties.id ?? feature.id ?? "")
    }
    static func parcelItem(_ feature: ParcelFeature) -> CampaignMapItem {
        CampaignMapItem(.parcel, feature.properties.parcelId ?? feature.properties.externalId ?? feature.id ?? feature.properties.id ?? "")
    }
    static func value(for item: CampaignMapItem, in state: CampaignMapEditState) -> CampaignMapEditValue {
        state.features[item.id] ?? CampaignMapEditValue()
    }
    static func patch<P: Codable>(_ properties: P, _ changes: [String: Any]) -> P {
        // Preserve every metadata field, including parcel links and label hints.
        guard let data = try? JSONEncoder().encode(properties),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return properties }
        object.merge(changes) { _, new in new }
        guard let output = try? JSONSerialization.data(withJSONObject: object),
              let result = try? JSONDecoder().decode(P.self, from: output) else { return properties }
        return result
    }
    static func snapshot(buildings: [BuildingFeature], addresses: [AddressFeature], parcels: [ParcelFeature], state: CampaignMapEditState) -> CampaignMapEditSnapshot {
        guard !state.features.isEmpty else { return .init(buildings: buildings, addresses: addresses, parcels: parcels) }
        let hiddenBuildingIDs = Set(buildings.filter { state.features[buildingItem($0).id]?.hidden == true }
            .flatMap { $0.properties.buildingIdentifierCandidates + [$0.id].compactMap { $0 } }.map { $0.lowercased() })
            .union(state.features.compactMap { $0.key.hasPrefix("building:") && $0.value.hidden == true ? String($0.key.dropFirst(9)) : nil })
        let hiddenParcelIDs = Set(parcels.filter { state.features[parcelItem($0).id]?.hidden == true }.flatMap {
            [$0.id, $0.properties.id, $0.properties.parcelId, $0.properties.externalId].compactMap { $0?.lowercased() }
        }).union(state.features.compactMap { $0.key.hasPrefix("parcel:") && $0.value.hidden == true ? String($0.key.dropFirst(7)) : nil })
        let effectiveAddresses = addresses.compactMap { feature -> AddressFeature? in
            let value = state.features[addressItem(feature).id]
            guard value?.hidden != true else { return nil }
            var changes: [String: Any] = [:]
            let linked = value?.buildingLinkSet == true ? value?.buildingId : (feature.properties.buildingGersId ?? feature.properties.linkedBuildingId)
            if value?.buildingLinkSet == true || linked.map({ hiddenBuildingIDs.contains($0.lowercased()) }) == true {
                let id = value?.buildingId.flatMap { hiddenBuildingIDs.contains($0.lowercased()) ? nil : $0 }
                changes["building_gers_id"] = id as Any? ?? NSNull()
                changes["linked_building_id"] = id as Any? ?? NSNull()
                changes["has_building_link"] = id != nil
            }
            let parcel = value?.parcelLinkSet == true ? value?.parcelId : (feature.properties.parcelId ?? feature.properties.campaignParcelId)
            if value?.parcelLinkSet == true || parcel.map({ hiddenParcelIDs.contains($0.lowercased()) }) == true {
                let id = value?.parcelId.flatMap { hiddenParcelIDs.contains($0.lowercased()) ? nil : $0 }
                changes["parcel_id"] = id as Any? ?? NSNull()
                changes["campaign_parcel_id"] = id as Any? ?? NSNull()
                changes["has_parcel_link"] = id != nil
            }
            if value?.geometry != nil {
                changes["label_anchor_lon"] = NSNull(); changes["label_anchor_lat"] = NSNull()
                changes["pin_placement"] = "address"
            }
            return AddressFeature(type: feature.type, id: feature.id, geometry: value?.geometry ?? feature.geometry,
                properties: changes.isEmpty ? feature.properties : patch(feature.properties, changes))
        }
        let addressByID = Dictionary(effectiveAddresses.map { (addressItem($0).featureID, $0) }, uniquingKeysWith: { first, _ in first })
        var addedBuildingLinks: [String: [String]] = [:]
        var addedParcelLinks: [String: [String]] = [:]
        for address in effectiveAddresses {
            let id = addressItem(address).featureID
            if let building = address.properties.buildingGersId ?? address.properties.linkedBuildingId {
                addedBuildingLinks[building.lowercased(), default: []].append(id)
            }
            if let parcel = address.properties.parcelId ?? address.properties.campaignParcelId {
                addedParcelLinks[parcel.lowercased(), default: []].append(id)
            }
        }
        func linkedIDs(_ existing: [String], additions: [String], kind: CampaignMapItemKind, aliases: Set<String>) -> [String] {
            var result = Set(additions)
            for id in existing.map({ $0.lowercased() }) {
                guard addressByID[id] != nil else { continue }
                let v = state.features[CampaignMapItem(.address, id).id]
                if kind == .building, v?.buildingLinkSet == true {
                    if let target = v?.buildingId, aliases.contains(target.lowercased()) { result.insert(id) }
                } else if kind == .parcel, v?.parcelLinkSet == true {
                    if let target = v?.parcelId, aliases.contains(target.lowercased()) { result.insert(id) }
                } else { result.insert(id) }
            }
            return result.sorted()
        }
        let effectiveBuildings = buildings.compactMap { feature -> BuildingFeature? in
            let v = state.features[buildingItem(feature).id]
            guard v?.hidden != true else { return nil }
            let aliases = Set((feature.properties.buildingIdentifierCandidates + [feature.id].compactMap { $0 }).map { $0.lowercased() })
            let old = feature.properties.addressIds + [feature.properties.addressId].compactMap { $0 }
            let additions = aliases.flatMap { addedBuildingLinks[$0] ?? [] }
            let ids = linkedIDs(old, additions: additions, kind: .building, aliases: aliases)
            let changed = Set(old.map { $0.lowercased() }) != Set(ids)
            var properties = feature.properties
            if changed {
                var changes: [String: Any] = ["address_ids": ids, "address_id": ids.first as Any? ?? NSNull(),
                    "address_count": ids.count, "is_linked": !ids.isEmpty]
                if let first = ids.first.flatMap({ addressByID[$0] }) {
                    changes["address_text"] = first.properties.formatted as Any? ?? NSNull()
                    changes["house_number"] = first.properties.houseNumber as Any? ?? NSNull()
                    changes["street_name"] = first.properties.streetName as Any? ?? NSNull()
                } else {
                    for key in ["address_text", "house_number", "street_name"] { changes[key] = NSNull() }
                }
                properties = patch(properties, changes)
            }
            return BuildingFeature(type: feature.type, id: feature.id, geometry: v?.geometry ?? feature.geometry, properties: properties)
        }
        let effectiveParcels = parcels.compactMap { feature -> ParcelFeature? in
            let v = state.features[parcelItem(feature).id]
            guard v?.hidden != true else { return nil }
            let aliases = Set([feature.id, feature.properties.id, feature.properties.parcelId, feature.properties.externalId].compactMap { $0?.lowercased() })
            let old = (feature.properties.addressIds ?? []) + [feature.properties.addressId].compactMap { $0 }
            let ids = linkedIDs(old, additions: aliases.flatMap { addedParcelLinks[$0] ?? [] }, kind: .parcel, aliases: aliases)
            let unchanged = Set(old.map { $0.lowercased() }) == Set(ids)
            let properties = unchanged ? feature.properties : patch(feature.properties, ["address_ids": ids, "address_id": ids.first as Any? ?? NSNull()])
            return ParcelFeature(type: feature.type, id: feature.id, geometry: v?.geometry ?? feature.geometry, properties: properties)
        }
        return .init(buildings: effectiveBuildings, addresses: effectiveAddresses, parcels: effectiveParcels)
    }

    static func translated(_ geometry: MapFeatureGeoJSONGeometry, latitude: Double, longitude: Double) -> MapFeatureGeoJSONGeometry? {
        func point(_ p: [Double]) -> [Double] { p.count < 2 ? p : [p[0] + longitude, p[1] + latitude] }
        if let p = geometry.asPoint { return .init(type: "Point", coordinates: .init(point: point(p))) }
        if let rings = geometry.asPolygon { return .init(type: "Polygon", coordinates: .init(polygon: rings.map { $0.map(point) })) }
        if let polygons = geometry.asMultiPolygon { return .init(type: "MultiPolygon", coordinates: .init(multiPolygon: polygons.map { $0.map { $0.map(point) } })) }
        return nil
    }
}
