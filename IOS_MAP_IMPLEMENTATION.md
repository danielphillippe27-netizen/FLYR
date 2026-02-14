# FLYR iOS Map Implementation

This document explains the iOS implementation for querying buildings, addresses, and roads from Supabase and the backend (Lambda + S3) and rendering them with Mapbox fill-extrusions.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS App                               │
├─────────────────────────────────────────────────────────────┤
│  CampaignMapView.swift                                       │
│  └── MapboxMapViewRepresentable (SwiftUI wrapper)           │
│      └── MapLayerManager                                     │
│          ├── Buildings Layer (fill-extrusion)               │
│          ├── Roads Layer (line)                             │
│          └── Addresses Layer (circle)                       │
├─────────────────────────────────────────────────────────────┤
│  MapFeaturesService.swift                                    │
│  └── Supabase RPC calls → GeoJSON FeatureCollections        │
├─────────────────────────────────────────────────────────────┤
│                     Supabase                                 │
│  ├── rpc_get_campaign_full_features(campaign_id)            │
│  ├── rpc_get_buildings_in_bbox(min_lon, min_lat, ...)       │
│  ├── rpc_get_addresses_in_bbox(min_lon, min_lat, ...)       │
│  └── rpc_get_roads_in_bbox(min_lon, min_lat, ...)           │
└─────────────────────────────────────────────────────────────┘
```

## Files Created

### 1. `FLYR/Services/MapFeaturesService.swift`
Central service for fetching map data from Supabase.

**Key Methods:**
```swift
// Fetch ALL features for a campaign (fetch once, render forever)
await MapFeaturesService.shared.fetchCampaignFullFeatures(campaignId: "...")

// Fetch features in viewport (exploration mode)
await MapFeaturesService.shared.fetchBuildingsInBbox(
    minLon: -79.5, minLat: 43.5,
    maxLon: -79.3, maxLat: 43.7
)

// Get GeoJSON data for Mapbox source
let data = MapFeaturesService.shared.buildingsAsGeoJSONData()
```

### 2. `FLYR/Services/MapLayerManager.swift`
Manages Mapbox layers and styling.

**Key Features:**
- **Fill-extrusion layer** for 3D buildings with status-based colors
- **Line layer** for roads with class-based styling
- **Circle layer** for address markers
- **Real-time updates** via `setFeatureState()`
- **Status filters** for toggling visibility

**Status Colors (matches FLYR-PRO):**
| Status | Color | Hex |
|--------|-------|-----|
| QR Scanned | Yellow | `#eab308` |
| Conversations (hot) | Blue | `#3b82f6` |
| Touched (visited) | Green | `#22c55e` |
| Untouched | Red | `#ef4444` |
| Orphan | Gray | `#9ca3af` |

### 3. `FLYR/Features/Map/Views/CampaignMapView.swift`
SwiftUI view that ties everything together.

**Features:**
- 3D map with pitch/rotate gestures
- Status legend with filter toggles
- Building tap → Location card popup
- Loading state handling

### 4. `supabase/migrations/20250203_ios_map_features_rpc.sql`
SQL migration with RPC functions for iOS.

**Functions:**
- `rpc_get_buildings_in_bbox()` - Buildings in viewport
- `rpc_get_addresses_in_bbox()` - Addresses in viewport  
- `rpc_get_roads_in_bbox()` - Roads in viewport
- `rpc_get_campaign_full_features()` - All campaign buildings
- `rpc_get_campaign_addresses()` - All campaign addresses
- `rpc_get_campaign_roads()` - All campaign roads

## Data Flow

### Campaign Mode (Fetch Once, Render Forever)
```
1. User opens campaign map
2. MapFeaturesService.fetchCampaignFullFeatures(campaignId)
3. Supabase RPC returns full GeoJSON FeatureCollection
4. MapLayerManager.updateBuildings(data)
5. Buildings render with fill-extrusion
6. User pans/zooms freely (no re-fetching)
```

### Exploration Mode (Viewport-Based)
```
1. User pans map (no campaign selected)
2. MapFeaturesService.fetchBuildingsInBbox(viewport bounds)
3. Supabase RPC returns buildings in viewport
4. MapLayerManager.updateBuildings(data)
5. Buildings render with fill-extrusion
6. On next pan, repeat (debounced 200ms)
```

### Real-Time QR Scan Updates
```
1. User scans QR code elsewhere
2. building_stats table updated
3. Supabase Realtime broadcasts change
4. MapLayerManager.updateBuildingState(gersId, "visited", scansTotal: 1)
5. Building instantly changes to yellow (no full re-render)
```

## Fill-Extrusion Configuration

```swift
// Color expression (status priority)
layer.fillExtrusionColor = .expression(
    Exp(.switchCase) {
        // QR Scanned (highest priority): scans_total > 0
        Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
        "#eab308" // Yellow
        
        // Conversations: status == "hot"
        Exp(.eq) { Exp(.get) { "status" }; "hot" }
        "#3b82f6" // Blue
        
        // Touched: status == "visited"
        Exp(.eq) { Exp(.get) { "status" }; "visited" }
        "#22c55e" // Green
        
        // Default: Untouched
        "#ef4444" // Red
    }
)

// Height from properties
layer.fillExtrusionHeight = .expression(
    Exp(.coalesce) {
        Exp(.get) { "height" }
        Exp(.get) { "height_m" }
        10 // Default 10m
    }
)

// 3D lighting
map.setLights(
    ambient: AmbientLight(intensity: 0.5),
    directional: DirectionalLight(
        intensity: 0.6,
        direction: [210, 30],
        castShadows: true
    )
)
```

## GeoJSON Response Format

### Buildings
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "uuid",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[lon, lat], ...]]
      },
      "properties": {
        "id": "uuid",
        "gers_id": "overture-gers-id",
        "height": 10,
        "height_m": 10,
        "status": "not_visited",
        "scans_total": 0,
        "scans_today": 0,
        "address_text": "123 Main St",
        "feature_status": "matched",
        "match_method": "COVERS"
      }
    }
  ]
}
```

### Addresses
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "uuid",
      "geometry": {
        "type": "Point",
        "coordinates": [lon, lat]
      },
      "properties": {
        "id": "uuid",
        "gers_id": "overture-gers-id",
        "house_number": "123",
        "street_name": "Main St",
        "postal_code": "M5V 1A1",
        "formatted": "123 Main St, Toronto"
      }
    }
  ]
}
```

### Roads
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "uuid",
      "geometry": {
        "type": "LineString",
        "coordinates": [[lon, lat], ...]
      },
      "properties": {
        "id": "uuid",
        "gers_id": "overture-gers-id",
        "class": "secondary",
        "name": "Main Street"
      }
    }
  ]
}
```

## Setup Instructions

### 1. Run Supabase Migration
```bash
cd /Users/danielphillippe/Desktop/FLYR\ IOS
supabase db push
# Or run the SQL directly in Supabase Dashboard → SQL Editor
```

### 2. Add Files to Xcode Project
- `FLYR/Services/MapFeaturesService.swift`
- `FLYR/Services/MapLayerManager.swift`
- `FLYR/Features/Map/Views/CampaignMapView.swift`

### 3. Update Package Dependencies
Ensure `MapboxMaps` SDK is added to your project.

### 4. Usage
```swift
// In your campaign detail view:
CampaignMapView(campaignId: campaign.id)
```

## Database Tables Used

| Table | Purpose |
|-------|---------|
| `buildings` | Building footprints (geometry + gers_id + height) |
| `campaign_addresses` | Addresses with GERS IDs |
| `building_address_links` | Links buildings ↔ addresses |
| `building_stats` | Status tracking (visited, scans) |
| `roads` | Road geometries for rendering |

## Backend Provision (Lambda + S3)

The backend loads the campaign polygon from Supabase, calls the Tile Lambda with it; Lambda reads S3 parquet (DuckDB/ST_Intersects), writes snapshot GeoJSON to S3. Backend ingests addresses and snapshot metadata into Supabase and runs StableLinker + TownhouseSplitter. The iOS app fetches addresses from Supabase; buildings from GET `/api/campaigns/[id]/buildings` (S3-backed) or fallback `rpc_get_campaign_full_features` for legacy campaigns.

**Data pipeline:**
```
Supabase (territory_boundary)
    ↓ [Backend provision API → Tile Lambda]
S3 (buildings.geojson.gz, addresses.geojson.gz)
    ↓ [Backend ingest]
Supabase (campaign_addresses, campaign_snapshots, building_address_links, building_units)
    ↓ [GET /api/campaigns/[id]/buildings or RPC]
iOS App (GeoJSON FeatureCollections)
    ↓ [MapLayerManager]
Mapbox (fill-extrusion, line, circle layers)
```

## Troubleshooting

### Buildings not appearing
1. Check zoom level (minZoom: 12)
2. Verify campaign has provisioned data
3. Check Supabase RPC response in Console logs

### Colors not updating
1. Ensure `gers_id` is set in properties (needed for feature state)
2. Check building_stats table for status updates
3. Verify Realtime is enabled on building_stats table

### Performance issues
1. Use campaign mode for campaigns (fetch once)
2. Debounce viewport queries (200ms)
3. Limit to 2000 features per query
