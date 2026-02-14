# FLYR RPC Catalog

Reference for all Supabase RPC functions with inputs, outputs, and example responses.

## Map Feature RPCs

### Get Campaign Buildings

**`rpc_get_campaign_full_features(p_campaign_id UUID)`**

Returns all buildings for a campaign as GeoJSON FeatureCollection with address properties and status.

**Returns**: JSONB (GeoJSON FeatureCollection)

**Example Response**:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-79.123456, 35.789012], [-79.123400, 35.789012], ...]]
      },
      "properties": {
        "status": "delivered",
        "height": 10.5,
        "formatted": "123 Main St",
        "scans_total": 0,
        "gers_id": "abc123"
      }
    }
  ]
}
```

---

### Get Campaign Addresses

**`rpc_get_campaign_addresses(p_campaign_id UUID)`**

Returns all addresses for a campaign as GeoJSON FeatureCollection of Points.

**Returns**: JSONB (GeoJSON FeatureCollection)

**Example Response**:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "geometry": {
        "type": "Point",
        "coordinates": [-79.123456, 35.789012]
      },
      "properties": {
        "formatted": "123 Main St",
        "postal_code": "27701",
        "city": "Durham",
        "gers_id": "abc123"
      }
    }
  ]
}
```

---

### Get Campaign Roads

**`rpc_get_campaign_roads(p_campaign_id UUID)`**

Returns all roads for a campaign as GeoJSON FeatureCollection of LineStrings.

**Returns**: JSONB (GeoJSON FeatureCollection)

**Example Response**:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "770e8400-e29b-41d4-a716-446655440000",
      "geometry": {
        "type": "LineString",
        "coordinates": [[-79.123456, 35.789012], [-79.123500, 35.789100]]
      },
      "properties": {
        "name": "Main St",
        "road_class": "residential"
      }
    }
  ]
}
```

---

### Get Buildings in Bounding Box

**`rpc_get_buildings_in_bbox(min_lon FLOAT, min_lat FLOAT, max_lon FLOAT, max_lat FLOAT, p_campaign_id UUID)`**

Returns buildings within a bounding box (viewport-based loading).

**Returns**: JSONB (GeoJSON FeatureCollection, same structure as `rpc_get_campaign_full_features`)

---

### Get Addresses in Bounding Box

**`rpc_get_addresses_in_bbox(min_lon FLOAT, min_lat FLOAT, max_lon FLOAT, max_lat FLOAT, p_campaign_id UUID)`**

Returns addresses within a bounding box.

**Returns**: JSONB (GeoJSON FeatureCollection, same structure as `rpc_get_campaign_addresses`)

---

### Get Roads in Bounding Box

**`rpc_get_roads_in_bbox(min_lon FLOAT, min_lat FLOAT, max_lon FLOAT, max_lat FLOAT, p_campaign_id UUID)`**

Returns roads within a bounding box.

**Returns**: JSONB (GeoJSON FeatureCollection, same structure as `rpc_get_campaign_roads`)

---

### Get Buildings by Address IDs

**`get_buildings_by_address_ids(p_address_ids UUID[])`**

Returns building polygons for specific address IDs.

**Returns**: JSONB (GeoJSON FeatureCollection)

---

## Address Lookup RPCs

### Find Nearest Addresses

**`fn_addr_nearest_v2(p_lat FLOAT, p_lon FLOAT, p_limit INT, p_province TEXT)`**

Finds nearest addresses to a point, ordered by distance.

**Returns**: TABLE (address records)

**Example Response**:
```json
[
  {
    "id": "880e8400-e29b-41d4-a716-446655440000",
    "formatted": "123 Main St",
    "postal_code": "27701",
    "city": "Durham",
    "province": "NC",
    "geom": {...},
    "distance_m": 15.3
  }
]
```

---

### Find Same Street Addresses

**`fn_addr_same_street_v2(p_street TEXT, p_city TEXT, p_lon FLOAT, p_lat FLOAT, p_limit INT, p_province TEXT)`**

Finds addresses on the same street, ordered by proximity to reference point.

**Returns**: TABLE (address records)

**Example Response**: Same structure as `fn_addr_nearest_v2`

---

## Building Polygon Management

### Upsert Building Polygon

**`fn_upsert_building_polygon(p_address_id UUID, p_geom_json JSONB)`**

Inserts or updates a building polygon for an address. Converts GeoJSON to PostGIS geometry.

**Input**:
- `p_address_id`: Address UUID
- `p_geom_json`: GeoJSON geometry object (Polygon or MultiPolygon)

**Returns**: UUID (building_polygons.id)

**Example Input**:
```json
{
  "type": "Polygon",
  "coordinates": [[[-79.123, 35.789], [-79.122, 35.789], ...]]
}
```

---

### Upsert Address Building by Formatted Address

**`upsert_address_building_by_formatted(p_formatted TEXT, p_postal TEXT, p_building_id UUID, p_building_source TEXT, p_geojson JSONB)`**

Upserts building polygon using formatted address + postal code as lookup key.

**Returns**: UUID (building_polygons.id)

---

## Leaderboard & Stats RPCs

### Get Leaderboard

**`get_leaderboard(metric TEXT, timeframe TEXT)`**

Returns leaderboard rankings by metric and timeframe.

**Parameters**:
- `metric`: 'flyers', 'conversations', 'leads', 'distance'
- `timeframe`: 'daily', 'weekly', 'all_time'

**Returns**: TABLE

**Example Response**:
```json
[
  {
    "user_id": "990e8400-e29b-41d4-a716-446655440000",
    "rank": 1,
    "flyers": 150,
    "conversations": 25,
    "leads": 5,
    "distance_meters": 12500.0
  }
]
```

---

## Analytics RPCs

### Get Address Scan Count

**`get_address_scan_count(p_address_id UUID)`**

Returns total scan count for an address.

**Returns**: INT

---

### Get Campaign Scan Count

**`get_campaign_scan_count(p_campaign_id UUID)`**

Returns total scan count for a campaign.

**Returns**: INT

---

## Farm RPCs

### Update Farm Polygon

**`update_farm_polygon(p_farm_id UUID, p_polygon_geojson JSONB)`**

Updates a farm's polygon geometry from GeoJSON.

**Input**:
- `p_farm_id`: Farm UUID
- `p_polygon_geojson`: GeoJSON Polygon geometry

**Returns**: VOID

**Example Input**:
```json
{
  "type": "Polygon",
  "coordinates": [[[-79.1, 35.8], [-79.0, 35.8], [-79.0, 35.7], [-79.1, 35.7], [-79.1, 35.8]]]
}
```

---

## Utility Functions

### Generate Address Key

**`addr_key(p_formatted TEXT, p_postal TEXT)`**

Generates deterministic MD5 hash key from formatted address + postal code for deduplication.

**Returns**: TEXT (MD5 hash)

**Example**:
```sql
SELECT addr_key('123 Main St', '27701');
-- Returns: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
```

---

## RPC Call Patterns

### iOS Client Example

```swift
// Call RPC via SupabaseClientShim
let features = try await supabase
  .rpc("rpc_get_campaign_full_features", params: ["p_campaign_id": campaignId])
  .execute()
  .value

// Decode GeoJSON FeatureCollection
let featureCollection = try JSONDecoder().decode(
  FeatureCollection.self, 
  from: features
)
```

### Direct SQL Example

```sql
-- Call RPC from SQL
SELECT * FROM rpc_get_campaign_full_features('550e8400-e29b-41d4-a716-446655440000');

-- Call address lookup function
SELECT * FROM fn_addr_nearest_v2(35.789, -79.123, 10, 'NC');
```

---

## Important Notes

### GeoJSON Flexibility

- RPCs return GeoJSON as JSONB (can be object or array depending on PostGIS version)
- iOS client uses flexible decoding (tries object first, falls back to array)

### Geometry Type Filtering

- **Buildings**: ALWAYS filter to Polygon/MultiPolygon when rendering in Mapbox
- **Roads**: LineString only
- **Addresses**: Point only

### Performance

- Bounding box RPCs are optimized for viewport-based loading (use when zoomed in)
- Full campaign RPCs load all features (use for campaign overview)
- Spatial indexes (GIST) on all geometry columns ensure fast queries

### Error Handling

- Invalid UUID → Returns empty FeatureCollection
- Missing campaign_id → Returns empty FeatureCollection
- Invalid geometry → Throws PostGIS error (caught by client)
