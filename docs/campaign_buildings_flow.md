# Campaign Buildings Caching Flow

## Overview

This document describes the new architecture for rendering campaign buildings on the map. The system has been refactored from runtime Mapbox queries to cached building polygons stored in Supabase.

## Old Flow (Runtime Queries)

**Previous Architecture:**
1. iOS app fetches campaign addresses from Supabase
2. For each address coordinate, uses `queryRenderedFeatures` on Mapbox composite building layer
3. Collects building IDs from rendered features
4. Creates a `FillExtrusionLayer` with a filter on those IDs
5. Renders red 3D buildings

**Problems:**
- Inconsistent results (depends on viewport, zoom, style, tile loading)
- Slow performance (queries run every time map is opened)
- Requires map to be loaded and tiles rendered before queries work
- Building IDs may not be found if tiles haven't loaded yet

## New Flow (Cached Geometry)

**Current Architecture:**
1. **One-time sync**: Edge Function `campaign-sync-buildings` fetches building polygons from Mapbox and stores them in `campaign_buildings` table
2. **Runtime rendering**: iOS app fetches cached buildings from Supabase
3. **GeoJSON source**: Creates a `GeoJSONSource` with building polygons
4. **3D layer**: Creates a `FillExtrusionLayer` on that source for red 3D buildings
5. **Consistent rendering**: Same buildings every time, no dependency on tile loading

**Benefits:**
- Consistent results (same buildings every time)
- Fast performance (no runtime queries needed)
- Works immediately (no waiting for tiles to load)
- Self-healing (can trigger sync if buildings missing)

## Database Schema

### `campaign_buildings` Table

```sql
CREATE TABLE public.campaign_buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    building_id TEXT, -- Optional Mapbox building identifier
    geometry GEOMETRY(Polygon, 4326) NOT NULL, -- PostGIS polygon
    height_m DOUBLE PRECISION, -- Optional building height
    min_height_m DOUBLE PRECISION, -- Optional base height
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    CONSTRAINT unique_campaign_building_address UNIQUE (address_id)
);
```

**Key Points:**
- **1:1 relationship**: One building per address (UNIQUE constraint on `address_id`)
- **PostGIS geometry**: Stored as `GEOMETRY(Polygon, 4326)` for efficient spatial queries
- **Cascade deletes**: Buildings are deleted when campaign or address is deleted
- **RLS policies**: Users can only access buildings for campaigns they own

### RPC Function: `fn_upsert_campaign_building`

Handles PostGIS geometry conversion from GeoJSON:

```sql
CREATE OR REPLACE FUNCTION public.fn_upsert_campaign_building(
    p_campaign_id UUID,
    p_address_id UUID,
    p_geom_json JSONB,
    p_building_id TEXT DEFAULT NULL,
    p_height_m DOUBLE PRECISION DEFAULT NULL,
    p_min_height_m DOUBLE PRECISION DEFAULT NULL
)
```

Converts GeoJSON Polygon/MultiPolygon to PostGIS geometry and upserts into `campaign_buildings`.

## Edge Function: `campaign-sync-buildings`

**Location:** `supabase/functions/campaign-sync-buildings/index.ts`

**Purpose:** Sync building polygons for all addresses in a campaign

**Input:**
```json
{
  "campaign_id": "uuid-string"
}
```

**Output:**
```json
{
  "campaign_id": "uuid-string",
  "processed": 42,
  "created": 35,
  "updated": 7,
  "skipped": 0,
  "errors": 0
}
```

**Process:**
1. Fetches all `campaign_addresses` for the campaign
2. For each address, reuses `tiledecode_buildings` logic to fetch building polygon from Mapbox
3. Upserts into `campaign_buildings` table via `fn_upsert_campaign_building` RPC
4. Returns summary of sync operation

**Reuses Logic:**
- Mapbox tile decoding from `tiledecode_buildings` function
- Polygon selection (contains > nearest > largest)
- Style template resolution
- Fallback to streets-v11 tileset

## iOS Integration

### CampaignBuildingsAPI

**Location:** `FLYR/Features/Campaigns/API/CampaignBuildingsAPI.swift`

**Models:**
- `CampaignBuilding`: Cached building with geometry, height, etc.
- `SyncResult`: Summary of sync operation

**Methods:**
- `fetchBuildings(campaignId:)` → `[CampaignBuilding]`
  - Queries `campaign_buildings` table with `ST_AsGeoJSON(geometry)` to convert PostGIS to GeoJSON
  - Returns array of buildings with decoded geometry
  
- `triggerSyncBuildings(campaignId:)` → `SyncResult`
  - Calls Edge Function `campaign-sync-buildings`
  - Returns sync summary

### MapController Integration

**Location:** `FLYR/Features/Map/Controllers/MapController.swift`

**Updated Method:** `addCampaignAddressBuildings(to:campaignId:targetAddressIds:)`

**New Flow:**
1. Fetch cached buildings from `CampaignBuildingsAPI.shared.fetchBuildings(campaignId:)`
2. If empty, trigger sync via `CampaignBuildingsAPI.shared.triggerSyncBuildings(campaignId:)` then refetch
3. Filter by `targetAddressIds` if provided
4. Build `GeoJSONFeatureCollection` from buildings
5. Convert to Mapbox `FeatureCollection` format
6. Create `GeoJSONSource` with unique ID: `"flyr-campaign-buildings-{campaignId}"`
7. Create `FillExtrusionLayer` on that source:
   - Red color (`systemRed`)
   - 0.85 opacity
   - Height from `height_m` property (fallback: 18.0)
   - Base from `min_height_m` property (fallback: 0.0)
8. Add layer above dimmed buildings layer

**Removed:**
- All `queryRenderedFeatures` logic
- Building ID collection from rendered features
- Filter expressions on composite source
- Camera waiting and tile loading delays

## Migration Notes

### For Existing Campaigns

1. **First time opening a campaign map:**
   - iOS detects no cached buildings
   - Automatically triggers sync
   - Sync may take 10-30 seconds depending on address count
   - Buildings appear after sync completes

2. **Subsequent opens:**
   - Buildings load immediately from cache
   - No sync needed unless addresses change

### For New Campaigns

- Buildings are synced automatically when map is first opened
- Can also trigger sync manually via `CampaignBuildingsAPI.triggerSyncBuildings()`

## Self-Healing

If a campaign has addresses but no cached buildings:
- iOS automatically triggers sync when map opens
- Edge Function processes all addresses and caches buildings
- Next map open uses cached buildings (fast)

## Performance

**Old Flow:**
- ~2-5 seconds per address (query + wait for tiles)
- 100 addresses = 200-500 seconds total
- Inconsistent results

**New Flow:**
- Sync: ~0.5-1 second per address (one-time)
- Render: <100ms (fetch from Supabase + create GeoJSON source)
- Consistent results every time

## 3D Rendering

**Goal:** Full 3D app with:
- Dark base style
- Dimmed 3D gray buildings for background (`crushSurroundings`)
- Red 3D buildings for campaign targets (from cached `campaign_buildings` source)
- No 2D rectangles or polygons

**Implementation:**
- Only `FillExtrusionLayer` is used for campaign buildings
- Old 2D highlight layers have been removed from `MapController`
- All rendering is 3D extrusions

## Fallback Behavior

**Optional (not implemented):**
- If sync fails or returns no buildings for some addresses
- Can fall back to `queryRenderedFeatures` for those addresses only
- Convert polygons to GeoJSON and send back to Supabase
- Keeps system self-healing over time

## Files Changed

1. **Supabase:**
   - `supabase/migrations/20250125000002_create_campaign_buildings.sql` - Table + RPC
   - `supabase/functions/campaign-sync-buildings/index.ts` - Edge Function

2. **iOS:**
   - `FLYR/Features/Campaigns/API/CampaignBuildingsAPI.swift` - New API client
   - `FLYR/Features/Map/Controllers/MapController.swift` - Refactored building rendering

3. **Documentation:**
   - `docs/campaign_buildings_flow.md` - This file

## Testing

1. **Sync Test:**
   - Create a campaign with addresses
   - Open campaign map
   - Verify sync is triggered automatically
   - Check `campaign_buildings` table in Supabase

2. **Render Test:**
   - Open campaign map (after sync)
   - Verify red 3D buildings appear
   - Verify buildings match addresses
   - Verify no queryRenderedFeatures calls in logs

3. **Performance Test:**
   - Compare old vs new map open time
   - Verify consistent building rendering
   - Test with large campaigns (100+ addresses)









