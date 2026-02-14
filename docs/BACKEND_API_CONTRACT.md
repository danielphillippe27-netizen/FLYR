# Backend API contract (generate-address-list, provision, buildings)

Single source of truth for the FLYR backend and iOS app. Backend base URL is set on iOS via `FLYR_PRO_API_URL` (e.g. `https://flyrpro.app`).

**Data architecture:** Polygon and campaign metadata live in Supabase. Provision loads the polygon from Supabase, calls the Tile Lambda with it; Lambda reads buildings and addresses from S3 parquet (DuckDB/ST_Intersects), writes snapshot GeoJSON to S3. Backend ingests addresses and snapshot metadata into Supabase and runs StableLinker + TownhouseSplitter. Building geometry lives in S3; Supabase holds `campaign_snapshots`, `campaign_addresses`, `building_address_links`, and `building_units`. The map fetches building GeoJSON via GET `/api/campaigns/[campaignId]/buildings` (S3-backed) and merges with `building_units` for extruded townhouse units.

---

## 1. POST /api/campaigns/generate-address-list

**Purpose:** Fetch addresses (Lambda + S3 / Overture) and upsert them into Supabase for a campaign. Addresses only; no buildings or roads. Backend is backed by Lambda/S3, not MotherDuck.

### Request body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `campaign_id` | string (UUID) | Yes | Campaign to attach addresses to. |
| `starting_address` | string | One of two | For "closest home" mode: address or label to geocode (or skip geocoding if `coordinates` provided). |
| `polygon` | GeoJSON Polygon | One of two | For map/territory mode: `{ "type": "Polygon", "coordinates": [[[lng,lat], ...]] }`. |
| `count` | integer | No | Max addresses when using `starting_address`; default 50. |
| `coordinates` | object | No | Skip geocoding when using `starting_address`: `{ "lat": number, "lng": number }`. |

**Rule:** Exactly one of `starting_address` or `polygon` is required.

- **With polygon:** Addresses inside that polygon (map-drawn territory).
- **With starting_address:** Geocode (or use `coordinates`), then nearest N addresses from backend (Lambda/S3).

### Success response (200)

```json
{
  "inserted_count": 123,
  "preview": [
    { "id": "uuid", "formatted": "714 Mason St", "postal_code": "94102", "source": "overture", "gers_id": "..." }
  ]
}
```

Empty result (200):

```json
{
  "inserted_count": 0,
  "preview": [],
  "message": "No addresses found in polygon"
}
```

(or `"No addresses found near location"` for starting_address mode.)

### Error responses

- **400:** Missing `campaign_id`; or neither `starting_address` nor `polygon`; or geocoding failed.
- **404:** Campaign not found.
- **500:** Lambda/S3 or Supabase upsert error.

### Supabase tables written

| Table | Action |
|-------|--------|
| `campaign_addresses` | Upsert (on conflict `campaign_id`, `gers_id`). Columns: `campaign_id`, `formatted`, `postal_code`, `source`, `visited`, `geom`, `gers_id`, `house_number`, `street_name`, `locality`, `region`, `building_gers_id`. |
| `campaigns` | Update `total_flyers` for that campaign. |
| (optional) | RPC `update_campaign_bbox(p_campaign_id)` to refresh campaign bbox from addresses. |

**Backend flow:** Backend (Lambda/S3: e.g. bbox or polygon query) → map to canonical → upsert `campaign_addresses` → update `campaigns.total_flyers` (and optionally bbox). No buildings or roads in this endpoint.

---

## 2. POST /api/campaigns/provision

**Purpose:** Full provisioning: load polygon from Supabase, call Tile Lambda; Lambda reads S3 parquet, writes snapshot GeoJSON to S3; backend ingests addresses and snapshot metadata into Supabase, runs StableLinker and TownhouseSplitter (building_address_links, building_units). No MotherDuck.

### Request body

```json
{
  "campaign_id": "uuid"
}
```

**Precondition:** Campaign must have `territory_boundary` (polygon) set. If not, backend returns **400** with message e.g. `"No territory boundary defined. Please draw a polygon on the map when creating the campaign."`

### Success response (200)

```json
{
  "success": true,
  "addresses_saved": 150,
  "buildings_saved": 145,
  "roads_saved": 50,
  "links_created": 148,
  "discovered_addresses": 5,
  "cache_hits": 3,
  "api_calls": 2,
  "orphan_buildings": 0,
  "total_addresses": 155,
  "total_buildings": 148,
  "message": "Zero-Gap provisioning complete: ..."
}
```

### Error responses

- **400:** Missing `campaign_id` or no `territory_boundary`.
- **404:** Campaign not found.
- **500:** Provisioning failed (e.g. Lambda, S3, ingest, or link step).

### Backend flow

1. Load polygon (and region) from `campaigns.territory_boundary` in Supabase.
2. Call Tile Lambda (e.g. `TileLambdaService.generateSnapshots()`) with polygon and campaign_id/region.
3. Lambda queries S3 parquet (buildings, addresses) with DuckDB/ST_Intersects, writes gzipped GeoJSON to snapshot bucket (e.g. `campaigns/{campaignId}/buildings.geojson.gz`, `addresses.geojson.gz`), returns bucket/keys and presigned URLs.
4. Backend downloads addresses from snapshot URL, inserts into `campaign_addresses`, writes `campaign_snapshots` (bucket, keys, counts).
5. Backend runs StableLinkerService (spatial join → `building_address_links`) and TownhouseSplitterService (multi-unit splits → `building_units`).
6. Set `provision_status` → `'ready'` on campaign.

### Supabase tables written (by backend + RPCs)

| Table | Action |
|-------|--------|
| `campaigns` | `provision_status` → `'pending'` at start, then `'ready'` or `'failed'`. |
| `campaign_addresses` | Replaced for that campaign (from snapshot addresses). |
| `campaign_snapshots` | Insert/update: bucket, buildings_key, addresses_key, counts (metadata only; building geometry stays in S3). |
| `building_address_links` | Filled by StableLinkerService (address ↔ building by GERS ID). |
| `building_units` | Filled by TownhouseSplitterService (unit geometry per address for multi-unit buildings). |
| `roads` / `campaign_roads` | Optional; same RPC/table convention as before. |

Building geometry is stored in S3; only addresses, snapshot metadata, links, and units are in Supabase.

---

## 3. GET /api/campaigns/[campaignId]/buildings

**Purpose:** Return building GeoJSON for the campaign map. Backend reads `campaign_snapshots` for the campaign, fetches the buildings file from S3 (GetObject, gunzip), returns GeoJSON. Used by iOS (and web) for extruded building layer; client may merge with `building_units` from Supabase for townhouse splits.

### Request

- **Method:** GET
- **Path:** `/api/campaigns/{campaign_id}/buildings` (campaign_id = UUID)

### Success response (200)

- **Content-Type:** `application/geo+json` or `application/json`
- **Body:** GeoJSON FeatureCollection of building polygons (and optional properties: gers_id, height_m, etc.). May be merged with unit geometries by backend or by client from `building_units`.

### Error responses

- **404:** Campaign not found or no snapshot (no buildings_key in campaign_snapshots).
- **500:** S3 or backend error.

---

## 4. Table name alignment (roads vs campaign_roads)

- **iOS** currently reads roads via `rpc_get_campaign_roads(p_campaign_id)`, which selects from **`public.roads`** where `campaign_id = p_campaign_id` (see `supabase/migrations/20250203_ios_map_features_rpc.sql`).
- The contract text may refer to **`campaign_roads`** as the table name.
- **Convention:** Use one of:
  - **(a)** Backend writes to **`roads`** with `campaign_id`; no RPC change. Recommended for consistency with existing iOS RPC.
  - **(b)** Introduce a **`campaign_roads`** table and update `rpc_get_campaign_roads` to select from `campaign_roads`.

Document which convention your backend uses so migrations and RPCs stay consistent.

---

## 5. iOS usage summary

- **Create campaign (with territory):** Ensure campaign row exists in Supabase with `territory_boundary` set (e.g. from map draw). Then call either:
  - POST `.../generate-address-list` with `campaign_id` + `polygon` (same as territory), or
  - POST `.../provision` with `campaign_id` (backend uses stored `territory_boundary`).
- **Addresses-only (e.g. "closest home"):** Call POST `.../generate-address-list` with `campaign_id` + `starting_address` (and optional `count` / `coordinates`). Backend is backed by Lambda/S3.
- **Full map experience (addresses + buildings + roads):** Call POST `.../provision` with `campaign_id` after the campaign has `territory_boundary` set. Then fetch buildings via GET `.../api/campaigns/{id}/buildings` (S3-backed); optionally merge with `building_units` from Supabase for extruded units. Fallback: use `rpc_get_campaign_full_features` for legacy campaigns that still have rows in `buildings` table.

iOS only needs `FLYR_PRO_API_URL` pointing at the backend that implements these endpoints. After create/provision, addresses are read from Supabase; buildings are read from GET buildings API (or RPC fallback).

---

## 6. Closest-home buildings (optional / future)

When a campaign is created via **closest-home** (generate-address-list with `starting_address`), only addresses are written; no buildings or roads. The backend can provide buildings for closest-home using the same Lambda + S3 + link flow (e.g. small bbox or polygon around center), then write snapshot metadata and links. iOS can call GET `.../buildings` if a snapshot exists, or use `rpc_get_campaign_full_features` if backend still syncs to `buildings` table.

### Option A – provision-from-center

`POST /api/campaigns/provision-from-center` with body: `campaign_id`, `coordinates`, optional `count` or `radius`. Backend builds a small territory, runs the same Lambda → ingest → link flow as provision, writes to `campaign_addresses`, `campaign_snapshots`, `building_address_links`, `building_units`. iOS then uses GET buildings or RPC for map.

---

## 7. Verification checklist

After implementing the contract on both backend and iOS:

1. **Closest-home / map-point create:** Create a campaign with a location (typed query or map pin). Confirm the backend receives `POST .../generate-address-list` with `campaign_id`, `starting_address`, `coordinates`, and `count` (no polygon). Confirm iOS decodes `inserted_count` and `preview` and that the campaign detail shows addresses from Supabase.
2. **Polygon create:** Draw a polygon and create a campaign. Confirm `territory_boundary` is saved, then `POST .../provision` with `campaign_id` is sent. Confirm 200 response is decoded (addresses_saved, buildings_saved, etc. logged) and that the campaign map shows addresses and buildings (via GET buildings or RPC).
3. **Buildings API:** For a provisioned campaign, GET `.../api/campaigns/{id}/buildings` returns GeoJSON; iOS can use it for the map layer (with optional merge of `building_units`).
4. **Error handling:** If the backend returns 400/404/500 with a JSON `message` (or `error`) field, confirm the user sees that message in the app error state instead of raw body.
