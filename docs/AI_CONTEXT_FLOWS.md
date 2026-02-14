# FLYR Common Flows

Reference for end-to-end flows through the FLYR system, from user action to final result.

## Campaign Creation & Provisioning Flow

Complete flow from campaign creation to map rendering with 3D buildings.

### Step 1: User Creates Campaign

**User Action**: Taps "Create Campaign" button in iOS app

**iOS Code**:
```swift
// NewCampaignScreen.swift
Button("Create Campaign") {
  Task {
    await useCreateCampaign.createV2(
      name: "Durham Neighborhoods",
      type: .doorKnock,
      addressSource: .closestHome
    )
  }
}
```

### Step 2: Hook Coordinates Creation

**Hook Logic**:
```swift
// UseCreateCampaign.swift
@MainActor
class UseCreateCampaign: ObservableObject {
  func createV2(name: String, type: CampaignType, addressSource: AddressSource) async {
    isLoading = true
    
    let campaign = CampaignV2(
      id: UUID(),
      name: name,
      type: type,
      addressSource: addressSource
    )
    
    let result = try await campaignsAPI.createV2(campaign)
    store.append(result)
    
    isLoading = false
  }
}
```

### Step 3: API Inserts Campaign Record

**API Call**:
```swift
// CampaignsAPI.swift
func createV2(_ campaign: CampaignV2) async throws -> CampaignV2 {
  return try await supabase
    .from("campaigns")
    .insert(campaign.dbRow)
    .select()
    .single()
    .execute()
    .value
}
```

**Database**: Row inserted in `campaigns` table

### Step 4: Provision Campaign (Backend)

**User Action**: App automatically calls provision after campaign creation

**iOS Code**:
```swift
// After campaign created
try await campaignsAPI.provision(campaignId: campaign.id)
```

**Backend API** (`POST /api/campaigns/provision`):
1. Loads polygon from Supabase; calls Tile Lambda; Lambda reads S3 parquet, writes snapshot to S3
2. Backend ingests addresses into `campaign_addresses`, writes `campaign_snapshots`; runs StableLinker + TownhouseSplitter
3. Building geometry in S3; map fetches via GET `/api/campaigns/[id]/buildings`

### Step 5: iOS Fetches Map Data

**User Action**: User navigates to campaign map view

**iOS Code**:
```swift
// CampaignMapView.swift
.task {
  await mapFeaturesService.fetchAllCampaignFeatures(campaignId: campaign.id)
}
```

**Service Logic**:
```swift
// MapFeaturesService.swift
func fetchAllCampaignFeatures(campaignId: UUID) async throws {
  async let buildings = fetchBuildings(campaignId: campaignId)
  async let addresses = fetchAddresses(campaignId: campaignId)
  async let roads = fetchRoads(campaignId: campaignId)
  
  let (b, a, r) = try await (buildings, addresses, roads)
  
  await mapLayerManager.updateBuildings(features: b)
  await mapLayerManager.updateAddresses(features: a)
  await mapLayerManager.updateRoads(features: r)
}
```

**Supabase RPCs**:
- `rpc_get_campaign_full_features` → Buildings GeoJSON
- `rpc_get_campaign_addresses` → Addresses GeoJSON
- `rpc_get_campaign_roads` → Roads GeoJSON

### Step 6: Mapbox Renders Map

**MapLayerManager**:
```swift
func updateBuildings(features: FeatureCollection) {
  var source = GeoJSONSource(id: "buildingsSource")
  source.data = .featureCollection(features)
  
  try mapView.mapboxMap.updateGeoJSONSource(
    withId: "buildingsSource",
    geoJSON: source.data!
  )
}
```

**Result**: 3D buildings rendered on map with status-based colors (red = untouched)

---

## QR Code Scan Flow

Complete flow from QR code scan to building color update on map.

### Step 1: User Scans QR Code

**User Action**: Scans QR code with phone camera or QR scanner app

**QR Code URL**: `https://xxx.supabase.co/functions/v1/qr_redirect/q/abc123`

### Step 2: Edge Function Handles Redirect

**Edge Function** (`qr_redirect`):
```typescript
// Look up QR code by slug
const qrCode = await supabase
  .from('qr_codes')
  .select('*')
  .eq('slug', slug)
  .single()

// Log scan
await supabase
  .from('qr_code_scans')
  .insert({
    qr_code_id: qrCode.id,
    address_id: qrCode.address_id,
    scanned_at: new Date(),
    user_agent: req.headers.get('user-agent'),
    ip_address: req.headers.get('x-forwarded-for')
  })

// Redirect to landing page
return Response.redirect(qrCode.landing_page_url, 302)
```

**Database Triggers**:
- Insert into `qr_code_scans` triggers update to `building_stats.scans_total`
- Update to `building_stats` triggers update to `user_stats.flyers`

### Step 3: iOS Polls for Updates

**iOS Code** (adaptive polling):
```swift
// CampaignMapView.swift
.task {
  while !Task.isCancelled {
    await mapFeaturesService.fetchBuildings(campaignId: campaign.id)
    
    // Adaptive polling: faster when activity detected
    let interval = recentScans > 0 ? 5.0 : 30.0
    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
  }
}
```

**Alternative**: Real-time subscription (future enhancement)
```swift
// Real-time updates via Supabase
supabase
  .from("building_stats")
  .on(.update) { payload in
    // Update feature state immediately
  }
```

### Step 4: MapLayerManager Updates Building Color

**iOS Code**:
```swift
// Update feature state for instant color change
try mapView.mapboxMap.setFeatureState(
  sourceId: "buildingsSource",
  featureId: addressId.uuidString,
  state: ["scans_total": 1, "status": "none"]
)
```

**Result**: Building changes from red (untouched) to yellow (QR scanned)

---

## Address Status Update Flow

Complete flow from user tapping building to status change and color update.

### Step 1: User Taps Building on Map

**User Action**: Taps on 3D building in map view

**iOS Code**:
```swift
// CampaignMapView.swift
mapView.gestures.onMapTap.observe { context in
  let features = try? mapView.mapboxMap.queryRenderedFeatures(
    with: context.point,
    options: RenderedQueryOptions(
      layerIds: ["buildingsExtrusionLayer"],
      filter: nil
    )
  )
  
  if let feature = features?.first {
    selectedAddressId = UUID(uuidString: feature.identifier as! String)
    showStatusSheet = true
  }
}
```

### Step 2: User Selects Status

**User Action**: Selects "Delivered" from status sheet

**iOS Code**:
```swift
// StatusSheet.swift
Button("Delivered") {
  Task {
    await updateStatus(.delivered)
  }
}
```

### Step 3: iOS Updates Database

**API Call**:
```swift
// AddressStatusAPI.swift
func updateStatus(addressId: UUID, campaignId: UUID, status: AddressStatus) async throws {
  try await supabase
    .from("address_statuses")
    .upsert([
      "address_id": addressId,
      "campaign_id": campaignId,
      "status": status.rawValue,
      "visited_at": Date(),
      "user_id": currentUserId
    ])
    .execute()
}
```

**Database**:
- Row inserted/updated in `address_statuses`
- Trigger updates `building_stats.status = 'delivered'`
- Trigger updates `user_stats.flyers += 1`

### Step 4: iOS Updates Map Immediately

**iOS Code** (optimistic update):
```swift
// Update feature state before API response
try mapView.mapboxMap.setFeatureState(
  sourceId: "buildingsSource",
  featureId: addressId.uuidString,
  state: ["status": "delivered"]
)

// Then update database
try await addressStatusAPI.updateStatus(...)
```

**Result**: Building color changes from red to green instantly (no reload needed)

---

## Leaderboard Update Flow

Complete flow from user activity to leaderboard ranking update.

### Step 1: User Activity Occurs

**Triggers**:
- QR code scanned → `qr_code_scans` insert
- Status changed → `address_statuses` upsert
- Session completed → `sessions` insert

### Step 2: Database Triggers Update Stats

**Trigger Logic** (simplified):
```sql
-- Trigger on qr_code_scans insert
CREATE TRIGGER update_user_stats_on_scan
AFTER INSERT ON qr_code_scans
FOR EACH ROW
EXECUTE FUNCTION increment_user_flyers();

-- Function updates user_stats
CREATE OR REPLACE FUNCTION increment_user_flyers()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE user_stats
  SET 
    flyers = flyers + 1,
    updated_at = now()
  WHERE user_id = (
    SELECT owner_id FROM campaigns
    WHERE id = (
      SELECT campaign_id FROM qr_codes
      WHERE id = NEW.qr_code_id
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Result**: `user_stats` table updated automatically

### Step 3: iOS Fetches Leaderboard

**User Action**: User navigates to Stats tab

**iOS Code**:
```swift
// LeaderboardView.swift
.task {
  await leaderboardViewModel.fetchLeaderboard(
    metric: .flyers,
    timeframe: .weekly
  )
}
```

**API Call**:
```swift
// LeaderboardService.swift
func fetchLeaderboard(metric: LeaderboardMetric, timeframe: Timeframe) async throws -> [LeaderboardEntry] {
  return try await supabase
    .rpc("get_leaderboard", params: [
      "metric": metric.rawValue,
      "timeframe": timeframe.rawValue
    ])
    .execute()
    .value
}
```

**RPC Logic**:
```sql
CREATE OR REPLACE FUNCTION get_leaderboard(metric TEXT, timeframe TEXT)
RETURNS TABLE(...) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    user_id,
    ROW_NUMBER() OVER (ORDER BY flyers DESC) as rank,
    flyers,
    conversations,
    leads
  FROM user_stats
  WHERE (
    CASE timeframe
      WHEN 'daily' THEN last_activity = CURRENT_DATE
      WHEN 'weekly' THEN last_activity >= CURRENT_DATE - INTERVAL '7 days'
      ELSE true
    END
  )
  ORDER BY flyers DESC;
END;
$$ LANGUAGE plpgsql;
```

### Step 4: View Displays Rankings

**SwiftUI View**:
```swift
// LeaderboardView.swift
List(leaderboardEntries) { entry in
  HStack {
    Text("#\(entry.rank)")
      .font(.headline)
    
    Text(entry.userName)
    
    Spacer()
    
    Text("\(entry.flyers) flyers")
      .foregroundColor(.secondary)
  }
}
```

**Result**: User sees their ranking and other users' rankings

---

## Session Recording Flow

Complete flow from starting a session to saving the recorded path.

### Step 1: User Starts Session

**User Action**: Taps "Start Session" in Record tab

**iOS Code**:
```swift
// RecordHomeView.swift
Button("Start Session") {
  sessionManager.startSession(
    campaignId: campaign.id,
    goalType: .doors,
    goalAmount: 50
  )
  navigateToMap = true
}
```

### Step 2: SessionManager Tracks Location

**Session Logic**:
```swift
// SessionManager.swift
func startSession(campaignId: UUID, goalType: GoalType, goalAmount: Double) {
  session = SessionRecord(
    id: UUID(),
    campaignId: campaignId,
    startTime: Date(),
    goalType: goalType,
    goalAmount: goalAmount,
    pathGeoJSON: nil
  )
  
  locationManager.startUpdatingLocation()
}

func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
  for location in locations {
    pathCoordinates.append([location.coordinate.longitude, location.coordinate.latitude])
    updateDistance()
  }
}
```

### Step 3: User Ends Session

**User Action**: Taps "End Session" button

**iOS Code**:
```swift
// SessionMapView.swift
Button("End Session") {
  Task {
    await sessionManager.endSession()
  }
}
```

### Step 4: SessionManager Saves to Database

**API Call**:
```swift
// SessionManager.swift
func endSession() async throws {
  session.endTime = Date()
  session.pathGeoJSON = generateGeoJSON(from: pathCoordinates)
  
  try await sessionsAPI.create(session)
}

func generateGeoJSON(from coordinates: [[Double]]) -> [String: Any] {
  return [
    "type": "LineString",
    "coordinates": coordinates
  ]
}
```

**Database**: Row inserted in `sessions` table with path GeoJSON

**Trigger**: `user_stats.distance_meters` updated automatically

### Step 5: iOS Shows Session Summary

**View**:
```swift
// SessionSummaryView.swift
VStack {
  Text("Session Complete!")
    .font(.title)
  
  HStack {
    VStack {
      Text("Distance")
      Text("\(session.distanceMeters / 1000, specifier: "%.2f") km")
    }
    
    VStack {
      Text("Duration")
      Text(formatDuration(session.duration))
    }
    
    VStack {
      Text("Doors")
      Text("\(doorsKnocked)")
    }
  }
}
```

**Result**: User sees summary of their session

---

## Contact/Lead Creation Flow

Complete flow from conversation to CRM sync.

### Step 1: User Has Conversation

**User Action**: After talking to homeowner, taps "Add Contact" in status sheet

### Step 2: User Enters Contact Info

**iOS Code**:
```swift
// ContactCreateSheet.swift
Form {
  TextField("Name", text: $name)
  TextField("Phone", text: $phone)
  TextField("Email", text: $email)
  TextEditor(text: $notes)
  
  Picker("Status", selection: $status) {
    Text("Hot").tag(ContactStatus.hot)
    Text("Warm").tag(ContactStatus.warm)
    Text("Cold").tag(ContactStatus.cold)
  }
}
```

### Step 3: iOS Creates Contact

**API Call**:
```swift
// ContactsService.swift
func createContact(_ contact: Contact) async throws -> Contact {
  return try await supabase
    .from("contacts")
    .insert(contact.dbRow)
    .select()
    .single()
    .execute()
    .value
}
```

**Database**: Row inserted in `contacts` table

### Step 4: iOS Syncs to CRM (Optional)

**User Action**: If CRM integration enabled, automatically syncs

**Edge Function Call**:
```swift
// CRMIntegrationManager.swift
func syncLead(_ contact: Contact) async throws {
  try await supabase.functions.invoke(
    "crm_sync",
    options: FunctionInvokeOptions(
      body: [
        "lead": contact.asCRMLead(),
        "user_id": currentUserId
      ]
    )
  )
}
```

**Edge Function** (`crm_sync`):
1. Looks up user's active integrations
2. Creates contact in HubSpot (if connected)
3. Creates item in Monday.com (if connected)
4. Creates lead in Follow Up Boss (if connected)
5. Triggers Zapier webhook (if connected)

**Result**: Lead appears in connected CRM systems

---

## Data Flow Diagram

```
User Action (iOS)
  ↓
Hook/ViewModel (@MainActor)
  ↓
API Client (CampaignsAPI, etc.)
  ↓
[Branch 1: Supabase Direct]
  Supabase RPC/Table
    ↓
  Database Trigger
    ↓
  User Stats Update

[Branch 2: Backend API]
  Next.js API Route
    ↓
  External Service (Lambda/S3 backend, Mapbox)
    ↓
  Supabase Insert
    ↓
  Database Trigger

[Branch 3: Edge Function]
  Supabase Edge Function
    ↓
  External Service (CRM API)
    ↓
  Success Response

  ↓
Response to iOS
  ↓
Store Update (@Published)
  ↓
View Re-render (SwiftUI)
```

---

## Performance Optimization Patterns

### 1. Parallel Fetching

Fetch multiple data sources concurrently:
```swift
async let buildings = fetchBuildings(campaignId)
async let addresses = fetchAddresses(campaignId)
async let roads = fetchRoads(campaignId)

let (b, a, r) = try await (buildings, addresses, roads)
```

### 2. Optimistic Updates

Update UI immediately, sync to backend in background:
```swift
// Update UI
updateLocalState()

// Then sync to backend
Task {
  try await syncToBackend()
}
```

### 3. Adaptive Polling

Poll more frequently when activity detected:
```swift
let interval = hasRecentActivity ? 5.0 : 30.0
try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
```

### 4. Feature State Updates

Use Mapbox feature state for instant updates (no source reload):
```swift
mapView.mapboxMap.setFeatureState(
  sourceId: "buildingsSource",
  featureId: id,
  state: ["status": "delivered"]
)
```
