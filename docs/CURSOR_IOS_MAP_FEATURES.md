# iOS Map Features – 3D Fill-Extrusions for Campaign Maps

Implementation guide for 3D building fill-extrusions on campaign maps in the FLYR iOS app. Matches FLYR-PRO web behavior and colors.

## Overview

- **MapFeaturesService** – Fetches campaign map data from Supabase (buildings, addresses, roads).
- **MapLayerManager** – Renders Mapbox layers: 3D fill-extrusion buildings, address markers, roads, and status-based colors.
- **CampaignMapView** – SwiftUI view that wires the map, service, and layer manager together.

## RPC Functions (Supabase)

| Function | Purpose |
|----------|--------|
| `rpc_get_campaign_full_features(p_campaign_id)` | Returns GeoJSON FeatureCollection of **buildings** with status, height, address_text, etc. Primary source for 3D extrusions. |
| `rpc_get_campaign_addresses(p_campaign_id)` | Returns GeoJSON FeatureCollection of **address points** for the campaign. |
| `rpc_get_campaign_roads(p_campaign_id)` | Returns GeoJSON FeatureCollection of **roads**. Can be a placeholder (empty) if no roads table. |

Run the SQL in `supabase_missing_functions.sql` in the Supabase SQL Editor if these RPCs or `address_statuses` are missing.

## Status Color Mapping (same as FLYR-PRO)

| Status | Hex | Usage |
|--------|-----|--------|
| QR Scanned | `#eab308` | Yellow – `scans_total > 0` |
| Conversations | `#3b82f6` | Blue – `status == "hot"` |
| Touched | `#22c55e` | Green – `status == "visited"` |
| Untouched | `#ef4444` | Red – `status == "not_visited"` (default) |
| Orphan (optional) | `#9ca3af` | Gray – orphan buildings |

Defined in:
- **MapFeaturesService** – `BuildingProperties.statusColor`
- **MapLayerManager** – `MapStatusColor` enum and fill-extrusion expression

## Flow

1. **CampaignMapView** appears with a `campaignId`.
2. **MapFeaturesService** calls `rpc_get_campaign_full_features`, `rpc_get_campaign_addresses`, and `rpc_get_campaign_roads` (all by campaign id).
3. **MapLayerManager** sets up:
   - Empty GeoJSON sources for buildings, addresses, roads.
   - Fill-extrusion layer for buildings (height from `height` / `height_m`, color from status expression).
   - Line layer for roads, circle layer for addresses.
   - 3D lighting.
4. When data arrives, `updateBuildings`, `updateAddresses`, `updateRoads` push GeoJSON into the sources.
5. Legend toggles (QR Scanned, Conversations, Touched, Untouched) call `updateStatusFilter()` to show/hide by status.
6. Tap on a building uses `getBuildingAt(point:completion:)` and shows **LocationCardView** with building details.

## Key Files

- `FLYR/Services/MapFeaturesService.swift` – API and GeoJSON types.
- `FLYR/Services/MapLayerManager.swift` – Layers, colors, filters, tap handling.
- `FLYR/Features/Map/Views/CampaignMapView.swift` – UI and wiring.

## Feature state (optional)

For real-time updates (e.g. after a QR scan), use **MapLayerManager.updateBuildingState(gersId:status:scansTotal:)** so the building color updates without re-fetching. Requires the buildings source to use `promoteId: "gers_id"` (already set in MapLayerManager).
