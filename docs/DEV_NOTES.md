# Map Pro Mode Tilequery - Developer Notes

## Overview

Map Pro Mode exclusively uses a server-side Mapbox Tilequery workflow. Building polygons are fetched via Edge Function, cached in Supabase, and rendered from the database. All camera-based queries (`queryRenderedFeatures`) have been removed.

## Architecture

### Flow

1. **Client loads campaign** → fetches address list (id + lat/lon)
2. **Client calls Edge Function** → `ensureBuildingPolygons` with address coordinates
3. **Edge Function processes** → calls Mapbox Tilequery for each coordinate, selects best building polygon, upserts to DB
4. **Client fetches from DB** → reads polygons from `building_polygons` table
5. **Client renders** → polygons via GeoJSON source + FillLayer + LineLayer
6. **Fallback** → if polygon missing, render small proxy circle (3-4m radius)

### Database Schema

**Table**: `building_polygons`
- `id UUID PK`
- `address_id UUID UNIQUE NOT NULL` (FK to `campaign_addresses.id`)
- `source TEXT NOT NULL` default `'mapbox_tilequery'`
- `geom JSONB NOT NULL` (GeoJSON Feature with Polygon/MultiPolygon)
- `area_m2 DOUBLE PRECISION NOT NULL`
- `centroid_lnglat GEOGRAPHY(Point,4326)` (optional)
- `bbox JSONB` (minLng, minLat, maxLng, maxLat)
- `properties JSONB` (raw Mapbox properties)
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

**Indexes**:
- UNIQUE on `address_id`
- GIN on `geom`
- btree on `area_m2`

**RLS Policies**:
- SELECT: authenticated users
- INSERT/UPDATE: service role only (Edge Function)

## Environment Variables

### Supabase Secrets

Set the Mapbox access token in Supabase:

```bash
supabase secrets set MAPBOX_ACCESS_TOKEN=your_mapbox_token_here
```

The Edge Function reads this via `Deno.env.get("MAPBOX_ACCESS_TOKEN")`.

## Edge Function

### Endpoint

`POST /functions/v1/tilequery_buildings`

### Request Body

```json
{
  "addresses": [
    {
      "id": "uuid-string",
      "lat": 43.6532,
      "lon": -79.3832
    }
  ]
}
```

### Response

```json
{
  "created": 5,
  "updated": 0,
  "proxies": 2,
  "requested": 7,
  "matched": 5,
  "errors": 0,
  "results": [
    {
      "address_id": "uuid-string",
      "matched": true,
      "selection": "contains",
      "area_m2": 123.4
    }
  ]
}
```

### Selection Rules

The Edge Function selects the best building polygon using this priority:

1. **Contains**: Polygons that contain the (lon, lat) point
   - If multiple, choose largest area
   - Selection: `"contains"`

2. **Nearby**: Polygons whose centroid is within ≤15m of the point
   - Choose nearest centroid
   - Selection: `"nearby"`

3. **Largest**: If no containing or nearby polygons, choose largest area
   - Selection: `"largest"`

4. **Retry**: If no candidates found, retry with radius 35m once

### Batch Processing

- Processes addresses in batches of 10 parallel requests
- 150ms delay between batches
- Handles Mapbox rate limits (429) with exponential backoff (1s, 2s)

### Example cURL

```bash
curl -X POST \
  'https://your-project.supabase.co/functions/v1/tilequery_buildings' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "addresses": [
      {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "lat": 43.6532,
        "lon": -79.3832
      }
    ]
  }'
```

## Client API

### BuildingsAPI.swift

#### `ensureBuildingPolygons(addresses:)`

Ensures building polygons are cached for given addresses.

- Chunks addresses to 40 per call
- Calls Edge Function with authenticated session
- Returns `TilequeryResponse` with statistics

#### `fetchBuildingPolygons(addressIds:)`

Fetches building polygons from database.

- Calls RPC `get_buildings_by_address_ids`
- Returns `GeoJSONFeatureCollection`

## Integration

### UseCampaignMap.swift

**Highlight Mode**: `.mapboxProTilequery` (default, only mode available)

The `loadFootprints()` method:

1. After `loadHomes` completes
2. Calls `ensureBuildingPolygons` → Edge Function processes and caches
3. Calls `fetchBuildingPolygons` → fetch from DB
4. Converts `GeoJSONFeatureCollection` to Mapbox `FeatureCollection`
5. Renders polygons + proxy circles for misses

**Note**: All camera-based query logic has been removed. No zoom checks, visibility checks, or `queryRenderedFeatures` calls.

### Rendering

- **Fill**: white, 35% opacity
- **Outline**: black, 1.0 width, 90% opacity
- **Layer ordering**: above basemap buildings
- **Proxy circles**: 3.5m radius for missing polygons

## Known Limits

1. **Rural Areas**: Many addresses may return `matched=false` → client shows proxies only
2. **Rate Limits**: Mapbox Tilequery has rate limits; Edge Function handles 429 with backoff
3. **Idempotency**: Calling `ensureBuildingPolygons` twice is safe; second run yields mostly `updated=0, created=0`
4. **Performance**: 50 addresses complete under a few seconds (batching parallelism 10)
5. **No Camera Dependencies**: Building polygons load independently of map zoom level or camera position

## Future Enhancements

1. **Retry Logic**: Enhanced retry with exponential backoff for failed addresses
2. **Caching Strategies**: Client-side caching of fetched polygons
3. **Incremental Updates**: Only fetch missing polygons on subsequent loads
4. **Selection Metrics**: Track selection method distribution for analytics
5. **Batch Size Tuning**: Adjustable batch size based on network conditions

## Troubleshooting

### Edge Function Returns 401

- Verify authentication header is present
- Check Supabase session is valid

### No Polygons Returned

- Check Mapbox token is set: `supabase secrets list`
- Verify addresses have valid coordinates
- Check Edge Function logs for Tilequery errors

### Database Upsert Fails

- Verify RLS policies allow service role writes
- Check `building_polygons` table exists
- Verify `address_id` references valid `campaign_addresses.id`

## Migration Notes

- `building_polygons` table is separate from `address_buildings` table
- `address_buildings` uses `address_key` (formatted + postal)
- `building_polygons` uses `address_id` (UUID FK to `campaign_addresses.id`)
- Both tables coexist for backward compatibility

