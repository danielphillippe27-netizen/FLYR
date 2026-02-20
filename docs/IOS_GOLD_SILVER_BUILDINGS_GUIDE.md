# iOS Guide: Gold & Silver Building Data

> **Audience**: iOS developer working on FLYR PRO  
> **Last Updated**: 2026-02-18  
> **Status**: Reflects the live codebase as of the Gold integration PR

---

## What Are Gold and Silver?

| Tier | Source | How buildings are matched to addresses |
|------|--------|----------------------------------------|
| **Gold** | `ref_buildings_gold` (Overture Maps polygons imported directly into Supabase) | `campaign_addresses.building_id` → `ref_buildings_gold.id` (FK written by the spatial linker `link_campaign_addresses_all`) |
| **Silver** | `buildings` table + S3 snapshot / Lambda pipeline | `building_address_links.building_id` → `buildings.id`, then lookup in `campaign_addresses.building_gers_id` |
| **Fallback (address_point)** | No polygon found | RPC returns the address as a **Point** feature; rendered as a coloured 3D circle |

Gold is the **preferred path**. When a campaign has Gold polygons, the RPC returns them directly. If not, the app falls back to Silver (S3 snapshot). If neither has polygons, address points are rendered as circles.

---

## 1. Data Flow

```
rpc_get_campaign_full_features
         │
         ├─ returns Polygon/MultiPolygon features  ──► Gold or Silver buildings
         │         source = "gold" | "silver"
         │
         └─ returns Point features                 ──► address_point fallback
                   source = "address_point"
                            │
         ┌───────────────────────────────────────────────────────┐
         │         MapFeaturesService.partitionFeaturesByGeometry │
         └───────────────────────────────────────────────────────┘
                  │                          │
           Polygons → self.buildings   Points → self.addresses (merged)
                  │
        (if still empty)
                  │
         BuildingLinkService.fetchBuildings()   ← Silver S3 snapshot fallback
                  │
        (if still empty)
                  │
         fetchBuildingsForAddressesFallback()   ← Edge Function / closest-home
```

---

## 2. Feature Properties Reference

All features (Gold, Silver, address_point) share the same `BuildingProperties` shape after decoding. Optional fields are populated when available.

```swift
struct BuildingProperties: Codable {
    // Always present
    let id: String              // feature UUID
    let status: String          // "not_visited" | "visited" | "hot"
    let scansTotal: Int         // QR scan count
    let height: Double          // extrusion height (default 10 m)

    // Present when linked to an address
    let addressId: String?      // campaign_addresses.id
    let addressText: String?    // full formatted address
    let houseNumber: String?    // "123"
    let streetName: String?     // "Main St"

    // Present for all tiers
    let gersId: String?         // Gold: ref_buildings_gold.id  Silver: Overture GERS ID
    let buildingId: String?     // same as id for most features
    let matchMethod: String?    // "gold_exact" | "gold_proximity" | "containment_verified" | "proximity_verified"

    // Gold / address_point specific
    let source: String?         // "gold" | "silver" | "address_point"
    let confidence: Double?     // 0.5 – 1.0
    let qrScanned: Bool?        // true when scans_total > 0
    let heightM: Double?        // same as height, from height_m column

    var statusColor: String {
        if scansTotal > 0 || (qrScanned ?? false) { return "#8b5cf6" } // Purple
        switch status {
        case "hot":     return "#3b82f6" // Blue
        case "visited": return "#22c55e" // Green
        default:        return "#ef4444" // Red
        }
    }
}
```

---

## 3. Fetching Buildings

Call `MapFeaturesService.fetchAllCampaignFeatures(campaignId:)` — that's the only entry point you need. It handles everything:

```swift
await MapFeaturesService.shared.fetchAllCampaignFeatures(campaignId: campaign.id.uuidString)
// After this:
//   .buildings  → BuildingFeatureCollection  (Polygon/MultiPolygon only)
//   .addresses  → AddressFeatureCollection   (Point features, incl. Gold address_point fallbacks)
//   .roads      → RoadFeatureCollection
```

Internally it runs in this order:

1. `rpc_get_campaign_full_features` — Gold + Silver + address_point in one call
2. Partition by geometry type (polygons → buildings, points → merged into addresses)
3. If still no polygons → `BuildingLinkService.fetchBuildings()` (S3 snapshot)
4. If still no polygons but have addresses → `fetchBuildingsForAddressesFallback()` (Edge Function)

**You never need to call the Silver S3 or Edge Function paths directly — the service handles it.**

---

## 4. Rendering on the Map

`MapLayerManager` handles all rendering. No changes needed for Gold/Silver — the layer setup is geometry-type based:

| Geometry | Layer | Visual |
|----------|-------|--------|
| Polygon / MultiPolygon | `buildings-extrusion` (FillExtrusionLayer) | 3D building footprint |
| Point (address_point) | `campaign-address-points-extrusion` (converted to circle polygon) | 3D coloured pillar |

After fetching, update the map:
```swift
// In CampaignMapView.updateMapData()
manager.updateBuildings(featuresService.buildingsAsGeoJSONData())
manager.updateAddresses(featuresService.addressesAsGeoJSONData())
manager.updateRoads(featuresService.roadsAsGeoJSONData())
```

`updateBuildings()` already **filters non-polygon geometry** before pushing to the Mapbox source, so Point features in the buildings collection are silently ignored — they go through the addresses pipeline instead.

---

## 5. Status Colors (Priority Order)

The color expressions in `MapLayerManager` and `BuildingProperties.statusColor` both follow this priority:

| Priority | Color | Hex | Condition |
|----------|-------|-----|-----------|
| 1 | Purple | `#8b5cf6` | `scans_total > 0` OR `qr_scanned == true` |
| 2 | Blue | `#3b82f6` | `status == "hot"` |
| 3 | Green | `#22c55e` | `status == "visited"` |
| 4 | Red | `#ef4444` | Default / `status == "not_visited"` |

Colors are driven by Mapbox feature-state expressions (live, no re-render needed). Real-time updates come through `BuildingStatsSubscriber` and call `setFeatureState()`.

---

## 6. Building Tap → Address Resolution

When a user taps a building, `CampaignMapView.resolveAddressForBuilding()` runs the following chain. **Stop at the first hit.**

```
Step 0  Fast path (Gold/address_point)
        building.source == "gold" || "address_point"
        AND building.addressId != nil
        → Build AddressTapResult directly from feature properties
          (no network call needed — address is already in the feature)

Step 1  Match by building.addressId against address feature collection
        (existing Silver match via campaign_addresses.id)

Step 2  Match building GERS IDs against address.building_gers_id
        (Silver / legacy GERS matching)

Step 3  Match building.addressText against address.formatted text
        (fuzzy text fallback)
```

`BuildingDataService.fetchBuildingData()` runs a deeper DB resolution chain when the card opens:

```
Step 0   Direct lookup by addressId (if feature carried it)
Step 1   campaign_addresses WHERE gers_id = gersId OR building_gers_id = gersId
Step 1b  Gold FK: campaign_addresses WHERE building_id = gersId   ← NEW
Step 2   building_address_links (Silver join table) via buildings.id UUID
Step 3   API: GET /api/campaigns/{id}/buildings/{id}/addresses
```

---

## 7. Identifying Gold vs Silver at Runtime

Check `building.source` on any `BuildingProperties`:

```swift
switch building.source {
case "gold":
    // Polygon from ref_buildings_gold; address linked via building_id FK
    // address details already in feature: addressText, houseNumber, streetName

case "silver":
    // Polygon from buildings table (Overture via S3 snapshot)
    // address linked via building_address_links join table

case "address_point":
    // No polygon — address rendered as a 3D circle
    // address details already in feature: addressText, houseNumber, streetName

case nil:
    // Legacy / pre-Gold data; treat as Silver
}
```

For the confidence/match quality badge on the location card:

```swift
switch building.matchMethod {
case "gold_exact":       // Exact address match on Gold polygon
case "gold_proximity":   // Proximity match on Gold polygon
case "containment_verified": // Point inside Silver polygon (high confidence)
case "proximity_verified":   // Nearby Silver polygon (lower confidence)
}
// building.confidence is 0.5–1.0 — use for a visual indicator if needed
```

---

## 8. What Each Layer Shows

| Display mode | Buildings layer | Addresses layer |
|---|---|---|
| **Buildings** (default) | Visible — 3D polygons | Hidden |
| **Addresses** | Hidden | Visible — 3D circle pillars |

Toggled by `BuildingCircleToggle` in `CampaignMapView`. Address_point fallbacks (Gold campaigns with no polygon match) appear in the **addresses layer** since they are Point geometry that got routed there during partition.

---

## 9. Debugging Checklist

| Symptom | Likely Cause | Fix |
|---|---|---|
| Buildings not appearing at all | RPC returned empty, Silver S3 also empty | Check `campaign_addresses.building_id` populated (run linker); check `buildings` table for this campaign |
| Building tapped shows "Unlinked Building" | `source == nil` and no address match in any step | Confirm `building_id` set on `campaign_addresses` for Gold; `building_gers_id` set for Silver |
| Wrong color (yellow instead of purple for QR scanned) | Stale `statusColor` in old code | Updated — now `#8b5cf6` purple, checks `qr_scanned` flag too |
| Address_point circles not showing | Point features not partitioned from buildings RPC | Confirm `MapFeaturesService.partitionFeaturesByGeometry` is running; check `self.addresses` after fetch |
| Silver fallback not firing | Partition produced polygons (correct) | Only fires when partition returns 0 polygons |
| `confidence` nil on Gold features | RPC not returning it yet | Add `confidence` to RPC property bag; field already in `BuildingProperties` |

---

## 10. Quick Reference: Files to Edit

| What you want to change | File |
|---|---|
| Feature properties model (add new fields) | `FLYR/Features/Buildings/Models/BuildingLinkModels.swift` — `BuildingProperties` |
| Fetch strategy / fallback order | `FLYR/Services/MapFeaturesService.swift` — `fetchAllCampaignFeatures()` |
| Point → address conversion | `MapFeaturesService` — `addressFeaturesFromPointBuildingFeatures()` |
| DB address resolution (tap → card) | `FLYR/Features/Map/Services/BuildingDataService.swift` — `fetchBuildingData()` |
| Tap fast-path (Gold properties) | `FLYR/Features/Map/Views/CampaignMapView.swift` — `resolveAddressForBuilding()` |
| Layer colors / heights / filters | `FLYR/Services/MapLayerManager.swift` — `setupBuildingsLayer()` / `setupAddressesLayer()` |
| Real-time color updates | `MapLayerManager` — `updateBuildingState()` / `updateAddressState()` |
