# Linked Homes & Building Stats Card

## Overview

The Linked Homes feature provides comprehensive building information cards when users tap on buildings in the campaign map. It displays address details, resident information, QR code scan status, and provides quick actions for navigation, visit logging, and contact management.

## Architecture

### Core Components

#### 1. BuildingDataService
**Location**: `FLYR/Features/Map/Services/BuildingDataService.swift`

Main service for fetching and caching building data.

**Key Features**:
- Fetches complete building data (address, residents, QR status)
- Two-path resolution: Direct GERS ID lookup + fallback via building_address_links
- 5-minute cache with TTL management
- ObservableObject for SwiftUI integration

**Usage**:
```swift
let service = BuildingDataService(supabase: SupabaseManager.shared.client)
await service.fetchBuildingData(gersId: gersId, campaignId: campaignId)
// Access data via service.buildingData
```

#### 2. BuildingStatsSubscriber
**Location**: `FLYR/Features/Map/Services/BuildingStatsSubscriber.swift`

Actor-based real-time subscription service.

**Key Features**:
- WebSocket subscriptions to `building_stats` table
- Automatic fallback to polling (5-second intervals)
- Thread-safe actor pattern
- Callback-based update notifications

**Usage**:
```swift
let subscriber = BuildingStatsSubscriber(supabase: supabaseClient)
await subscriber.subscribe(campaignId: campaignId)
await subscriber.onUpdate = { gersId, status, scansTotal, qrScanned in
    // Update UI
}
```

#### 3. LocationCardView
**Location**: `FLYR/Features/Map/Views/CampaignMapView.swift`

SwiftUI view displaying comprehensive building information.

**Features**:
- Loading, error, and unlinked building states
- Residents list with tap-to-edit
- QR code status with visual indicators
- Action buttons (Navigate, Log Visit, Add Contact)
- Automatic data fetching on appear

### Data Models

#### ResolvedAddress
```swift
struct ResolvedAddress {
    let id: UUID
    let street: String
    let formatted: String
    let locality: String
    let region: String
    let postalCode: String
    let houseNumber: String
    let streetName: String
    let gersId: UUID
}
```

#### QRStatus
```swift
struct QRStatus {
    let hasFlyer: Bool
    let totalScans: Int
    let lastScannedAt: Date?
}
```

#### BuildingData
```swift
struct BuildingData {
    let isLoading: Bool
    let error: Error?
    let address: ResolvedAddress?
    let residents: [Contact]
    let qrStatus: QRStatus
    let buildingExists: Bool
    let addressLinked: Bool
}
```

## Database Schema

### Core Tables

#### buildings
- `id`: UUID (PK)
- `gers_id`: UUID (Overture Maps GERS ID)
- `geom`: Geometry (Polygon)
- `height_m`: Numeric
- `campaign_id`: UUID (FK)
- `latest_status`: Text

#### building_address_links
- `id`: UUID (PK)
- `building_id`: UUID (FK to buildings)
- `address_id`: UUID (FK to campaign_addresses)
- `campaign_id`: UUID (FK to campaigns)
- `method`: Text (COVERS, NEAREST, MANUAL)
- `is_primary`: Boolean

#### building_stats
- `building_id`: UUID (PK)
- `campaign_id`: UUID
- `gers_id`: UUID (denormalized)
- `status`: Text (not_visited, visited, hot)
- `scans_total`: Integer
- `scans_today`: Integer
- `last_scan_at`: Timestamp

### Triggers

**update_building_stats_on_scan**
- Automatically updates building_stats when QR codes are scanned
- Increments scan counts
- Updates last_scan_at timestamp
- Sets status to 'visited'

## Data Flow

### Building Tap Flow

```
User taps building on map
    ↓
Extract GERS ID from BuildingProperties
    ↓
BuildingDataService.fetchBuildingData()
    ↓
Path 1: Direct lookup in campaign_addresses (by gers_id)
    ↓ (if not found)
Path 2: Lookup via building_address_links
    ↓
Fetch contacts for address_id
    ↓
Parse QR status from address data
    ↓
Display LocationCardView with complete data
```

### Real-time Update Flow

```
QR code scanned
    ↓
Database trigger updates building_stats
    ↓
Supabase real-time notification
    ↓
BuildingStatsSubscriber receives update
    ↓
onUpdate callback invoked
    ↓
Map building color updated
    ↓
LocationCard refreshes if open
```

## Color Priority System

Buildings are colored based on this priority:

1. **Yellow** (#FCD34D) - QR Scanned (highest priority)
   - `scans_total > 0` OR `qr_scanned = true`

2. **Blue** (#3B82F6) - Hot Lead
   - `status = "hot"` AND not QR scanned

3. **Green** (#10B981) - Visited
   - `status = "visited"` AND not QR scanned

4. **Red** (#EF4444) - Not Visited (default)
   - `status = "not_visited"`

## API Methods

### BuildingDataService

```swift
// Fetch complete building data
await service.fetchBuildingData(gersId: UUID, campaignId: UUID)

// Clear cache
service.clearCache()

// Clear specific entry
service.clearCacheEntry(gersId: UUID, campaignId: UUID)

// Prune old entries
service.pruneCache()
```

### ContactsService

```swift
// Fetch contacts by FK
let contacts = try await ContactsService.shared.fetchContactsForAddress(addressId: UUID)

// Fetch contacts by text (fallback)
let contacts = try await ContactsService.shared.fetchContactsForAddressText(
    addressText: String, 
    campaignId: UUID
)

// Link contact to address
try await ContactsService.shared.linkContactToAddress(
    contactId: UUID, 
    addressId: UUID
)
```

### BuildingStatsSubscriber

```swift
// Subscribe to updates
await subscriber.subscribe(campaignId: UUID)

// Unsubscribe
await subscriber.unsubscribe()

// Set update callback
await subscriber.onUpdate = { gersId, status, scansTotal, qrScanned in
    // Handle update
}
```

## Integration Guide

### Adding to a New Map View

1. Add BuildingStatsSubscriber:
```swift
@State private var statsSubscriber: BuildingStatsSubscriber?
```

2. Setup on appear:
```swift
.onAppear {
    setupRealTimeSubscription()
}
```

3. Implement subscription:
```swift
private func setupRealTimeSubscription() {
    guard let campId = UUID(uuidString: campaignId) else { return }
    
    let subscriber = BuildingStatsSubscriber(supabase: SupabaseManager.shared.client)
    self.statsSubscriber = subscriber
    
    Task {
        await subscriber.subscribe(campaignId: campId)
        await subscriber.onUpdate = { gersId, status, scansTotal, qrScanned in
            // Update map colors
        }
    }
}
```

4. Clean up on disappear:
```swift
.onDisappear {
    Task {
        await statsSubscriber?.unsubscribe()
    }
}
```

### Showing LocationCard

```swift
LocationCardView(
    gersId: building.gersId,
    campaignId: campaignId,
    onClose: {
        showLocationCard = false
    }
)
```

## Performance Considerations

### Caching
- BuildingDataService caches for 5 minutes
- Cache key: `{campaignId}:{gersId}`
- Automatic pruning of expired entries
- Manual cache clearing on data updates

### Real-time
- WebSocket primary, polling fallback
- 5-second polling interval
- Automatic reconnection on failure
- Unsubscribe on view disappear

### Database
- Indexed queries on gers_id, campaign_id
- Denormalized gers_id in building_stats
- Efficient spatial queries with GIST indexes
- Row-level security enabled

## Testing

### Unit Tests
**Location**: `FLYRTests/BuildingDataServiceTests.swift`

Tests:
- ResolvedAddress display logic
- QRStatus text formatting
- BuildingData state management
- Cache validation
- Color priority logic

### UI Tests
**Location**: `FLYRUITests/LocationCardUITests.swift`

Tests:
- Location card display
- Loading/error/unlinked states
- Action button interactions
- Real-time updates

### Manual Testing Checklist

See `FLYRUITests/LocationCardUITests.swift` for complete manual testing checklist including:
- Basic display tests
- Resident list tests
- QR status tests
- Action button tests
- State transition tests
- Real-time update tests
- Edge case handling

## Troubleshooting

### Building Not Found
**Symptom**: LocationCard shows "Unlinked Building"
**Cause**: No campaign_addresses record with matching gers_id
**Solution**: 
1. Check if building exists in buildings table
2. Verify building_address_links has link to address
3. Ensure campaign_id matches

### Residents Not Showing
**Symptom**: "No residents" despite contacts existing
**Cause**: Contacts not linked via address_id FK
**Solution**:
1. Check contacts.address_id field
2. Use ContactsService.linkContactToAddress() to fix
3. Fallback to text matching if needed

### Real-time Not Working
**Symptom**: Building colors don't update when QR scanned
**Cause**: WebSocket connection failed or polling disabled
**Solution**:
1. Check console for subscription errors
2. Verify Supabase real-time enabled
3. Check network connectivity
4. Polling fallback should activate automatically

### Slow Performance
**Symptom**: Location card takes >1 second to load
**Cause**: Cache miss + slow network
**Solution**:
1. Verify cache is working (check timestamps)
2. Optimize database queries
3. Consider preloading data
4. Check network latency

## Future Enhancements

### Planned
- [ ] Offline support with local caching
- [ ] Batch contact editing from card
- [ ] Visit history timeline
- [ ] Photo attachments for buildings
- [ ] Custom notes per building
- [ ] Share building link
- [ ] Export building data

### Under Consideration
- [ ] AR building identification
- [ ] Voice notes for visits
- [ ] Integration with calendar for appointments
- [ ] Team collaboration features
- [ ] Building comparison view
- [ ] Analytics dashboard per building

## Migration Notes

### From address_buildings to New Schema

The old `address_buildings` table used MD5 hash keys for linking. The new system uses:
- Direct GERS ID linking in campaign_addresses
- Explicit building_address_links table
- Better support for multiple addresses per building
- Confidence scores for link quality

### Backwards Compatibility

The system supports:
- Legacy contacts without address_id (text matching fallback)
- Mixed GERS ID fields (gers_id + building_gers_id)
- Buildings without campaign_id
- Addresses without GERS ID

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review test files for examples
3. Check database schema in migrations
4. Review source code inline documentation

## References

- Database migrations: `supabase/migrations/20250206*.sql`
- Data models: `FLYR/Features/Map/Models/BuildingDataModels.swift`
- Services: `FLYR/Features/Map/Services/`
- UI: `FLYR/Features/Map/Views/CampaignMapView.swift`
- Tests: `FLYRTests/BuildingDataServiceTests.swift`
