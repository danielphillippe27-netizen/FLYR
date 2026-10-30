import Foundation
import CoreLocation

struct CampaignMapLinkChoice: Identifiable {
    let addressID: String
    let buildingID: String
    let title: String
    var id: String { "\(addressID):\(buildingID)" }
}

struct CampaignMapEditProposal {
    var title: String
    var changes: [CampaignMapEditChange]
    var parcelID: String?
    var choices: [CampaignMapLinkChoice] = []
    var message: String
    var baseState: CampaignMapEditState?

    func choosing(_ choices: [CampaignMapLinkChoice]) -> Self {
        var result = self
        var values = Dictionary(changes.compactMap { change in change.value.map { (change.item, $0) } }, uniquingKeysWith: { _, last in last })
        for choice in choices {
            let item = CampaignMapItem(.address, choice.addressID)
            var value = values[item] ?? baseState?.features[item.id] ?? CampaignMapEditValue()
            value.buildingLinkSet = true; value.buildingId = choice.buildingID
            if let parcelID { value.parcelLinkSet = true; value.parcelId = parcelID }
            values[item] = value
        }
        result.changes = values.map { .init($0.key, value: $0.value) }.sorted { $0.item.id < $1.item.id }
        result.choices = []
        return result
    }
}

/// Every proposal is a single journal command, including relationship changes.
/// Geometry is exact field geometry, never a clipped vector-tile fragment.
enum CampaignMapEditPlanner {
    static func addressParcelLink(addressId: String, parcelId: String,
                                  coordinate: CLLocationCoordinate2D? = nil,
                                  buildingId: String? = nil,
                                  state: CampaignMapEditState, sourceRevision: String?) -> CampaignMapEditChange {
        let item = CampaignMapItem(.address, addressId)
        var value = CampaignMapEdits.value(for: item, in: state)
        value.parcelLinkSet = true
        value.parcelId = parcelId.lowercased()
        if let coordinate {
            value.geometry = .init(type: "Point", coordinates: .init(point: [coordinate.longitude, coordinate.latitude]))
        }
        if let buildingId {
            value.buildingLinkSet = true
            value.buildingId = buildingId.lowercased()
        }
        value.sourceRevision = sourceRevision
        return .init(item, value: value)
    }

    static func uniqueBuilding(on parcel: ParcelFeature, among buildings: [BuildingFeature]) -> BuildingFeature? {
        var found: BuildingFeature?
        for building in buildings {
            guard let center = center(building.geometry), contains(parcel.geometry, center),
                  buildingFits(building, parcel: parcel) else { continue }
            if found != nil { return nil }
            found = building
        }
        return found
    }
    /// Replace all placement relationships, including an explicit unlink when no parcel contains the point.
    static func addressPlacement(addressId: String, coordinate: CLLocationCoordinate2D,
                                 buildingId: String?, parcelId: String?, state: CampaignMapEditState,
                                 sourceRevision: String?) -> CampaignMapEditChange {
        let item = CampaignMapItem(.address, addressId)
        var value = CampaignMapEdits.value(for: item, in: state)
        value.geometry = .init(type: "Point", coordinates: .init(point: [coordinate.longitude, coordinate.latitude]))
        value.buildingLinkSet = true
        value.buildingId = buildingId?.lowercased()
        value.parcelLinkSet = true
        value.parcelId = parcelId?.lowercased()
        value.sourceRevision = sourceRevision
        return .init(item, value: value)
    }

    static func linkedBuilding(_ address: AddressFeature) -> String? {
        address.properties.buildingGersId ?? address.properties.linkedBuildingId
    }
    static func contains(_ geometry: MapFeatureGeoJSONGeometry, _ point: CLLocationCoordinate2D) -> Bool {
        guard let shape = geometry.nativeGeometry else { return false }
        return CanonicalParcelFieldGeometry.contains([point.longitude, point.latitude], in: shape)
    }
    static func center(_ geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        if let p = geometry.asPoint, p.count >= 2 { return .init(latitude: p[1], longitude: p[0]) }
        let rings = geometry.asPolygon ?? geometry.asMultiPolygon?.flatMap { $0 } ?? []
        guard let outer = rings.first, !outer.isEmpty else { return nil }
        let points = Array(outer.dropLast())
        guard !points.isEmpty, points.allSatisfy({ $0.count >= 2 }) else { return nil }
        return .init(latitude: points.reduce(0) { $0 + $1[1] } / Double(points.count),
                     longitude: points.reduce(0) { $0 + $1[0] } / Double(points.count))
    }
    static func containingParcel(_ point: CLLocationCoordinate2D, parcels: [ParcelFeature]) -> ParcelFeature? {
        let matches = parcels.filter { contains($0.geometry, point) }
        return matches.count == 1 ? matches[0] : nil
    }
    static func snapCoordinate(_ point: CLLocationCoordinate2D, parcels: [ParcelFeature], toleranceMeters: Double) -> CLLocationCoordinate2D {
        // A small screen-scaled tolerance helps with fingers at parcel edges.
        // Shared/overlapping edges stay ambiguous until the user moves inside.
        guard !parcels.contains(where: { contains($0.geometry, point) }), toleranceMeters > 0 else { return point }
        let scaleX = 111_320 * max(0.01, cos(point.latitude * .pi / 180))
        let scaleY = 111_320.0
        var candidates: [CLLocationCoordinate2D] = []
        for parcel in parcels {
            let polygons = parcel.geometry.asMultiPolygon ?? parcel.geometry.asPolygon.map { [$0] } ?? []
            var closest: (Double, Double, Double, Double, Double)?
            for ring in polygons.compactMap({ $0.first }) {
                guard ring.count > 1 else { continue }
                for i in 1..<ring.count where ring[i-1].count >= 2 && ring[i].count >= 2 {
                    let ax = (ring[i-1][0] - point.longitude) * scaleX, ay = (ring[i-1][1] - point.latitude) * scaleY
                    let dx = (ring[i][0] - ring[i-1][0]) * scaleX, dy = (ring[i][1] - ring[i-1][1]) * scaleY
                    let length2 = dx*dx + dy*dy
                    guard length2 > 0 else { continue }
                    let t = min(1, max(0, -(ax*dx + ay*dy) / length2))
                    let x = ax+t*dx, y = ay+t*dy, distance = hypot(x,y)
                    if distance <= toleranceMeters, closest == nil || distance < closest!.0 { closest = (distance,x,y,dx,dy) }
                }
            }
            if let (_,x,y,dx,dy) = closest {
                let length = hypot(dx,dy), inset = min(0.2,toleranceMeters/4)
                for direction in [1.0,-1.0] {
                    let target = CLLocationCoordinate2D(latitude:point.latitude+(y+direction*dx/length*inset)/scaleY,
                        longitude:point.longitude+(x-direction*dy/length*inset)/scaleX)
                    if contains(parcel.geometry,target) { candidates.append(target); break }
                }
            }
        }
        return candidates.count == 1 ? candidates[0] : point
    }
    static func buildingFits(_ building: BuildingFeature, parcel: ParcelFeature) -> Bool {
        let polygons = building.geometry.asMultiPolygon ?? building.geometry.asPolygon.map { [$0] } ?? []
        let outerPoints = polygons.compactMap { $0.first }.flatMap { $0 }
        guard !outerPoints.isEmpty && outerPoints.allSatisfy({ p in
            p.count >= 2 && contains(parcel.geometry, .init(latitude: p[1], longitude: p[0]))
        }) else { return false }
        let parcelPolygons = parcel.geometry.asMultiPolygon ?? parcel.geometry.asPolygon.map { [$0] } ?? []
        func side(_ a: [Double], _ b: [Double], _ p: [Double]) -> Double {
            (b[0]-a[0])*(p[1]-a[1]) - (b[1]-a[1])*(p[0]-a[0])
        }
        // Vertices alone are insufficient for concave parcels and holes.
        for ring in polygons.compactMap({ $0.first }) where ring.count > 1 {
            for i in 1..<ring.count {
                let a = ring[i-1], b = ring[i]
                guard a.count >= 2, b.count >= 2 else { return false }
                for boundary in parcelPolygons.flatMap({ $0 }) where boundary.count > 1 {
                    for j in 1..<boundary.count {
                        let c = boundary[j-1], d = boundary[j]
                        guard c.count >= 2, d.count >= 2 else { return false }
                        if side(a,b,c)*side(a,b,d) < 0 && side(c,d,a)*side(c,d,b) < 0 { return false }
                    }
                }
            }
        }
        for hole in parcelPolygons.flatMap({ Array($0.dropFirst()) }) {
            if let p = hole.first, p.count >= 2, contains(building.geometry,.init(latitude:p[1],longitude:p[0])) { return false }
        }
        return true
    }
    static func linkedAddresses(_ building: BuildingFeature, addresses: [AddressFeature]) -> [AddressFeature] {
        let ids = Set((building.properties.buildingIdentifierCandidates + [building.id].compactMap { $0 }).map { $0.lowercased() })
        let linkedIDs = Set(building.properties.addressUUIDs.map { $0.uuidString.lowercased() })
        return addresses.filter { address in
            if let target = linkedBuilding(address) { return ids.contains(target.lowercased()) }
            if address.properties.hasBuildingLink == false { return false }
            return linkedIDs.contains(CampaignMapEdits.addressItem(address).featureID)
        }
    }
    static func linkedAddresses(_ parcel: ParcelFeature, addresses: [AddressFeature], state: CampaignMapEditState) -> [AddressFeature] {
        let ids = Set([parcel.id, parcel.properties.id, parcel.properties.parcelId, parcel.properties.externalId].compactMap { $0?.lowercased() })
        let linked = Set(((parcel.properties.addressIds ?? []) + [parcel.properties.addressId].compactMap { $0 }).map { $0.lowercased() })
        return addresses.filter { address in
            let item = CampaignMapEdits.addressItem(address)
            if let value = state.features[item.id], value.parcelLinkSet == true {
                return value.parcelId.map { ids.contains($0.lowercased()) } == true
            }
            let explicit = address.properties.parcelId ?? address.properties.campaignParcelId
            if let explicit { return ids.contains(explicit.lowercased()) }
            if linked.contains(item.featureID) { return true }
            return center(address.geometry).map { contains(parcel.geometry, $0) } == true
        }
    }
    static func deletion(_ items: Set<CampaignMapItem>, snapshot: CampaignMapEditSnapshot, state: CampaignMapEditState) throws -> CampaignMapEditProposal {
        guard !items.isEmpty, items.count <= 500 else { throw CampaignMapEditError.invalidSelection }
        var values: [CampaignMapItem: CampaignMapEditValue] = [:]
        for item in items {
            var value = CampaignMapEdits.value(for: item, in: state)
            value.hidden = true
            values[item] = value
        }
        for building in snapshot.buildings where items.contains(CampaignMapEdits.buildingItem(building)) {
            for address in linkedAddresses(building, addresses: snapshot.addresses) {
                let item = CampaignMapEdits.addressItem(address)
                var value = values[item] ?? CampaignMapEdits.value(for: item, in: state)
                value.buildingLinkSet = true; value.buildingId = nil
                values[item] = value
            }
        }
        for parcel in snapshot.parcels where items.contains(CampaignMapEdits.parcelItem(parcel)) {
            let parcelIDs = Set([parcel.id, parcel.properties.id, parcel.properties.parcelId, parcel.properties.externalId].compactMap { $0?.lowercased() })
            for address in linkedAddresses(parcel, addresses: snapshot.addresses, state: state) {
                let item = CampaignMapEdits.addressItem(address)
                var value = values[item] ?? CampaignMapEdits.value(for: item, in: state)
                value.parcelLinkSet = true; value.parcelId = nil
                values[item] = value
            }
            for building in snapshot.buildings {
                let item = CampaignMapEdits.buildingItem(building)
                guard let old = state.features[item.id], old.parcelLinkSet == true,
                      old.parcelId.map({ parcelIDs.contains($0.lowercased()) }) == true else { continue }
                var value = values[item] ?? old
                value.parcelLinkSet = true; value.parcelId = nil
                values[item] = value
            }
        }
        if values.count > 500 {
            // A large apartment building can have thousands of addresses. Its
            // campaign tombstone also clears all effective links on read, so
            // the batch can remain small without dropping or deleting units.
            values = values.filter { items.contains($0.key) }
        }
        return .init(title: "Remove \(items.count) map item\(items.count == 1 ? "" : "s")",
            changes: values.map { .init($0.key, value: $0.value) }.sorted { $0.item.id < $1.item.id },
            message: "Removed from this campaign. Linked addresses, contacts, and visits are preserved.")
    }
    static func unlink(_ address: AddressFeature, state: CampaignMapEditState) -> CampaignMapEditProposal {
        let item = CampaignMapEdits.addressItem(address)
        var value = CampaignMapEdits.value(for: item, in: state)
        value.buildingLinkSet = true; value.buildingId = nil
        return .init(title: "Unlink address", changes: [.init(item, value: value)],
            message: "Address unlinked. Its location and parcel link are preserved.")
    }
    static func movement(_ item: CampaignMapItem, geometry: MapFeatureGeoJSONGeometry, deltaLatitude: Double, deltaLongitude: Double,
                         moveLinked: Bool, snapshot: CampaignMapEditSnapshot, state: CampaignMapEditState, sourceRevision: String?) throws -> CampaignMapEditProposal {
        var values: [CampaignMapItem: CampaignMapEditValue] = [:]
        var value = CampaignMapEdits.value(for: item, in: state)
        value.geometry = geometry; value.sourceRevision = sourceRevision
        var proposal = CampaignMapEditProposal(title: "Move \(item.kind.rawValue)", changes: [], message: "\(item.kind.title) moved.")
        proposal.baseState = state
        switch item.kind {
        case .address:
            guard let coordinate = center(geometry) else { throw CampaignMapEditError.invalidSelection }
            let parcel = containingParcel(coordinate, parcels: snapshot.parcels)
            proposal.parcelID = parcel.map { CampaignMapEdits.parcelItem($0).featureID }
            value.parcelLinkSet = true; value.parcelId = proposal.parcelID
            value.buildingLinkSet = true; value.buildingId = nil
            let underPoint = snapshot.buildings.filter { contains($0.geometry, coordinate) }
            let candidates = underPoint.count == 1 ? underPoint :
                (parcel.map { p in snapshot.buildings.filter { buildingFits($0, parcel: p) } } ?? [])
            if candidates.count == 1, let building = candidates.first {
                value.buildingId = CampaignMapEdits.buildingItem(building).featureID
                proposal.message = "Address linked to the building\(parcel == nil ? "" : " and parcel")."
            } else if candidates.count > 1 {
                proposal.choices = candidates.map { building in
                    .init(addressID: item.featureID, buildingID: CampaignMapEdits.buildingItem(building).featureID,
                          title: building.properties.addressText ?? building.properties.canonicalBuildingIdentifier ?? "Building")
                }
                proposal.message = "Choose a building, or keep the address unlinked."
            } else { proposal.message = parcel == nil ? "Address moved and left unlinked." : "Address linked to the parcel." }
        case .building:
            guard let original = snapshot.buildings.first(where: { CampaignMapEdits.buildingItem($0) == item }), let coordinate = center(geometry) else { throw CampaignMapEditError.invalidSelection }
            let movedFeature = BuildingFeature(type: original.type, id: original.id, geometry: geometry, properties: original.properties)
            let parcel = containingParcel(coordinate, parcels: snapshot.parcels).flatMap { buildingFits(movedFeature, parcel: $0) ? $0 : nil }
            proposal.parcelID = parcel.map { CampaignMapEdits.parcelItem($0).featureID }
            value.parcelLinkSet = true; value.parcelId = proposal.parcelID
            let linked = linkedAddresses(original, addresses: snapshot.addresses)
            if moveLinked {
                for address in linked {
                    let addressItem = CampaignMapEdits.addressItem(address)
                    var v = CampaignMapEdits.value(for: addressItem, in: state)
                    v.geometry = CampaignMapEdits.translated(address.geometry, latitude: deltaLatitude, longitude: deltaLongitude)
                    v.buildingLinkSet = true; v.buildingId = item.featureID
                    let movedPoint = v.geometry.flatMap(center)
                    v.parcelLinkSet = true
                    v.parcelId = movedPoint.flatMap { containingParcel($0, parcels: snapshot.parcels) }.map { CampaignMapEdits.parcelItem($0).featureID }
                    values[addressItem] = v
                }
            }
            if let parcel, linked.isEmpty {
                let candidates = linkedAddresses(parcel, addresses: snapshot.addresses, state: state).filter { address in
                    linkedBuilding(address) == nil && state.features[CampaignMapEdits.addressItem(address).id]?.buildingLinkSet != true
                }
                if candidates.count == 1, let address = candidates.first {
                    let addressItem = CampaignMapEdits.addressItem(address)
                    var v = CampaignMapEdits.value(for: addressItem, in: state)
                    v.buildingLinkSet = true; v.buildingId = item.featureID
                    v.parcelLinkSet = true; v.parcelId = proposal.parcelID
                    values[addressItem] = v
                    proposal.message = "Building linked to the address and parcel."
                } else if candidates.count > 1 {
                    proposal.choices = candidates.map { .init(addressID: CampaignMapEdits.addressItem($0).featureID,
                        buildingID: item.featureID, title: $0.properties.formatted ?? "Address") }
                }
            }
        case .parcel:
            guard let parcel = snapshot.parcels.first(where: { CampaignMapEdits.parcelItem($0) == item }) else { throw CampaignMapEditError.invalidSelection }
            if moveLinked {
                for address in linkedAddresses(parcel, addresses: snapshot.addresses, state: state) {
                    let addressItem = CampaignMapEdits.addressItem(address)
                    var v = CampaignMapEdits.value(for: addressItem, in: state)
                    v.geometry = CampaignMapEdits.translated(address.geometry, latitude: deltaLatitude, longitude: deltaLongitude)
                    v.parcelLinkSet = true; v.parcelId = item.featureID
                    values[addressItem] = v
                }
                for building in snapshot.buildings {
                    let buildingItem = CampaignMapEdits.buildingItem(building)
                    let existing = state.features[buildingItem.id]
                    let belongs = existing?.parcelLinkSet == true ? existing?.parcelId == item.featureID : buildingFits(building, parcel: parcel)
                    guard belongs else { continue }
                    var v = CampaignMapEdits.value(for: buildingItem, in: state)
                    v.geometry = CampaignMapEdits.translated(building.geometry, latitude: deltaLatitude, longitude: deltaLongitude)
                    v.parcelLinkSet = true; v.parcelId = item.featureID
                    values[buildingItem] = v
                    // A building's address can be plotted at the curb, outside
                    // the parcel. Move the linked family together as requested.
                    for address in linkedAddresses(building, addresses: snapshot.addresses) {
                        let addressItem = CampaignMapEdits.addressItem(address)
                        var linked = values[addressItem] ?? CampaignMapEdits.value(for: addressItem, in: state)
                        linked.geometry = CampaignMapEdits.translated(address.geometry, latitude: deltaLatitude, longitude: deltaLongitude)
                        linked.parcelLinkSet = true; linked.parcelId = item.featureID
                        values[addressItem] = linked
                    }
                }
            }
        }
        values[item] = value
        guard values.count <= 500 else { throw CampaignMapEditError.unavailable("This move includes too many linked items. Move them in smaller groups.") }
        proposal.changes = values.map { .init($0.key, value: $0.value) }.sorted { $0.item.id < $1.item.id }
        return proposal
    }
}
