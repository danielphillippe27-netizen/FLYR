# FLYR iOS Architecture

Reference for iOS app architecture patterns, features, services, and data flows.

## Architecture Pattern: Hooks/Stores/Views

FLYR uses a reactive architecture pattern inspired by React hooks:

### 1. Views (SwiftUI)
- SwiftUI views that observe state and render UI
- Conform to `View` protocol
- Use `@StateObject`, `@ObservedObject`, `@EnvironmentObject` for reactivity

### 2. Hooks (ViewModels)
- Classes prefixed with `Use*` (e.g., `UseCampaignsV2`, `UseCreateCampaign`)
- Marked with `@MainActor` and conform to `ObservableObject`
- Manage business logic, coordinate API calls, update stores
- Published properties for view observation: `@Published var isLoading: Bool`

### 3. Stores (State Containers)
- In-memory state containers with `@Published` properties
- Suffixed with `*Store` (e.g., `CampaignV2Store`)
- Single source of truth for feature state
- Updated by hooks, observed by views

### 4. API Clients
- Classes suffixed with `*API` (e.g., `CampaignsAPI`, `QRCodeAPI`)
- Handle Supabase RPC calls and HTTP requests
- Return typed results or throw errors

### 5. Services
- Classes suffixed with `*Service` (e.g., `MapFeaturesService`, `AddressService`)
- Encapsulate complex business logic
- Protocol-based for testability and dependency injection

## Data Flow

```
View
  ↓ User Action
Hook (Use*)
  ↓ Business Logic
API Client (*API) or Service (*Service)
  ↓ Network Call
Supabase / Backend
  ↓ Response
Hook updates Store
  ↓ @Published change
View re-renders
```

## Feature Organization

**Note**: Two feature directories exist: `Features/` and `Feautures/` (typo)

### Campaigns (`Feautures/Campaigns/`)

**Models**:
- `CampaignV2` - Main campaign model
- `CampaignDBRow` - Database representation
- `CampaignAddress` - Address within campaign

**API**:
- `CampaignsAPI` - Campaign CRUD, provision, territory updates
- `GeoAPI` - Geocoding and reverse geocoding
- `VisitsAPI` - Visit tracking

**Hooks**:
- `UseCampaignsV2` - Campaign list management
- `UseCreateCampaign` - Campaign creation flow
- `UseCampaignMap` - Campaign map state

**Stores**:
- `CampaignV2Store` - Campaign list state

**Views**:
- `CampaignsListView` - Campaign list with pager
- `NewCampaignScreen` - Campaign creation wizard
- `NewCampaignDetailView` - Campaign detail view
- `MapDrawingView` - Map-based campaign territory drawing

**Flow Example**:
```
NewCampaignScreen (View)
  → UseCreateCampaign.createV2() (Hook)
    → CampaignsAPI.createV2() (API)
      → SupabaseClientShim.insertReturning() (Supabase)
        → CampaignV2Store.append() (Store)
          → View updates (@Published)
```

---

### Map (`Features/Map/`)

**Models**:
- `MapMode` - Map interaction mode (view, draw, select)
- `MapStyle` - Map style enum (light, dark, satellite)
- `MapTheme` - Theme with style URLs
- `SessionRecord` - Session tracking data
- `OptimizedRoute` - Route optimization result
- `RoadGraph` - Road network graph for routing

**Services**:
- `MapFeaturesService` - Fetches GeoJSON from Supabase RPCs
- `MapLayerManager` - Manages Mapbox sources and layers
- `RouteOptimizationService` - A* route optimization
- `SessionManager` - Session recording and tracking

**Views**:
- `CampaignMapView` - Main campaign map view
- `FlyrMapView` - Generic map view wrapper
- `SessionMapView` - Session recording map
- `RecordHomeView` - Session start/history view
- `RoutePreviewView` - Route optimization preview

**Controllers**:
- `MapController` - Mapbox map state management
- `CampaignPolygonHelper` - Campaign polygon manipulation

**Key Classes**:
- `SessionMapboxViewRepresentable` - UIViewRepresentable for MapboxMapView
- `MapboxViewContainer` - Container for Mapbox map

---

### QR Codes (`Features/QRCodes/`)

**Models**:
- `QRCode` - QR code definition
- `QRSet` - QR code batch
- `QRType` - Type enum (address, batch, custom)
- `QRDestinationType` - Destination enum (landing_page, custom_url, website)

**Services**:
- `QRRepository` - QR code data access
- `BatchRepository` - Batch data access
- `QRCodeAPI` - QR code API client

**Hooks**:
- `UseQRCodeHub` - QR code hub state
- `UseQRCodeManage` - QR code management

**Views**:
- `QRCodeHubView` - QR code dashboard
- `QRWorkflowView` - QR creation workflow
- `CreateBatchView` - Batch creation
- `CreateQRView` - Single QR creation
- `QRCodeMapView` - QR codes on map
- `QRExportOptionsSheet` - Export options

**Components**:
- `QRCard` - QR code card UI

---

### Addresses (`Feautures/Addresses/`)

**Services**:
- `AddressService` - Unified address search (backend Lambda/S3 → Mapbox fallback)
- `AddressServiceHealth` - Service health monitoring

**Providers** (Protocol-based):
- `AddressProvider` (protocol) - Address provider interface
- `OvertureAddressProvider` - Backend HTTP API provider (Lambda/S3, primary)
- `MapboxProvider` - Mapbox Geocoding API provider (fallback)

**Repository**:
- `AddressRepository` (protocol) - Address data access interface
- `AddressService+RepositoryAdapter` - Adapter pattern implementation

**Hooks**:
- `UseAddresses` - Address search state

**Flow**:
```
User searches address
  → UseAddresses.search()
    → AddressService.search()
      → OvertureAddressProvider.search() (try first)
        → If fails: MapboxProvider.search() (fallback)
          → Return AddressResult[]
```

---

### Stats & Leaderboard (`Features/Stats/`)

**Models**:
- `UserStats` - User statistics
- `LeaderboardEntry` - Leaderboard entry
- `MetricSnapshot` - Metric snapshot

**Services**:
- `StatsService` - Stats data access
- `LeaderboardService` - Leaderboard data access

**ViewModels**:
- `StatsViewModel` - Stats page state
- `LeaderboardViewModel` - Leaderboard state

**Views**:
- `StatsPageView` - Stats page (leaderboard + profile)
- `StatsView` - User stats cards
- `LeaderboardView` - Leaderboard list
- `LeaderboardHeaderView` - Leaderboard header
- `LeaderboardMetricSelector` - Metric selector

---

### Contacts/CRM (`Features/Contacts/`)

**Models**:
- `Contact` - CRM contact
- `ContactActivity` - Contact activity log

**Services**:
- `ContactsService` - Contact data access
- `CRMIntegrationManager` - CRM integration coordinator
- `LeadSyncManager` - Lead sync to external CRMs

**Views**:
- `ContactsHubView` - Contacts dashboard
- `ContactDetailSheet` - Contact detail modal

---

## Key Services

### MapFeaturesService

Fetches GeoJSON FeatureCollections from Supabase RPCs.

**Methods**:
- `fetchAllCampaignFeatures(campaignId:)` - Fetches buildings, addresses, roads in parallel
- `fetchBuildings(campaignId:)` - Fetches buildings only
- `fetchAddresses(campaignId:)` - Fetches addresses only
- `fetchRoads(campaignId:)` - Fetches roads only
- `fetchBuildingsInBBox(bbox:campaignId:)` - Viewport-based loading

**Returns**: `FeatureCollection` (Codable struct)

---

### MapLayerManager

Manages Mapbox sources and layers.

**Methods**:
- `setupLayers(mapView:)` - Initial layer setup
- `updateBuildings(features:mapView:)` - Updates buildings source
- `updateAddresses(features:mapView:)` - Updates addresses source
- `updateRoads(features:mapView:)` - Updates roads source
- `updateFeatureState(featureId:state:mapView:)` - Updates feature state for real-time color changes

**Source IDs**:
- `buildingsSource`
- `addressesSource`
- `roadsSource`

**Layer IDs**:
- `buildingsExtrusionLayer` (fill-extrusion)
- `addressesCircleLayer` (circle)
- `roadsLineLayer` (line)

---

### AddressService

Unified address search with fallback strategy.

**Methods**:
- `search(query:)` - Search addresses (backend Lambda/S3 → Mapbox fallback)
- `reverseGeocode(lat:lon:)` - Reverse geocode point
- `sameStreet(street:city:refLat:refLon:)` - Find addresses on same street

**Providers**:
1. **OvertureAddressProvider** (primary) - Backend Lambda/S3 via HTTP API
2. **MapboxProvider** (fallback) - Mapbox Geocoding API

---

### RouteOptimizationService

A* route optimization for session recording.

**Methods**:
- `optimizeRoute(addresses:)` - Optimizes route through addresses
- `buildRoadGraph(roads:)` - Builds road network graph

**Returns**: `OptimizedRoute` (path, distance, duration)

---

### SupabaseClientShim

Wrapper for common Supabase operations.

**Methods**:
- `insertReturning<T>(_ table:, values:)` - Insert with typed response
- `callRPC<T>(_ function:, params:)` - Call RPC with typed response
- `callRPCData(_ function:, params:)` - Call RPC returning raw Data (for GeoJSON)

---

## API Clients

### CampaignsAPI

**Methods**:
- `createV2(_ campaign:)` - Create campaign
- `updateV2(_ campaign:)` - Update campaign
- `delete(_ id:)` - Delete campaign
- `provision(_ campaignId:)` - Provision campaign (calls backend API)
- `fetchAll()` - Fetch all campaigns

---

### BuildingsAPI

**Methods**:
- `fetchBuildings(campaignId:)` - Fetch buildings GeoJSON
- `fetchBuildingsInBBox(bbox:campaignId:)` - Fetch buildings in bounding box

---

### QRCodeAPI

**Methods**:
- `create(_ qrCode:)` - Create QR code
- `fetchAll()` - Fetch all QR codes
- `fetchByCampaign(_ campaignId:)` - Fetch campaign QR codes

---

### SessionsAPI

**Methods**:
- `create(_ session:)` - Create session
- `update(_ session:)` - Update session
- `fetchAll()` - Fetch all sessions

---

## Shared Utilities

### AppUIState

Global UI state singleton.

**Properties**:
- `isTabBarVisible` - Tab bar visibility
- `colorScheme` - App color scheme

---

### CampaignContext

Campaign-specific context (passed via environment).

**Properties**:
- `campaignId` - Current campaign ID
- `accentColor` - Campaign accent color

---

### Codable+SnakeCase

JSON encoding/decoding helpers for snake_case ↔ camelCase conversion.

**Features**:
- Automatic key conversion
- Flexible GeoJSON decoding (object or array)

---

## Example: Complete Feature Flow

### Campaign Creation → Map Rendering → Status Update

1. **User creates campaign**:
```swift
// NewCampaignScreen.swift
Button("Create") {
  Task {
    await useCreateCampaign.createV2(name: "My Campaign")
  }
}
```

2. **Hook coordinates creation**:
```swift
// UseCreateCampaign.swift
func createV2(name: String) async {
  isLoading = true
  let campaign = CampaignV2(name: name, ...)
  let result = try await campaignsAPI.createV2(campaign)
  store.append(result)
  isLoading = false
}
```

3. **API calls backend**:
```swift
// CampaignsAPI.swift
func createV2(_ campaign: CampaignV2) async throws -> CampaignV2 {
  return try await supabase
    .insertReturning("campaigns", values: campaign.dbRow)
}
```

4. **User navigates to map**:
```swift
// CampaignMapView.swift
.task {
  await mapFeaturesService.fetchAllCampaignFeatures(campaignId: campaign.id)
}
```

5. **Service fetches GeoJSON**:
```swift
// MapFeaturesService.swift
func fetchAllCampaignFeatures(campaignId: UUID) async throws {
  async let buildings = fetchBuildings(campaignId: campaignId)
  async let addresses = fetchAddresses(campaignId: campaignId)
  async let roads = fetchRoads(campaignId: campaignId)
  
  let (b, a, r) = try await (buildings, addresses, roads)
  
  await mapLayerManager.updateBuildings(features: b, mapView: mapView)
  await mapLayerManager.updateAddresses(features: a, mapView: mapView)
  await mapLayerManager.updateRoads(features: r, mapView: mapView)
}
```

6. **User taps building, changes status**:
```swift
// MapView gesture handler
.onMapTap { coordinate, features in
  if let buildingFeature = features.first {
    // Update status
    try await addressStatusAPI.update(
      addressId: buildingFeature.id,
      status: "delivered"
    )
    
    // Update feature state (instant color change)
    mapLayerManager.updateFeatureState(
      featureId: buildingFeature.id,
      state: ["status": "delivered"],
      mapView: mapView
    )
  }
}
```

---

## Testing Patterns

### Protocol-Based Dependency Injection

Services use protocols for easy mocking:

```swift
protocol AddressProvider {
  func search(query: String) async throws -> [AddressResult]
}

// Production
class OvertureAddressProvider: AddressProvider { ... }

// Testing
class MockAddressProvider: AddressProvider {
  var mockResults: [AddressResult] = []
  func search(query: String) async throws -> [AddressResult] {
    return mockResults
  }
}
```

---

## Important Notes

### Directory Typo

- Both `Features/` and `Feautures/` exist
- When searching for code, check both directories

### @MainActor Usage

- All hooks and view models are marked `@MainActor`
- Ensures UI updates happen on main thread
- No need for `DispatchQueue.main.async { }`

### Async/Await

- All API calls use async/await (no callbacks)
- Error handling via `do-catch` or `Result` type

### SwiftUI Lifecycle

- `.task { }` for async work on view appear
- `.onAppear { }` for sync initialization only
