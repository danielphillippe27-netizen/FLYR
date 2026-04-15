# Campaign-Scoped Road Architecture Implementation Summary

## Overview

This implementation establishes a new campaign-scoped road architecture for FLYR Pro GPS Normalization Mode, with the following key characteristics:

- **Mapbox** = External road geometry source (ingestion only)
- **Supabase campaign_roads** = Canonical per-campaign store
- **Local device cache** = Offline mirror (non-authoritative)
- **Sessions** use preloaded roads only (zero API calls during tracking)

## Files Created

### Supabase Migrations

1. **`supabase/migrations/20250316_campaign_roads_architecture.sql`**
   - Creates `campaign_roads` table (canonical campaign-scoped road storage)
   - Creates `campaign_road_metadata` table (status tracking)
   - Adds RPC functions:
     - `rpc_get_campaign_roads_v2` - Get roads as GeoJSON
     - `rpc_get_campaign_road_metadata` - Get preparation status
     - `rpc_upsert_campaign_roads` - Atomic refresh
     - `rpc_update_road_preparation_status` - Status updates

### Swift Services

2. **`FLYR/Services/CampaignRoadService.swift`**
   - `CampaignRoadService` - Main service for campaign road management
   - `CampaignRoadStatus` - Preparation status enum
   - `CampaignRoadMetadata` - Metadata model
   - `MapboxRoadGeometryProvider` - Mapbox tilequery-based road fetching
   - `RoadGeometryProvider` - Protocol for alternative providers

3. **`FLYR/Services/CampaignRoadDeviceCache.swift`**
   - `CampaignRoadDeviceCache` - Actor-based local file cache
   - `LocalRoadCacheMetadata` - Cache metadata
   - TTL support (30 days default)
   - Size management (100MB default)

### UI Components

4. **`FLYR/Features/Campaigns/Components/CampaignRoadSettingsView.swift`**
   - `CampaignRoadSettingsView` - Settings UI for road refresh
   - `CampaignRoadSettingsViewModel` - View model
   - Status display, refresh button, confirmation dialogs

5. **`FLYR/Features/Map/GPSNormalization/GPSNormalizationDebugView.swift`**
   - Debug overlay for Pro GPS Normalization
   - Raw vs normalized point counts
   - Rejection reasons
   - Campaign road status

## Files Modified

### 1. `FLYR/Services/MapFeaturesService.swift`

**Changes:**
- Replaced legacy `fetchCampaignRoads()` method
- Removed `fetchMapboxRoadsFallback()` method
- Removed `estimateCampaignRadiusMeters()` method
- Now uses `CampaignRoadService.shared.getRoadsForSession()` which:
  1. Checks local device cache first (fast, offline)
  2. Falls back to Supabase canonical store
  3. Zero Mapbox API calls during session loading
- Added `buildGeoJSONCoordinates()` helper

**Before:**
```swift
func fetchCampaignRoads(campaignId: String) async {
    // Direct Supabase query with Mapbox fallback
}
```

**After:**
```swift
func fetchCampaignRoads(campaignId: String) async {
    // Uses CampaignRoadService (cache -> Supabase, no Mapbox)
    let corridors = await CampaignRoadService.shared.getRoadsForSession(...)
}
```

### 2. `FLYR/Features/Map/SessionManager.swift`

**Changes:**
- Updated `startBuildingSession()` to load roads from `CampaignRoadService`
- Added proper logging for road loading
- Shows error if roads not available
- Zero network calls during session tracking

**Key logging added:**
```
🛣️ [SessionManager] Loading roads for campaign XXX...
✅ [SessionManager] Loaded X roads from cache
🛣️ [SessionManager] Corridors built: X
🚫 [SessionManager] No road network calls during active tracking
```

### 3. `FLYR/Feautures/Campaigns/Hooks/UseCreateCampaign.swift`

**Changes:**
- Added `isPreparingRoads` and `preparationProgress` published properties
- Added `polygon` parameter to `createV2()` and `create()` methods
- Added `prepareCampaignRoads()` method
- Road preparation runs after campaign creation
- Progress updates during preparation

**New logging:**
```
🛣️ [CampaignCreation] Preparing campaign roads for XXX
🛣️ [CampaignCreation] Fetching roads from Mapbox for bounds: ...
✅ [CampaignRoadService] Stored X roads in Supabase for campaign XXX
✅ [CampaignCreation] Campaign ready with X roads cached
```

## Architecture Flow

### Campaign Creation Flow

```
User draws campaign polygon
    ↓
Campaign created in Supabase
    ↓
prepareCampaignRoads() called
    ↓
MapboxRoadGeometryProvider.fetchRoads(in: bounds)
    ↓
Grid sampling of polygon area
    ↓
Tilequery API calls (rate limited)
    ↓
Deduplicated roads
    ↓
rpc_upsert_campaign_roads() (atomic)
    ↓
campaign_roads table populated
    ↓
campaign_road_metadata updated (status: ready)
    ↓
Local device cache mirrored
    ↓
Campaign ready for sessions
```

### Session Start Flow

```
startBuildingSession() called
    ↓
CampaignRoadService.getRoadsForSession()
    ↓
Check CampaignRoadDeviceCache (local file)
    ↓
If cache hit AND valid: return corridors
    ↓
If cache miss/expired:
    ↓
    rpc_get_campaign_roads_v2()
    ↓
    Store in local cache
    ↓
Return corridors
    ↓
Build StreetCorridors
    ↓
Initialize SessionTrailNormalizer
    ↓
Session active (zero API calls)
```

### Manual Refresh Flow

```
User taps "Refresh Roads" in settings
    ↓
Confirmation dialog
    ↓
refreshCampaignRoads() called
    ↓
Fetch from Mapbox
    ↓
rpc_upsert_campaign_roads() (atomic replace)
    ↓
Update local cache
    ↓
UI shows updated status
```

## Key Features

### 1. Deterministic Runtime Behavior
- No hidden fallback logic
- Session road loading is deterministic: cache → Supabase
- Clear error if roads unavailable

### 2. Offline Support
- Local device cache mirrors Supabase data
- Cache TTL: 30 days
- Sessions work offline after initial preload

### 3. Atomic Updates
- Road refresh is atomic (upsert RPC)
- Old data preserved until new data successfully stored
- Failed refresh doesn't break existing data

### 4. Versioning
- `cache_version` incremented on each refresh
- `corridor_build_version` for algorithm changes
- Client can detect stale data

### 5. Status Tracking
- `pending` → `fetching` → `ready` | `failed`
- Error messages stored
- Retry count tracked

### 6. Rate Limiting
- Mapbox Tilequery: 600 req/min
- 100ms delay every 10 requests
- Grid sampling with spacing control

## Configuration

### GPSNormalizationConfig (existing)
```swift
maxHorizontalAccuracy: 20          // meters
minMovementDistance: 3             // meters
maxLateralDeviation: 10            // meters
preferredSideOffset: 7             // meters
maxWalkingSpeedMetersPerSecond: 2.2
smoothingWindow: 3                 // points
backwardToleranceMeters: 8         // meters
simplificationToleranceMeters: 1.5 // meters
```

### Cache Config (new)
```swift
defaultTTLDays = 30
maxCacheSizeMB = 100
```

## Testing

### Unit Tests
Add to `FLYRTests/GPSNormalizationTests.swift`:
- Campaign road caching
- Local device cache
- Cache expiration
- Version tracking

### Manual Testing
1. Create campaign with polygon
2. Verify road preparation logs
3. Start session, verify zero Mapbox calls
4. Turn off network, verify offline session works
5. Refresh roads in settings
6. Verify version increment

## Migration Path

### For Existing Campaigns
1. Campaigns without roads will show "Roads Pending"
2. User can manually refresh in settings
3. Or app can auto-refresh on first open

### For Web-Created Campaigns
1. Web should call same `rpc_upsert_campaign_roads`
2. iOS will mirror to local cache on first open
3. Shared canonical store ensures consistency

## Debugging

### Console Logs
All components log with prefixes:
- `🛣️ [CampaignRoadService]` - Road service
- `✅ [CampaignRoadService]` - Success
- `❌ [CampaignRoadService]` - Errors
- `🛣️ [CampaignCreation]` - Campaign creation
- `🛣️ [SessionManager]` - Session startup
- `📍 [GPSNorm]` - Normalization

### Debug View
`GPSNormalizationDebugView` shows:
- Raw vs normalized point counts
- Active corridors
- Side-of-street state
- Rejection reasons
- Campaign road status

## Acceptance Criteria

- [x] Campaign creation fetches roads from Mapbox
- [x] Campaign roads stored canonically in Supabase
- [x] Cross-platform consistency (web + iOS share Supabase)
- [x] Session uses preloaded roads only (zero per-point API calls)
- [x] Works offline after campaign preload
- [x] No old generic Supabase roads runtime dependency
- [x] Campaign settings has manual refresh
- [x] Road preparation supports status + versioning + TTL
- [x] Refresh is atomic and preserves old good data on failure
- [x] Campaign shows road preparation status
- [x] Session surfaces error if roads unavailable
- [x] Raw GPS preserved
- [x] Normalized GPS drives visible breadcrumb
- [x] Breadcrumb looks cleaner and sidewalk-biased
- [x] Debug mode can compare raw vs normalized

## TODO / Follow-up

1. **Web Implementation**
   - Implement same `rpc_upsert_campaign_roads` call in web app
   - Share road preparation logic

2. **Background Refresh**
   - Auto-refresh stale roads when app opens
   - Background fetch for campaign updates

3. **Smart Sampling**
   - Use campaign address density to optimize sampling
   - Skip low-density areas

4. **Corridor Optimization**
   - Pre-compute corridor graphs for navigation
   - Connected component analysis

5. **Analytics**
   - Track road cache hit rates
   - Measure preparation success rates
   - GPS normalization effectiveness

6. **Advanced GPS Features**
   - Predictive corridor switching
   - Multi-corridor interpolation
   - Building entrance snapping

## Assumptions Made

1. **Mapbox Token** - Assumes `MBXAccessToken` is in Info.plist
2. **Campaign Polygon** - Assumes polygon is available at creation time
3. **Supabase RLS** - Assumes proper RLS policies for campaign access
4. **Storage** - Uses file cache (not Core Data) for simplicity
5. **Tilequery** - Uses Mapbox Tilequery API (not Vector Tiles) for availability

## Limitations

1. **Tilequery Limits** - Max 600 req/min may limit very large campaigns
2. **Grid Sampling** - Fixed grid may miss some roads in irregular polygons
3. **No Real-time** - Roads don't update during session (by design)
4. **Single Source** - Only Mapbox supported (extensible via protocol)
5. **File Cache** - No encryption of local road cache
