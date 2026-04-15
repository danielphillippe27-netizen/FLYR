# Campaign Roads — Technical Overview

How FLYR gets road centerlines for a campaign: polygon source, Mapbox tiles, storage, and session use.

---

## 1. Purpose

- **Campaign roads** = road centerlines (LineStrings) inside the campaign boundary.
- Used for:
  - **Pro GPS Normalization**: snap raw GPS to the nearest road corridor and infer side-of-street for a clean breadcrumb trail.
  - **Map overlay**: draw campaign roads on the session map so the trail aligns with the road network.
- **Single polygon source**: the same polygon used for **addresses/buildings** is used for roads — the campaign’s **drawn boundary** at creation, and **`territory_boundary`** from the DB for refresh/session.

---

## 2. Polygon Source (Same as Addresses/Buildings)

| When | Polygon source |
|------|----------------|
| **Campaign creation** | Drawn polygon from the map (user taps vertices). Same array is passed to: `createV2(…, polygon:)` → road preparation, and `updateTerritoryBoundary(polygonGeoJSON)` → stored in DB. |
| **Refresh Roads** (campaign detail) | Loaded from DB: `CampaignsAPI.fetchTerritoryBoundary(campaignId)` → `campaigns.territory_boundary` (GeoJSON Polygon). Converted to `[CLLocationCoordinate2D]` and passed to `CampaignRoadSettingsView` → refresh. |
| **Session start** | No polygon sent. Roads are **already** prepared and loaded from **local cache** or **Supabase** (see below). |

So: **one polygon** drives both address provisioning and road preparation; roads are always aligned with the same boundary as addresses/buildings.

---

## 3. High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PREPARE ROADS (creation or manual refresh)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Polygon (drawn or from territory_boundary)                                  │
│       │                                                                      │
│       ▼                                                                      │
│  CampaignRoadService.prepareCampaignRoads(campaignId, bounds, polygon)       │
│       │                                                                      │
│       ├─► EdgeFunctionRoadGeometryProvider.fetchRoads(bounds, polygon)       │
│       │        │                                                             │
│       │        └─► POST /functions/v1/tiledecode_roads                      │
│       │             Body: { "polygon": [[lon,lat],...], "zoom": 17 }         │
│       │             (Supabase Edge Function)                                  │
│       │                                                                      │
│       │   Edge function:                                                      │
│       │   • Buffers polygon 150 m (turf.buffer)                              │
│       │   • Derives bbox from buffered polygon                                │
│       │   • Fetches Mapbox Vector Tiles (z17) that intersect polygon         │
│       │   • Decodes "road" layer from each tile (LineStrings)                │
│       │   • Filters out motorway/trunk; keeps street, service, etc.           
   │       │   • Deduplicates by exact geometry                                    │
│       │   • Clips each road to buffered polygon (booleanIntersects)          │
│       │   • Merges connected segments (snap endpoints, group by name+class,  │
│       │     chain segments, optional simplify) — removes tile-seam seams     │
│       │   • Returns { features: [ GeoJSON LineString features ] }             │
│       │                                                                      │
│       ▼                                                                      │
│  storeRoadsInSupabase(campaignId, roads)                                    │
│       • Deduplicate by geometry (merged segments from edge function)         │
│       • rpc_upsert_campaign_roads(p_campaign_id, p_roads, p_metadata)        │
│       • campaign_roads table + campaign_road_metadata updated                │
│       │                                                                      │
│       ▼                                                                      │
│  CampaignRoadDeviceCache.store(roads, campaignId, version)                   │
│       • Write to Caches/CampaignRoadCache/{campaignId}.json                  │
│       • Update cache_metadata.json                                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  SESSION START (get roads for tracking)                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  CampaignRoadService.getRoadsForSession(campaignId)                          │
│       │                                                                      │
│       ├─► 1. CampaignRoadDeviceCache.load(campaignId)                        │
│       │        • If hit and not expired → return [StreetCorridor]            │
│       │                                                                      │
│       └─► 2. If miss: fetchCampaignRoadsFromSupabase(campaignId)             │
│                • rpc_get_campaign_roads_v2(p_campaign_id)                     │
│                • Returns GeoJSON FeatureCollection of LineStrings            │
│                • Convert to [StreetCorridor]                                 │
│                • Store in device cache for next time                          │
│                                                                              │
│  SessionManager.startBuildingSession()                                       │
│       • corridors = await getRoadsForSession(campaignId)                     │
│       • SessionTrailNormalizer(config, corridors, buildingCentroids)        │
│       • sessionRoadCorridors = corridors (for map overlay)                   │
│       • No Mapbox or tiledecode_roads calls during session                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Edge Function: `tiledecode_roads`

**Path:** `supabase/functions/tiledecode_roads/index.ts`  
**Invoked by:** iOS `EdgeFunctionRoadGeometryProvider` (POST with auth headers).

### 4.1 Request

- **Method:** POST  
- **Body:** JSON only; **no bbox**.
  - `polygon` **(required):** `[[lon, lat], ...]` — at least 3 points (campaign boundary).
  - `zoom` (optional): 12–17; default 16. iOS sends **17** for maximum detail.

### 4.2 Steps Inside the Function

1. **Validate**  
   - Require `polygon` array with ≥ 3 points.

2. **Build clip polygon**  
   - Close ring if first ≠ last.  
   - `turf.polygon([ring])` → `turf.buffer(0.15, { units: "kilometers" })` → **150 m buffer** so boundary and inner roads are included.

3. **Tile selection (polygon-based)**  
   - `turf.bbox(clipPolygon)` → `[minLon, minLat, maxLon, maxLat]`.  
   - Expand bbox by 0.5% each side to avoid edge rounding.  
   - `bboxToTiles(...)` → candidate tile set at zoom 17.  
   - **Filter tiles**: keep only tiles whose geographic bbox **intersects** the buffered polygon (`turf.booleanIntersects(tileBboxPolygon(x,y), clipPolygon)`). So tile selection is driven by the polygon, not a raw bbox.

4. **Fetch Mapbox Vector Tiles**  
   - For each `(z, x, y)`: `GET https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/{z}/{x}/{y}.vector.pbf?access_token=...`  
   - Retry up to 3 times with 600 ms delay on 429 or 5xx.  
   - Decode with `@mapbox/vector-tile` + `pbf`.

5. **Decode road layer**  
   - Layer: `"road"`.  
   - Feature type: LineString (type 2).  
   - For each feature: read `class` (or `type`); **exclude** `motorway`, `motorway_link`, `trunk`, `trunk_link`.  
   - Convert to GeoJSON LineString with `feat.toGeoJSON(x, y, z)`; keep `id`, `name`, `class`.

6. **Deduplicate and clip**  
   - Deduplicate by exact geometry key (`JSON.stringify(coordinates)`).  
   - For each road: `turf.booleanIntersects(line, clipPolygon)`; drop if false.  
   - Collect all remaining features.

7. **Merge connected segments**  
   - **Snap endpoints**: Round first/last coordinates of each segment to 6 decimal places (~0.1 m) so boundaries from different tiles compare equal.  
   - **Group by road identity**: Use `(name, class)` as the merge key; unnamed roads use sentinel `"__"` so they still merge by class.  
   - **Chain segments**: Build continuous LineStrings by connecting segments whose endpoints match within tolerance (~1–2 m). Handles reversed direction (A.end≈B.end) by reversing B before appending.  
   - **Branches**: If a road splits (Y-junction), each branch becomes a separate feature.  
   - **Output**: One LineString per chain with the first segment’s `id` and shared `name`/`class`.  
   - **Optional simplify**: Light Douglas–Peucker simplification (tolerance ~1 m) for smoother curves and smaller payload.  
   - **Result**: Removes tile-seam discontinuities so roads render without gaps/angle shifts; GPS normalization no longer jitters or flips side-of-street at former tile boundaries.

8. **Response**  
   - `{ "features": [ { "type": "Feature", "geometry": { "type": "LineString", "coordinates": [[lon,lat],...] }, "properties": { "id", "name", "class" } }, ... ] }`.

### 4.3 Mapbox Tileset

- **Tileset:** `mapbox.mapbox-streets-v8`  
- **Layer:** `road`  
- **Zoom:** 17 for maximum road detail (service roads, inner loops, cul-de-sacs).  
- **Excluded classes:** motorway, motorway_link, trunk, trunk_link (no pedestrian access). All other classes (street, service, residential, path, etc.) are included.

---

## 5. iOS: From Polygon to Corridors

### 5.1 When Roads Are Fetched (Mapbox Path)

| Trigger | Call chain | Polygon from |
|--------|-------------|--------------|
| **Campaign creation** | `NewCampaignScreen` → `createHook.createV2(…, polygon:)` → `prepareCampaignRoads(campaignId, polygon)` | Drawn polygon |
| **Refresh Roads** | `CampaignRoadSettingsView` → `refreshRoads()` → `CampaignRoadService.refreshCampaignRoads(campaignId, bounds, polygon)` | `territoryPolygon` from `CampaignsAPI.fetchTerritoryBoundary(campaignId)` |

In both cases the provider **requires** a polygon (≥ 3 points); it does not use bbox for the request.

### 5.2 EdgeFunctionRoadGeometryProvider

- **Protocol:** `RoadGeometryProvider` — `fetchRoads(in: BoundingBox, polygon: [CLLocationCoordinate2D]?) async throws -> [StreetCorridor]`.  
- **Implementation:**  
  - Requires `polygon != nil` and `polygon.count >= 3`.  
  - Builds body: `{ "polygon": [[lon, lat], ...], "zoom": 17 }`.  
  - POST to `{SUPABASE_URL}/functions/v1/tiledecode_roads` with `Content-Type: application/json`, `apikey`, `Authorization: Bearer <session.accessToken>`.  
  - Decodes response into `RoadFeature` and converts with `StreetCorridor.from(roadFeatures:)`.

### 5.3 CampaignRoadService

- **prepareCampaignRoads(campaignId, bounds, polygon)**  
  - Sets metadata status to `fetching`.  
  - Calls `mapboxProvider.fetchRoads(in: bounds, polygon: polygon)` → gets `[StreetCorridor]`.  
  - **storeRoadsInSupabase**: deduplicates by geometry; assigns unique `road_id` per segment (so tile-split segments are kept); calls `rpc_upsert_campaign_roads`.  
  - Updates metadata to `ready`, then **CampaignRoadDeviceCache.store(roads, campaignId, version)**.

- **getRoadsForSession(campaignId)**  
  - Tries **CampaignRoadDeviceCache.load(campaignId)** first.  
  - On miss: **fetchCampaignRoadsFromSupabase(campaignId)** via `rpc_get_campaign_roads_v2`, then stores result in device cache.  
  - Returns `[StreetCorridor]`. No Mapbox or edge function calls in this path.

### 5.4 Storage

| Store | Role | Format |
|-------|------|--------|
| **Supabase `campaign_roads`** | Canonical: one row per road segment; columns include `road_id`, `road_name`, `road_class`, `geom` (PostGIS LineString), bbox, `cache_version`, etc. | Persisted; shared across devices and web. |
| **Supabase `campaign_road_metadata`** | Status and version: `roads_status`, `road_count`, `cache_version`, `fetched_at`, `expires_at`, etc. | One row per campaign. |
| **CampaignRoadDeviceCache** | Offline mirror: `Caches/CampaignRoadCache/{campaignId}.json` + `cache_metadata.json`. TTL 30 days, size cap 100 MB. | Fast session load; no network when cache hit. |

### 5.5 Session Use

- **SessionManager.startBuildingSession()** (when Pro GPS Normalization is enabled):  
  - `corridors = await CampaignRoadService.shared.getRoadsForSession(campaignId)`.  
  - If empty: show error “Campaign roads not available…”.  
  - Else: `SessionTrailNormalizer(config, corridors, candidatePointsForSide: buildingCentroids)`, and `sessionRoadCorridors = corridors` for the map.  
- **MapFeaturesService.fetchCampaignRoads(campaignId)** (e.g. map UI):  
  - Same: `getRoadsForSession(campaignId)` then converts corridors to `RoadFeatureCollection` for existing map code.  
- During the session there are **no** Mapbox or `tiledecode_roads` calls; all road data comes from cache or Supabase.

---

## 6. Data Model (Summary)

- **StreetCorridor** (Swift): `id`, `polyline: [CLLocationCoordinate2D]`, `roadName`, `roadClass`, plus cumulative distances for projection.  
- **campaign_roads** (DB): `campaign_id`, `road_id`, `road_name`, `road_class`, `geom` (LineString 4326), bbox, `cache_version`, etc.  
- **RPCs:**  
  - `rpc_get_campaign_roads_v2(p_campaign_id)` → GeoJSON FeatureCollection.  
  - `rpc_upsert_campaign_roads(p_campaign_id, p_roads, p_metadata)` → atomic replace for campaign.  
  - `rpc_get_campaign_road_metadata(p_campaign_id)`, `rpc_update_road_preparation_status(...)`.

---

## 7. File Reference

| Layer | File(s) |
|-------|--------|
| **Edge function** | `supabase/functions/tiledecode_roads/index.ts` |
| **Road service & provider** | `FLYR/Services/CampaignRoadService.swift` |
| **Device cache** | `FLYR/Services/CampaignRoadDeviceCache.swift` |
| **Corridor type** | `FLYR/Features/Map/GPSNormalization/StreetCorridor.swift` |
| **Session load** | `FLYR/Features/Map/SessionManager.swift` (startBuildingSession) |
| **Map features** | `FLYR/Services/MapFeaturesService.swift` (fetchCampaignRoads) |
| **Creation** | `FLYR/Feautures/Campaigns/Hooks/UseCreateCampaign.swift` (prepareCampaignRoads) |
| **Detail / refresh** | `FLYR/Feautures/Campaigns/Views/NewCampaignDetailView.swift`, `FLYR/Features/Campaigns/Components/CampaignRoadSettingsView.swift` |
| **Territory API** | `FLYR/Feautures/Campaigns/CampaignsAPI.swift` (fetchTerritoryBoundary, updateTerritoryBoundary) |
| **DB schema** | `supabase/migrations/20260316000001_campaign_roads_recreate_tables.sql` |

---

## 8. Summary

- **Polygon** = same as addresses/buildings: drawn at creation, stored as `territory_boundary`; refresh uses `fetchTerritoryBoundary(campaignId)`.  
- **Fetch path** = polygon-only POST to `tiledecode_roads` → Mapbox MVT at z17 → decode “road” layer → clip to 150 m buffered polygon → merge connected segments (removes tile seams) → return LineString features.  
- **Storage** = Supabase `campaign_roads` + `campaign_road_metadata` (canonical), plus device cache (offline/speed).  
- **Session** = `getRoadsForSession(campaignId)` → cache first, then Supabase; no Mapbox or edge calls during tracking. Roads drive `SessionTrailNormalizer` and the session map overlay.
