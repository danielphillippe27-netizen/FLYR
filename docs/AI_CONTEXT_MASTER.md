# FLYR Master Context

## Product

FLYR is a door-knocking and flyer tracking app for real estate agents and field marketing teams. Agents create campaigns, view 3D buildings/roads/addresses on a Mapbox map, track visit status with color-coded buildings, record QR scans, log conversations, and manage leads through an integrated CRM.

## Tech Stack

- **iOS App**: Swift/SwiftUI with Hooks/Stores/Views architecture
- **Map**: Mapbox Maps SDK (3D fill-extrusion buildings)
- **Backend**: Supabase Postgres + PostGIS for spatial data
- **Database**: RPC functions returning GeoJSON FeatureCollections
- **Web API**: Next.js backend at `https://flyrpro.app`
- **Address Data**: Backend Lambda + S3 (Overture parquet) primary source, Mapbox Geocoding fallback
- **Building Data**: S3 snapshot (provision) + GET `/api/campaigns/[id]/buildings`; Mapbox for rendering
- **Integrations**: HubSpot, Monday.com, Follow Up Boss, KVCore, Zapier

## Core Data Model (High Level)

### Primary Objects

- **Campaigns** (`campaigns` table, UUID id)
  - Container for a door-knocking or flyer distribution campaign
  - Types: flyer, doorKnock, event, survey, gift, popBy, openHouse
  - Address sources: closestHome, importList, map, sameStreet

- **Addresses** (`campaign_addresses` table)
  - Point geometry (lat/lon)
  - Linked to campaigns via `campaign_id` FK
  - Contains formatted address, postal code, GERS ID (unique identifier)

- **Buildings** (`buildings` table)
  - Polygon/MultiPolygon geometry (building footprints)
  - Linked to campaigns via `campaign_id` FK
  - Contains height, unit count, GERS ID
  - Cached in `building_polygons` table (address_id → geom)

- **Roads** (`roads` table)
  - LineString geometry (road centerlines)
  - Linked to campaigns via `campaign_id` FK
  - Contains road name, class (primary, secondary, tertiary)

- **Address Statuses** (`address_statuses` table)
  - Tracks visit status per address per campaign
  - Status enum: `none`, `no_answer`, `delivered`, `talked`, `appointment`, `do_not_knock`, `future_seller`, `hot_lead`
  - Updates trigger building color changes on map

- **QR Codes** (`qr_codes` table)
  - Generated QR codes for tracking flyer scans
  - Contains slug (short URL), address_id, campaign_id, qr_type
  - Scan tracking in `qr_code_scans` table

- **Contacts** (`contacts` table)
  - CRM contacts with full_name, phone, email, address
  - Linked to campaigns and farms
  - Activity tracking in `contact_activities` table

- **Sessions** (`sessions` table)
  - Session/workout tracking with path GeoJSON
  - Records distance, duration, goal type (time, distance, doors)

- **User Stats** (`user_stats` table)
  - Aggregated metrics: flyers, conversations, leads, distance
  - Powers leaderboard rankings

### Object Relationships

```
campaigns (1) → (many) campaign_addresses
campaign_addresses (1) → (1) building_polygons
campaign_addresses (1) → (many) address_statuses
campaign_addresses (1) → (many) qr_codes

campaigns (1) → (many) buildings
campaigns (1) → (many) roads
campaigns (1) → (many) contacts
campaigns (1) → (many) sessions

users (1) → (1) user_stats
users (1) → (many) campaigns
```

## Core Flow (Happy Path)

### Campaign Creation & Provisioning

1. **Campaign Created**: User creates campaign in iOS app
   - `CampaignsAPI.createV2()` → Supabase `campaigns` table

2. **Provisioning**: App calls `POST /api/campaigns/provision` with `campaign_id`
   - Backend loads polygon from Supabase, calls Tile Lambda; Lambda reads S3 parquet, writes snapshot to S3
   - Backend ingests addresses into `campaign_addresses`, writes `campaign_snapshots`; runs StableLinker + TownhouseSplitter
   - Building geometry in S3; map fetches via GET `/api/campaigns/[id]/buildings` (and optional `building_units` from Supabase)

3. **Map Data Loading**: iOS fetches GeoJSON via Supabase RPCs
   - `rpc_get_campaign_full_features(campaign_id)` → Buildings FeatureCollection (Polygon/MultiPolygon)
   - `rpc_get_campaign_addresses(campaign_id)` → Addresses FeatureCollection (Point)
   - `rpc_get_campaign_roads(campaign_id)` → Roads FeatureCollection (LineString)

4. **Map Rendering**: `MapLayerManager` updates Mapbox sources/layers
   - Buildings rendered as 3D fill-extrusion with status-based colors
   - Roads rendered as line layers
   - Addresses rendered as circle markers

5. **Status Updates**: User taps building, changes status → Adaptive polling or manual refresh
   - Status change updates `address_statuses` table
   - `building_stats` table updated via trigger
   - MapLayerManager updates feature state → Building color changes immediately

### Data Returns GeoJSON FeatureCollections

All map RPCs return GeoJSON in this format:

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "uuid-here",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-79.123, 35.456], ...]]
      },
      "properties": {
        "status": "delivered",
        "height": 10,
        "formatted": "123 Main St",
        "scans_total": 0
      }
    }
  ]
}
```

## Naming Conventions

### Database

- **Table names**: `snake_case` (e.g., `campaign_addresses`, `building_polygons`)
- **RPC prefix**: `rpc_` for complex queries, `fn_` for utility functions
  - Examples: `rpc_get_campaign_full_features`, `fn_addr_nearest_v2`
- **Column names**: `snake_case` with suffixes:
  - `_id` for foreign keys (e.g., `campaign_id`, `address_id`)
  - `_at` for timestamps (e.g., `created_at`, `visited_at`)
  - `_m` for meters (e.g., `height_m`, `area_m2`)

### iOS

- **Source IDs**: camelCase with "Source" suffix
  - `buildingsSource`, `roadsSource`, `addressesSource`
- **Layer IDs**: camelCase with layer type suffix
  - `buildingsExtrusionLayer`, `roadsLineLayer`, `addressesCircleLayer`
- **Hooks**: `Use*` prefix (e.g., `UseCampaignsV2`, `UseCreateCampaign`)
- **Stores**: `*Store` suffix (e.g., `CampaignV2Store`)
- **API Clients**: `*API` suffix (e.g., `CampaignsAPI`, `QRCodeAPI`)

### Code Organization

- **Features directory**: `Features/` and `Feautures/` (note typo exists in codebase)
- **Feature structure**: `Models/`, `Views/`, `ViewModels/`, `API/`, `Services/`, `Components/`

## Environments

### Production

- **Backend API**: `https://flyrpro.app`
- **Supabase**: Project URL and anon key in `Info.plist`
- **Mapbox**: Access token in `Info.plist`

### Configuration

- Environment variables in `.env.local` (for backend/scripts)
- iOS config in `FLYR/Info.plist`:
  - `FLYR_PRO_API_URL`
  - `MAPBOX_ACCESS_TOKEN`
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`

## Known Gotchas

### 1. TLS Intercept Issues

- **Problem**: iOS TLS errors on some corporate/public networks with SSL interception
- **Symptom**: "The certificate for this server is invalid" or connection failures
- **Workaround**: Use cellular data or different network

### 2. Mapbox Fill-Extrusion Geometry Filter

- **Problem**: Mapbox fill-extrusion layers crash if they receive LineString geometries
- **Solution**: ALWAYS filter buildings layer to polygon geometries only:
  ```swift
  ["in", ["geometry-type"], ["literal", ["Polygon", "MultiPolygon"]]]
  ```
- **Error message**: "Expected Polygon/MultiPolygon but got LineString"

### 3. RPC GeoJSON Flexibility

- **Problem**: PostGIS `ST_AsGeoJSON()` can return geometry as object or array depending on context
- **Solution**: iOS client uses flexible decoding (tries object first, falls back to array)
- **Code**: `Codable+SnakeCase.swift` handles both formats

### 4. Directory Naming Typo

- **Problem**: Two feature directories exist: `Features/` and `Feautures/` (typo)
- **Current state**: Both are in use
  - `Features/`: Map, QRCodes, Stats, Contacts, Farm, Settings
  - `Feautures/`: Campaigns, Addresses, Map (duplicate)
- **Note**: Be careful when searching for features - check both directories

### 5. Foreign Key Cascade Deletes

- **Problem**: Deleting campaigns may fail if child records exist
- **Solution**: Most FKs use `ON DELETE CASCADE` (automatically delete children)
- **Tables affected**: `campaign_addresses`, `buildings`, `roads`, `address_statuses`, `contacts`

### 6. Building Polygon Selection

- **Problem**: Multiple buildings may be near an address point
- **Strategy**: PostGIS uses priority:
  1. **Contains**: Point inside polygon (best match)
  2. **Nearby**: Centroid within 15m of point
  3. **Largest**: If multiple nearby, pick largest by area

### 7. Address Source Priority

- **Problem**: Multiple address sources may have conflicting data
- **Priority**: `durham_open` > `osm` > `user` > `fallback`
- **Table**: `addresses_master` with `source` column

### 8. Session Recording Path Size

- **Problem**: Long sessions generate large GeoJSON paths
- **Current**: Stored as JSONB in `sessions.path_geojson`
- **Note**: May need optimization for very long sessions (>1000 points)

## AI Prompt Best Practices

When asking AI questions about FLYR:

1. **Always paste this master doc** + one relevant module doc
2. **Be specific**: Include file paths, function names, table names
3. **Include context**: Error messages, logs, code snippets
4. **Ask for clarification**: If AI suggests multiple approaches, ask which is best for FLYR
5. **Prefer minimal changes**: Request diffs/patches, not full rewrites

### Example Prompt Header

```
You are my senior iOS + Supabase engineer for FLYR.
If you're unsure, ask for the missing file/function name.
Prefer minimal diff fixes.

[Paste this file]
[Paste relevant AI_CONTEXT_*.md module]
[Paste code snippet or error]

Question: [Your specific question]
```

## Module Quick Reference

- **Database questions** → Use `AI_CONTEXT_DB_SCHEMA.md`
- **RPC/query questions** → Use `AI_CONTEXT_RPC_CATALOG.md`
- **iOS code questions** → Use `AI_CONTEXT_IOS_ARCH.md`
- **Mapbox rendering questions** → Use `AI_CONTEXT_MAPBOX.md`
- **API/backend questions** → Use `AI_CONTEXT_API_ROUTES.md`
- **Flow/integration questions** → Use `AI_CONTEXT_FLOWS.md`

## Maintenance

Keep these docs updated when:

- **Schema changes**: Update `AI_CONTEXT_DB_SCHEMA.md`
- **New RPCs**: Update `AI_CONTEXT_RPC_CATALOG.md`
- **New API routes**: Update `AI_CONTEXT_API_ROUTES.md`
- **Architecture changes**: Update `AI_CONTEXT_IOS_ARCH.md` or this master doc
- **New flows**: Update `AI_CONTEXT_FLOWS.md`

**Goal**: Keep each doc ≤150 lines. If it grows too large, split into sub-modules.
