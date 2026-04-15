# FLYR Road Network Architecture — Web Integration Guide

**For:** FLYR Pro (web app)
**Context:** iOS has fully implemented the campaign-scoped road architecture. This doc covers the shared backend contracts, how the system works end-to-end, and exactly what the web app needs to implement.

---

## What Was Built

When a user creates a campaign, FLYR now pre-fetches all walkable roads within that campaign's polygon from Mapbox and stores them canonically in Supabase. Every session (iOS) then loads roads from Supabase — not Mapbox — which means:

- Zero Mapbox API calls during active sessions
- Offline session support after first preload
- Web and iOS share the same road data via a single Supabase source of truth
- Roads are versioned and atomic — a failed refresh never corrupts existing data

---

## Architecture at a Glance

```
Campaign Polygon (drawn by user)
        │
        ▼
tiledecode_roads (Supabase Edge Function)
  → Fetches Mapbox Vector Tiles for the bounding box
  → Decodes road geometries (LineString features)
  → Clips roads to the exact campaign polygon
  → Excludes motorways / high-speed roads (no pedestrian access)
        │
        ▼
rpc_upsert_campaign_roads()
  → Atomically replaces roads in campaign_roads table
  → Increments cache_version
  → Updates campaign_road_metadata (status: ready, expires in 30 days)
        │
        ▼
iOS / Web consumers
  → Call rpc_get_campaign_roads_v2(campaign_id) → GeoJSON FeatureCollection
  → Call rpc_get_campaign_road_metadata(campaign_id) → status + versioning info
```

---

## Supabase Tables

### `campaign_roads`

Stores one row per road segment per campaign.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `campaign_id` | UUID | FK → campaigns.id (CASCADE delete) |
| `road_id` | TEXT | Unique road identifier (from Mapbox or OSM) |
| `road_name` | TEXT | Street name (nullable) |
| `road_class` | TEXT | Mapbox road class (e.g. `street`, `path`, `footway`) |
| `geom` | GEOMETRY(LineString, 4326) | PostGIS geometry — the road centerline |
| `bbox_min_lat/lon` | DOUBLE PRECISION | Bounding box for spatial pre-filtering |
| `bbox_max_lat/lon` | DOUBLE PRECISION | Bounding box for spatial pre-filtering |
| `source` | TEXT | Always `mapbox` for now |
| `cache_version` | INTEGER | Increments on each refresh |
| `corridor_build_version` | INTEGER | Algorithm version (for client-side rebuild logic) |
| `properties` | JSONB | Raw Mapbox properties passthrough |
| `created_at` / `updated_at` | TIMESTAMPTZ | Timestamps |

**Indexes:** `campaign_id`, PostGIS GIST on `geom`, `(campaign_id, road_id)` unique, bbox composite.

---

### `campaign_road_metadata`

One row per campaign — tracks preparation status and versioning.

| Column | Type | Description |
|---|---|---|
| `campaign_id` | UUID | PK + FK → campaigns.id |
| `roads_status` | TEXT | `pending` \| `fetching` \| `ready` \| `failed` |
| `road_count` | INTEGER | Number of road segments stored |
| `bounds` | JSONB | Bounding box of all roads |
| `cache_version` | INTEGER | Latest version number |
| `corridor_build_version` | INTEGER | Algorithm version |
| `fetched_at` | TIMESTAMPTZ | When roads were last fetched |
| `expires_at` | TIMESTAMPTZ | Stale after this date (30-day TTL) |
| `last_refresh_at` | TIMESTAMPTZ | Last successful refresh |
| `last_error_message` | TEXT | Error detail on failure |
| `retry_count` | INTEGER | Number of failed attempts |
| `source` | TEXT | `mapbox` |

---

## Supabase RPC Reference

### `rpc_get_campaign_roads_v2(campaign_id UUID)`

Returns all roads for a campaign as a **GeoJSON FeatureCollection**.

```typescript
const { data } = await supabase.rpc('rpc_get_campaign_roads_v2', {
  p_campaign_id: campaignId
})

// data shape:
{
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      id: "road_id_string",
      geometry: { type: "LineString", coordinates: [[lon, lat], ...] },
      properties: {
        id: "road_id_string",
        name: "Main St",
        class: "street",
        cache_version: 3,
        corridor_build_version: 1
      }
    },
    ...
  ]
}
```

**Permissions:** `authenticated`, `service_role`, `anon`

---

### `rpc_get_campaign_road_metadata(campaign_id UUID)`

Returns preparation status and versioning info for a campaign.

```typescript
const { data } = await supabase.rpc('rpc_get_campaign_road_metadata', {
  p_campaign_id: campaignId
})

// data shape:
{
  campaign_id: "uuid",
  roads_status: "ready",       // "pending" | "fetching" | "ready" | "failed"
  road_count: 142,
  cache_version: 3,
  corridor_build_version: 1,
  fetched_at: "2026-03-16T...",
  expires_at: "2026-04-15T...",
  last_refresh_at: "2026-03-16T...",
  age_days: 0.5,
  is_stale: false,             // true if age_days >= 30
  last_error_message: null,
  source: "mapbox"
}
```

> If no record exists yet, returns `roads_status: "pending"` with zero counts — safe to call at any time.

**Permissions:** `authenticated`, `service_role`, `anon`

---

### `rpc_upsert_campaign_roads(campaign_id UUID, roads JSONB, metadata JSONB)`

**Atomically replaces** all roads for a campaign. Old data is deleted before new data is written. This is the write path — web should call this after fetching roads from the Edge Function.

```typescript
const { data } = await supabase.rpc('rpc_upsert_campaign_roads', {
  p_campaign_id: campaignId,
  p_roads: roadsArray,   // Array of road objects (see schema below)
  p_metadata: {
    bounds: { minLat, minLon, maxLat, maxLon },
    source: 'mapbox',
    corridor_build_version: 1
  }
})

// Returns:
{ success: true, road_count: 142, cache_version: 4 }
```

**Road object shape (element of `p_roads` array):**

```json
{
  "road_id": "string — unique road ID",
  "road_name": "Main St",
  "road_class": "street",
  "geom": { "type": "LineString", "coordinates": [[lon, lat], ...] },
  "bbox_min_lat": 37.123,
  "bbox_min_lon": -122.456,
  "bbox_max_lat": 37.124,
  "bbox_max_lon": -122.455,
  "source": "mapbox",
  "source_version": null,
  "properties": {}
}
```

**Permissions:** `authenticated`, `service_role` only

---

### `rpc_update_road_preparation_status(campaign_id UUID, status TEXT, error_message TEXT)`

Updates preparation status. Use this to reflect in-progress / failed states.

```typescript
// Mark as fetching
await supabase.rpc('rpc_update_road_preparation_status', {
  p_campaign_id: campaignId,
  p_status: 'fetching',
  p_error_message: null
})

// Mark as failed
await supabase.rpc('rpc_update_road_preparation_status', {
  p_campaign_id: campaignId,
  p_status: 'failed',
  p_error_message: 'Mapbox tile fetch timed out'
})
```

**Status values:** `pending` → `fetching` → `ready` | `failed`

**Permissions:** `authenticated`, `service_role`

---

## Supabase Edge Function — `tiledecode_roads`

This function handles the heavy lifting of fetching and decoding Mapbox Vector Tiles. **Call this from your backend/server-side only** — it requires the `MAPBOX_ACCESS_TOKEN` secret.

**Endpoint:** `POST /functions/v1/tiledecode_roads`

**Request body:**

```json
{
  "minLat": 37.700,
  "minLon": -122.480,
  "maxLat": 37.720,
  "maxLon": -122.460,
  "zoom": 14,
  "polygon": [[lon, lat], [lon, lat], ...]
}
```

| Field | Required | Description |
|---|---|---|
| `minLat/minLon/maxLat/maxLon` | Yes | Bounding box of campaign |
| `zoom` | No | MVT zoom level, default 14 (clamped 12–16) |
| `polygon` | No | Campaign polygon coords `[lon, lat][]` — roads outside are clipped out |

**Response:**

```json
{
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[lon, lat], ...] },
      "properties": {
        "id": "road_id",
        "name": "Oak Ave",
        "class": "street"
      }
    }
  ]
}
```

**Road classes returned (walkable only):**
`street`, `path`, `footway`, `pedestrian`, `residential`, `service`, `track`, `cycleway`

**Excluded (no pedestrian access):**
`motorway`, `motorway_link`, `trunk`, `trunk_link`

---

## Web Implementation — What You Need to Build

### On Campaign Creation

```
1. Campaign saved to Supabase
2. Call rpc_update_road_preparation_status(id, 'fetching')
3. Call tiledecode_roads edge function with campaign bbox + polygon
4. Map returned features → road objects (with bbox fields populated)
5. Call rpc_upsert_campaign_roads(id, roads, metadata)
   → This sets status to 'ready' automatically
```

If step 3 or 5 fails:
```
Call rpc_update_road_preparation_status(id, 'failed', errorMessage)
```

### Displaying Road Status

```typescript
const meta = await supabase.rpc('rpc_get_campaign_road_metadata', { p_campaign_id: id })

switch (meta.roads_status) {
  case 'pending':   // Show "Roads not prepared" + Prepare button
  case 'fetching':  // Show loading indicator
  case 'ready':     // Show road count + last refresh date
  case 'failed':    // Show error + Retry button (meta.last_error_message)
}

if (meta.is_stale) {
  // Show "Roads are outdated (30+ days), consider refreshing"
}
```

### Manual Refresh

Same flow as campaign creation — call `tiledecode_roads` → `rpc_upsert_campaign_roads`. The RPC is atomic so existing iOS users are never left with a broken state.

### Rendering Roads on Map

```typescript
const geojson = await supabase.rpc('rpc_get_campaign_roads_v2', { p_campaign_id: id })

// geojson is already a valid GeoJSON FeatureCollection
map.addSource('campaign-roads', { type: 'geojson', data: geojson })
map.addLayer({
  id: 'campaign-roads-line',
  type: 'line',
  source: 'campaign-roads',
  paint: { 'line-color': '#4A90D9', 'line-width': 2 }
})
```

---

## Road Class Reference (Mapbox Streets v8)

| Class | Description | Door-knocking? |
|---|---|---|
| `street` | Standard residential/commercial streets | Yes |
| `residential` | Residential streets | Yes |
| `path` | Footpaths, walking trails | Yes |
| `footway` | Dedicated footways | Yes |
| `pedestrian` | Pedestrian-only areas | Yes |
| `service` | Driveways, alleys | Yes |
| `track` | Unpaved/rural tracks | Yes |
| `cycleway` | Bike paths (often walkable) | Yes |
| `motorway` | Highways | **Excluded** |
| `trunk` | Major roads / expressways | **Excluded** |

---

## Versioning

Each call to `rpc_upsert_campaign_roads` auto-increments `cache_version`. iOS clients detect version changes and invalidate their local 30-day file cache, triggering a re-fetch from Supabase. This means:

- Web refreshes roads → `cache_version` bumps
- Next time iOS opens a session → detects stale version → re-downloads automatically
- No manual cache-busting needed

---

## RLS Policies Summary

| Table | SELECT | INSERT/UPDATE/DELETE |
|---|---|---|
| `campaign_roads` | Owner OR workspace member | Owner only |
| `campaign_road_metadata` | Owner OR workspace member | Owner only |

Both tables also grant full access to `service_role` for backend/edge function operations.

---

## Quick Reference — Supabase RPC Cheatsheet

```typescript
// Get roads as GeoJSON (read)
supabase.rpc('rpc_get_campaign_roads_v2', { p_campaign_id })

// Get status + version (read)
supabase.rpc('rpc_get_campaign_road_metadata', { p_campaign_id })

// Write roads (atomic replace)
supabase.rpc('rpc_upsert_campaign_roads', { p_campaign_id, p_roads, p_metadata })

// Update status only (no road data change)
supabase.rpc('rpc_update_road_preparation_status', { p_campaign_id, p_status, p_error_message })
```

---

## Notes & Gotchas

1. **`p_roads` must be a JSONB array** — pass it as a JavaScript array and Supabase will serialize it. Don't stringify it manually.
2. **Coordinates are `[lon, lat]`** throughout (GeoJSON standard / Mapbox convention) — not `[lat, lon]`.
3. **`geom` field in road objects** is the raw GeoJSON geometry object, not a WKT string.
4. **`bbox_*` fields are required** — compute them from the road's coordinate array before calling upsert.
5. **`rpc_upsert_campaign_roads` deletes all existing roads first** before inserting — this is intentional for atomicity. Do not call it in a partial/incremental way.
6. **`tiledecode_roads` needs `MAPBOX_ACCESS_TOKEN`** set as a Supabase secret — confirm this is already deployed.
7. Large campaigns (>1km²) at zoom 14 may cover many tiles — if timeouts occur, drop zoom to 13.
