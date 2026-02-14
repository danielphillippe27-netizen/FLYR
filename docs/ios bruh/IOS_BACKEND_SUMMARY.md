# Backend Summary for iOS Developer

## Files You Need to Know About

### 1. Building API Endpoint
**File**: `app/api/campaigns/[campaignId]/buildings/route.ts`

**What it does**:
- Fetches building GeoJSON from S3 (flyr-snapshots bucket)
- Decompresses gzip content
- Returns clean GeoJSON to iOS

**Key code**:
```typescript
// Fetches from S3 using AWS SDK
const command = new GetObjectCommand({
  Bucket: snapshot.bucket,      // "flyr-snapshots"
  Key: snapshot.buildings_key,  // "campaigns/{uuid}/buildings.json.gz"
});

// Decompresses gzip
const decompressed = gunzipSync(Buffer.from(bodyBuffer));
const geojson = JSON.parse(decompressed.toString('utf-8'));
```

**Response**: GeoJSON FeatureCollection with building footprints

---

### 2. Address API Endpoint
**File**: `app/api/campaigns/[campaignId]/addresses/route.ts`

**What it does**:
- Queries `campaign_addresses` table in Supabase
- Converts PostGIS geometry to GeoJSON Points
- Returns array of address features

**Key code**:
```typescript
const addresses = await CampaignsService.fetchAddresses(campaignId);

// Transforms to GeoJSON with Point geometry
const features = addresses.map((address) => ({
  type: 'Feature',
  geometry: { type: 'Point', coordinates: [lon, lat] },
  properties: {
    id: address.id,
    formatted: address.formatted,
    visited: address.visited,
    house_bearing: address.house_bearing,  // For icon rotation
    road_bearing: address.road_bearing,
  }
}));
```

**Response**: Array of GeoJSON Point features

---

### 3. Lambda Service (S3 Snapshot Generation)
**File**: `lib/services/TileLambdaService.ts`

**What it does**:
- Calls AWS Lambda to generate campaign snapshots
- Lambda queries Overture data from `flyr-data-lake`
- Writes compressed GeoJSON to `flyr-snapshots` S3 bucket

**Key flow**:
```
Provision Request
      │
      ▼
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Lambda    │───▶│ flyr-data-lake│───▶│ Overture    │
│   Function  │    │  (S3 Tiles)   │    │  Buildings  │
└─────────────┘    └──────────────┘    └─────────────┘
      │
      ▼
┌─────────────┐
│ flyr-snapshots│  ← 30-day TTL
│  buildings/   │
│  campaigns/   │
│  {uuid}/      │
│    buildings.json.gz
│    addresses.json.gz
│    roads.json.gz
└─────────────┘
```

**Environment Variables**:
- `SLICE_LAMBDA_URL`: Lambda function URL
- `SLICE_SHARED_SECRET`: Auth secret

---

### 4. Provision API
**File**: `app/api/campaigns/provision/route.ts`

**What it does**:
- Triggers the Lambda to create snapshots
- Stores metadata in `campaign_snapshots` table
- Runs spatial linking (matches addresses to buildings)

**When called**: During campaign creation in web app

---

### 5. Database Schema
**File**: `supabase/migrations/20251216000000_add_campaign_snapshot_columns.sql`

**Key Tables**:

#### `campaign_snapshots`
```sql
- campaign_id: UUID (links to campaigns)
- bucket: "flyr-snapshots"
- buildings_key: S3 key for buildings file
- buildings_url: Presigned S3 URL (expires in 1 hour)
- buildings_count: Number of buildings
- expires_at: 30 days from creation
```

#### `campaign_addresses`
```sql
- id: UUID
- campaign_id: UUID
- gers_id: String (matches building)
- formatted: String (display address)
- geom: PostGIS Point
- house_bearing: Float (rotation angle)
- road_bearing: Float (street angle)
- visited: Boolean
- status: String (new, visited, hot, etc.)
```

#### `building_stats`
```sql
- gers_id: String (links to building)
- campaign_id: UUID
- status: String (not_visited, visited, hot)
- scans_total: Integer
- last_scan_at: Timestamp
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │  S3: flyr-data- │    │  S3: flyr-      │    │  Supabase       │         │
│  │  lake           │    │  snapshots      │    │  PostgreSQL     │         │
│  │                 │    │                 │    │                 │         │
│  │  Master tiles   │    │  Campaign data  │    │  campaign_      │         │
│  │  (Overture)     │    │  (30-day TTL)   │    │  addresses      │         │
│  │                 │    │                 │    │  building_stats │         │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘         │
│         ▲                      ▲                      ▲                    │
│         │                      │                      │                    │
│         │ Lambda queries       │ API fetches          │ Realtime sub       │
│         │                      │                      │                    │
│  ┌──────┴──────────────────────┴──────────────────────┴─────────────────┐  │
│  │                                                                      │  │
│  │                    iOS APP                                           │  │
│  │                                                                      │  │
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────────────┐  │  │
│  │  │ GET /buildings│  │ GET /addresses│  │ Supabase Realtime       │  │  │
│  │  │ (S3 proxy)    │  │ (Supabase)    │  │ (building_stats)        │  │  │
│  │  └───────┬───────┘  └───────┬───────┘  └───────────┬─────────────┘  │  │
│  │          │                  │                      │                │  │
│  │          ▼                  ▼                      ▼                │  │
│  │  ┌─────────────────────────────────────────────────────────────┐    │  │
│  │  │                     Mapbox Map                              │    │  │
│  │  │  ┌─────────────────┐      ┌─────────────────┐              │    │  │
│  │  │  │ FillExtrusion   │      │ SymbolLayer     │              │    │  │
│  │  │  │ (3D Buildings)  │      │ (Address Pins)  │              │    │  │
│  │  │  │ - height_m      │      │ - bearing       │              │    │  │
│  │  │  │ - gers_id       │      │ - visited color │              │    │  │
│  │  │  └─────────────────┘      └─────────────────┘              │    │  │
│  │  └─────────────────────────────────────────────────────────────┘    │  │
│  │                              ▲                                      │  │
│  │                              │ Toggle                               │  │
│  │                         ┌────┴────┐                                 │  │
│  │                         │ UISegmentedControl                      │  │
│  │                         │ [Buildings|Addresses|Both]              │  │
│  │                         └─────────┘                                 │  │
│  │                                                                      │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Points for iOS Implementation

### 1. Always Use API Endpoints

**DON'T** fetch directly from S3:
```swift
// ❌ Wrong - URL expires after 1 hour
let s3Url = "https://flyr-snapshots.s3..."
```

**DO** use the API:
```swift
// ✅ Correct - API handles URL refresh
let url = "https://flyrpro.app/api/campaigns/\(id)/buildings"
```

### 2. GERS ID is the Link

Everything connects via `gers_id`:
- Building in S3 GeoJSON: `feature.id` and `properties.gers_id`
- Address in Supabase: `campaign_addresses.gers_id`
- Stats in Supabase: `building_stats.gers_id`

### 3. Building Heights

Building height comes from Overture data:
- `height_m`: Meters (use for fill-extrusion)
- `levels`: Number of floors (optional fallback)

### 4. Address Rotation

Addresses have bearing for icon rotation:
- `house_bearing`: Angle to face the street
- `road_bearing`: Street angle

### 5. Color Priority

Building colors (highest to lowest priority):
1. **Yellow** (`#facc15`): QR scanned (`scans_total > 0`)
2. **Blue** (`#3b82f6`): Hot lead (`status == "hot"`)
3. **Green** (`#22c55e`): Visited (`status == "visited"`)
4. **Red** (`#ef4444`): Default not visited

---

## Testing Checklist

- [ ] Toggle between Buildings/Addresses/Both modes
- [ ] Buildings show 3D extrusion with correct heights
- [ ] Address pins rotate to face street (using `house_bearing`)
- [ ] Building colors update in real-time when QR scanned
- [ ] Map zooms to fit all features on load
- [ ] Works with 1000+ buildings (performance test)

---

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Buildings not showing | `promoteId` not set | Add `source.promoteId = .string("gers_id")` |
| Colors not updating | Missing realtime sub | Subscribe to `building_stats` table |
| Address pins wrong rotation | Using wrong bearing | Use `house_bearing` not `road_bearing` |
| API returns empty | Campaign not provisioned | Check `provision_status = 'ready'` |
| 3D buildings flat | Missing height expression | Set `layer.fillExtrusionHeight` |
