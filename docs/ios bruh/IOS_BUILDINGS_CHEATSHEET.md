# iOS Buildings Workflow - Quick Cheatsheet

## The Golden Rule

```
┌─────────────────────────────────────────────────────────────┐
│  iOS App → API → S3 (buildings)                             │
│         → Supabase (realtime stats)                         │
│                                                             │
│  Buildings NEVER come from Supabase directly!               │
│  They come from S3 via the API proxy.                       │
└─────────────────────────────────────────────────────────────┘
```

## Data Sources

| What | Where | iOS Gets It From |
|------|-------|------------------|
| Building footprints | S3 (flyr-snapshots) | `GET /api/campaigns/{id}/buildings` |
| Building height | S3 GeoJSON properties | Same API call |
| Address text | S3 GeoJSON properties | Same API call |
| Scan count | Supabase (building_stats) | Realtime subscription |
| Status color | Supabase (building_stats) | Realtime subscription |
| Roads | S3 (flyr-snapshots) | `GET /api/campaigns/{id}/roads` |

## The GERS ID Chain

```
S3 Building GeoJSON           Supabase Stats              iOS Map
───────────────────           ──────────────              ───────
id: "abc123"          ←──────  gers_id: "abc123"   ←────  Feature State
properties: {                    status: "visited"          Color: GREEN
  gers_id: "abc123"              scans_total: 5
  height_m: 8.5
}
```

## Code Patterns

### 1. Fetch Buildings

```swift
let url = "https://flyrpro.app/api/campaigns/\(campaignId)/buildings"
let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
let geoJSON = try JSONDecoder().decode(BuildingsResponse.self, from: data)
```

### 2. Add to Mapbox

```swift
// MUST set promoteId for feature state to work
var source = GeoJSONSource()
source.data = .featureCollection(featureCollection)
source.promoteId = .string("gers_id")  // ← CRITICAL!

try mapView.mapboxMap.style.addSource(source, id: "buildings")

var layer = FillExtrusionLayer(id: "buildings-3d")
layer.source = "buildings"
layer.fillExtrusionHeight = .expression(Exp(.get) { "height_m" })
layer.fillExtrusionColor = .expression(colorExpression)
```

### 3. Realtime Updates

```swift
supabase.channel("buildings-\(campaignId)")
    .on("postgres_changes", filter: .eq("campaign_id", campaignId), 
        table: "building_stats") { payload in
        
        let gersId = payload.new["gers_id"] as? String
        let scans = payload.new["scans_total"] as? Int ?? 0
        
        // Update color instantly
        mapView.mapboxMap.setFeatureState(
            sourceId: "buildings",
            featureId: gersId!,
            state: ["scans_total": scans]
        )
    }
    .subscribe()
```

### 4. Color Expression

```swift
let colorExpression = Exp(.switchCase) {
    // 1. Scanned = YELLOW (highest priority)
    Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
    UIColor(hex: "#facc15")
    
    // 2. Hot = BLUE
    Exp(.eq) { Exp(.get) { "status" }; "hot" }
    UIColor(hex: "#3b82f6")
    
    // 3. Visited = GREEN
    Exp(.eq) { Exp(.get) { "status" }; "visited" }
    UIColor(hex: "#22c55e")
    
    // 4. Default = RED
    UIColor(hex: "#ef4444")
}
```

## GeoJSON Properties Reference

```json
{
  "type": "Feature",
  "id": "08a2b4c5d6e7f8g9h0i",     // ← Same as gers_id
  "geometry": { "type": "Polygon", ... },
  "properties": {
    "gers_id": "08a2b4c5d6e7f8g9h0i",  // ← Use this for everything
    "height_m": 8.5,                      // ← For 3D extrusion
    "levels": 2,                          // ← Number of floors
    "address_text": "123 Main St",        // ← Display address
    "feature_status": "linked"            // ← "linked" or "orphan_building"
  }
}
```

## Lifecycle Flow

```
User creates campaign (Web)
        │
        ▼
┌──────────────────┐
│  Lambda queries  │  ← flyr-data-lake (Overture data)
│  Overture data   │
└──────────────────┘
        │
        ▼
┌──────────────────┐
│  Writes to S3    │  ← flyr-snapshots bucket
│  (30-day TTL)    │
└──────────────────┘
        │
        ▼
┌──────────────────┐
│  Supabase stores │  ← campaign_snapshots table
│  metadata only   │    (URLs, counts, keys)
└──────────────────┘
        │
        ▼
iOS requests buildings  ← GET /api/campaigns/{id}/buildings
        │
        ▼
┌──────────────────┐
│  API fetches     │  ← From S3, decompresses gzip
│  from S3         │
└──────────────────┘
        │
        ▼
iOS renders with Mapbox  ← FillExtrusionLayer
        │
        ▼
iOS subscribes to realtime  ← building_stats table
        │
        ▼
Colors update instantly  ← setFeatureState()
```

## Common Mistakes

| ❌ Wrong | ✅ Right |
|----------|----------|
| Query `buildings` table in Supabase | Use `/api/campaigns/{id}/buildings` endpoint |
| Use direct S3 URLs | Use API endpoint (handles URL refresh) |
| Forget `promoteId` | Always set `source.promoteId = .string("gers_id")` |
| Re-add source on update | Use `setFeatureState()` for color changes |
| Query `feature.id` for stats | Query by `gers_id` in `building_stats` |

## Debug Checklist

Buildings not showing?
1. ✅ Is campaign provisioned? (check `provision_status = 'ready'`)
2. ✅ Does `campaign_snapshots` have `buildings_key`?
3. ✅ Is API returning valid GeoJSON?
4. ✅ Are features being parsed correctly?
5. ✅ Is Mapbox source added with correct ID?

Colors not updating?
1. ✅ Is `promoteId` set to `"gers_id"`?
2. ✅ Is realtime subscription active?
3. ✅ Does `building_stats` have rows for this campaign?
4. ✅ Are you calling `setFeatureState` with correct `gers_id`?

---

**Remember**: Buildings live in S3, stats live in Supabase, colors come from combining both!
