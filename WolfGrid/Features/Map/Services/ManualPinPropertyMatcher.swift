import Foundation
import CoreLocation

/// Keeps the field record (and its history) while adopting a verified property's
/// geometry. A duplicate source row is only hidden after separate activity checks.
enum ManualPinPropertyMatcher {
    static func isUnlinkedFieldRecord(_ feature: AddressFeature) -> Bool {
        if MapLayerManager.isManualPinAddressFeature(feature) { return true }
        let p = feature.properties
        // Older field pins were stored as ordinary manual addresses with only
        // a parcel link, before the dedicated manual_pin source was introduced.
        return p.source?.lowercased() == "manual" && p.featureType != "address" &&
            p.hasBuildingLink != true && p.buildingGersId == nil && p.linkedBuildingId == nil
    }

    struct Match {
        let pinID: UUID
        let addressID: UUID
        let coordinate: CLLocationCoordinate2D
        let buildingID: String?
        let parcelID: String?
    }

    static func matches(addresses: [AddressFeature], buildings: [BuildingFeature],
                        parcels: [ParcelFeature], state: CampaignMapEditState) -> [Match] {
        func identity(_ feature: AddressFeature) -> String? {
            let p = feature.properties
            return AddressMatcher.identity(houseNumber: p.houseNumber, streetName: p.streetName,
                                           formatted: p.formatted, unit: p.unit)
        }
        func isPin(_ feature: AddressFeature) -> Bool {
            isUnlinkedFieldRecord(feature)
        }
        let available = addresses.filter { state.features[CampaignMapEdits.addressItem($0).id]?.hidden != true }
        let byIdentity = Dictionary(grouping: available.filter { !isPin($0) }.compactMap { address in
            identity(address).map { ($0, address) }
        }, by: { $0.0 })
        var result: [Match] = []
        for pin in available where isPin(pin) {
            let item = CampaignMapEdits.addressItem(pin)
            let edit = state.features[item.id]
            // Explicit moves/unlinks, including undoable earlier corrections, win.
            guard edit?.geometry == nil, edit?.buildingLinkSet != true, edit?.parcelLinkSet != true,
                  let pinID = UUID(uuidString: item.featureID), let key = identity(pin),
                  let origin = CampaignTargetResolver.coordinate(for: pin.geometry) else { continue }
            let candidates = (byIdentity[key] ?? []).compactMap { _, address -> Match? in
                guard let addressID = UUID(uuidString: CampaignMapEdits.addressItem(address).featureID),
                      addressID != pinID,
                      state.features[CampaignMapEdits.addressItem(address).id] == nil,
                      let point = CampaignTargetResolver.coordinate(for: address.geometry),
                      CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                        .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) <= 40 else { return nil }
                let buildingID = address.properties.buildingGersId ?? address.properties.linkedBuildingId
                let linkedBuilding = buildings.first { feature in
                    buildingID.map { id in feature.properties.buildingIdentifierCandidates.contains { $0.lowercased() == id.lowercased() } } == true ||
                    (buildingID == nil && feature.properties.addressUUIDs.contains(addressID))
                }
                let parcelID = address.properties.parcelId ?? address.properties.campaignParcelId
                let linkedParcels = parcels.filter { feature in
                    let aliases = [feature.id, feature.properties.id, feature.properties.parcelId, feature.properties.externalId].compactMap { $0?.lowercased() }
                    return parcelID.map { aliases.contains($0.lowercased()) } == true ||
                        (parcelID == nil && ((feature.properties.addressIds ?? []) + [feature.properties.addressId].compactMap { $0 }).contains { $0.lowercased() == addressID.uuidString.lowercased() })
                }
                let parcel = linkedParcels.count == 1 ? linkedParcels.first : CampaignMapEditPlanner.containingParcel(point, parcels: parcels)
                let building = linkedBuilding ?? parcel.flatMap { CampaignMapEditPlanner.uniqueBuilding(on: $0, among: buildings) }
                if let building, let parcel, !CampaignMapEditPlanner.buildingFits(building, parcel: parcel) { return nil }
                // The address text alone is insufficient: the dropped point must
                // be inside the same known building or parcel.
                guard building.map({ CampaignMapEditPlanner.contains($0.geometry, origin) }) == true ||
                        parcel.map({ CampaignMapEditPlanner.contains($0.geometry, origin) }) == true else { return nil }
                guard building.map({ CampaignMapEditPlanner.contains($0.geometry, point) }) == true ||
                        parcel.map({ CampaignMapEditPlanner.contains($0.geometry, point) }) == true else { return nil }
                return Match(pinID: pinID, addressID: addressID, coordinate: point,
                             buildingID: building?.properties.canonicalBuildingIdentifier,
                             parcelID: parcel.map { CampaignMapEdits.parcelItem($0).featureID })
            }
            guard candidates.count == 1, let match = candidates.first else { continue }
            result.append(match)
        }
        // Two field records for one home need a history-aware merge; do not pick
        // one arbitrarily or hide the shared source row twice.
        let counts = Dictionary(grouping: result, by: \.addressID)
        return result.filter { counts[$0.addressID]?.count == 1 }
    }

    static func changes(for matches: [Match], unusedAddressIDs: Set<UUID>,
                        state: CampaignMapEditState, sourceRevision: String?) -> [CampaignMapEditChange] {
        matches.filter { unusedAddressIDs.contains($0.addressID) }.flatMap { match in
            let placement = CampaignMapEditPlanner.addressPlacement(addressId: match.pinID.uuidString,
                coordinate: match.coordinate, buildingId: match.buildingID, parcelId: match.parcelID,
                state: state, sourceRevision: sourceRevision)
            let duplicate = CampaignMapItem(.address, match.addressID.uuidString)
            var value = CampaignMapEdits.value(for: duplicate, in: state)
            value.hidden = true
            return [placement, CampaignMapEditChange(duplicate, value: value)]
        }
    }
}
