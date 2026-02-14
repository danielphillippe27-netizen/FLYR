# FLYR PRO iOS - Buildings Workflow Guide

> **For**: iOS Developer (Cursor)  
> **Topic**: Complete workflow for getting buildings via S3, Lambda, and Supabase  
> **Last Updated**: 2026-02-12

---

## 📋 Overview

This guide explains the complete architecture for fetching and rendering buildings in the iOS app. Instead of querying a database for building data, we use a **snapshot-based architecture** where:

1. **Lambda** generates campaign snapshots (buildings, addresses, roads)
2. **S3** stores gzipped GeoJSON files (30-day TTL)
3. **Supabase** stores only address leads and snapshot metadata
4. **iOS App** renders buildings directly from S3

---

## 🏗️ Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BUILDINGS DATA FLOW (iOS App)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  STEP 1: PROVISION (One-time, during campaign creation)                    │
│  ─────────────────────────────────────────────────────                     │
│                                                                             │
│  Web App / Dashboard                                                       │
│       │                                                                    │
│       ▼                                                                    │
│  POST /api/campaigns/provision                                             │
│       │                                                                    │
│       ▼                                                                    │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐      │
│  │   TileLambda    │────▶│  flyr-data-lake │────▶│  flyr-snapshots │      │
│  │   (AWS Lambda)  │     │   (Master Data) │     │   (S3 Bucket)   │      │
│  └─────────────────┘     └─────────────────┘     └─────────────────┘      │
│                              │                        │                    │
│                              │ Queries Overture       │ Writes GeoJSON     │
│                              │ (buildings/roads)      │ (gzipped)          │
│                              │                        │                    │
│                              ▼                        ▼                    │
│                    ┌─────────────────┐      ┌─────────────────┐           │
│                    │  buildings.json │      │  buildings/     │           │
│                    │  addresses.json │      │  campaigns/     │           │
│                    │  roads.json     │      │  {campaignId}/  │           │
│                    └─────────────────┘      └─────────────────┘           │
│                                                                             │
│  STEP 2: STORE METADATA                                                    │
│  ─────────────────────                                                     │
│                                                                             │
│  Supabase: campaign_snapshots table                                        │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │  campaign_id: "uuid"                                                │   │
│  │  bucket: "flyr-snapshots"                                           │   │
│  │  prefix: "campaigns/{uuid}/"                                        │   │
│  │  buildings_key: "campaigns/{uuid}/buildings.json.gz"                │   │
│  │  buildings_url: "https://flyr-snapshots.s3... (presigned)"          │   │
│  │  roads_url: "https://flyr-snapshots.s3..."                          │   │
│  │  expires_at: "2026-03-14T12:00:00Z" (30 days)                       │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Supabase: campaign_addresses table (LEAN - only leads)                    │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │  Only ingested data: addresses for QR/tracking                      │   │
│  │  - gers_id, house_number, street_name, geom (point)                 │   │
│  │  - status, scans, visited                                           │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  STEP 3: iOS APP RENDERS FROM S3                                           │
│  ───────────────────────────────                                           │
│                                                                             │
│  iOS App                                                                   │
│       │                                                                    │
│       ▼                                                                    │
│  GET /api/campaigns/{id}/buildings  ← Your API endpoint                    │
│       │                                                                    │
│       ▼                                                                    │
│  API Server fetches from S3 directly                                       │
│       │                                                                    │
│       ▼                                                                    │
│  Response: GeoJSON FeatureCollection                                       │
│  {                                                                         │
│    "type": "FeatureCollection",                                            │
│    "features": [{                                                          │
│      "type": "Feature",                                                    │
│      "id": "gers_id_123",   ← Use this for feature state                  │
│      "geometry": { "type": "Polygon", "coordinates": [...] },              │
│      "properties": {                                                       │
│        "gers_id": "gers_id_123",                                          │
│        "height_m": 8.5,          ← Building height for 3D                 │
│        "levels": 2,                                                        │
│        "address_text": "123 Main St",                                      │
│        "feature_status": "linked"                                          │
│      }                                                                     │
│    }]                                                                      │
│  }                                                                         │
│                                                                             │
│       │                                                                    │
│       ▼                                                                    │
│  Mapbox Maps SDK (iOS)                                                     │
│  - FillExtrusionLayer for 3D buildings                                     │
│  - Color based on scans/status from Supabase realtime                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔑 Key Concepts

### 1. **Snapshots = Immutable Campaign Data**

When a campaign is provisioned, Lambda creates a snapshot - a point-in-time extract of:
- **Buildings**: GeoJSON with footprints, heights, GERS IDs
- **Addresses**: Points for each address in the territory
- **Roads**: LineStrings for routing/orientation

These are **immutable** for the campaign's lifetime. No updates needed.

### 2. **S3 Direct Access (Not Supabase)**

| Data | Location | Why |
|------|----------|-----|
| Buildings | S3 (flyr-snapshots) | Large geometry data, cached by CloudFront |
| Roads | S3 (flyr-snapshots) | Routing data, static per campaign |
| Addresses | Supabase (campaign_addresses) | Dynamic status, scans, lead tracking |
| Building Stats | Supabase (building_stats) | Real-time scan counts |

### 3. **GERS ID = The Link**

```
Overture Building (S3) ──gers_id──▶ Supabase Address ──gers_id──▶ Building Stats
       │                                                           │
       │                    "What house is this?"                   │
       │◄──────────────────────────────────────────────────────────┘
       │
       ▼
  Map Feature ID (for setFeatureState)
```

Every building has a stable `gers_id` (Global Entity Reference System) from Overture Maps. This links:
- S3 GeoJSON building footprint
- Supabase campaign address (lead)
- Supabase building_stats (scan counts)

---

## 📡 iOS Implementation

### Step 1: Get Buildings for a Campaign

```swift
import Foundation

// MARK: - API Response Models

struct BuildingFeature: Codable {
    let type: String
    let id: String           // This is the gers_id
    let geometry: PolygonGeometry
    let properties: BuildingProperties
}

struct PolygonGeometry: Codable {
    let type: String         // "Polygon" or "MultiPolygon"
    let coordinates: [[[[Double]]]]  // GeoJSON coords
}

struct BuildingProperties: Codable {
    let gersId: String
    let heightM: Double      // For 3D extrusion
    let levels: Int?         // Number of floors
    let addressText: String?
    let featureStatus: String  // "linked" or "orphan_building"
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case heightM = "height_m"
        case levels
        case addressText = "address_text"
        case featureStatus = "feature_status"
    }
}

struct BuildingsResponse: Codable {
    let type: String
    let features: [BuildingFeature]
}

// MARK: - API Service

class BuildingsService {
    static let shared = BuildingsService()
    private let baseURL = "https://flyrpro.app/api"
    
    /// Fetches buildings GeoJSON for a campaign
    /// This returns the raw S3 data via our API proxy
    func fetchBuildings(campaignId: String) async throws -> BuildingsResponse {
        let url = URL(string: "\(baseURL)/campaigns/\(campaignId)/buildings")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Add auth header if needed
        // request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BuildingError.fetchFailed
        }
        
        return try JSONDecoder().decode(BuildingsResponse.self, from: data)
    }
}

enum BuildingError: Error {
    case fetchFailed
    case decodingFailed
}
```

### Step 2: Render in Mapbox

```swift
import MapboxMaps
import UIKit

class CampaignMapViewController: UIViewController {
    var mapView: MapView!
    var campaignId: String!
    
    // Store building features for color updates
    var buildingFeatures: [BuildingFeature] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMap()
        loadBuildings()
        subscribeToRealtimeUpdates()
    }
    
    func setupMap() {
        let options = MapInitOptions(
            cameraOptions: CameraOptions(zoom: 15)
        )
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        
        // Configure 3D light for extrusion
        var light = Light()
        light.anchor = .map
        light.position = .constant([1.5, 90, 80])
        light.intensity = .constant(0.5)
        try? mapView.mapboxMap.style.setLight(light)
    }
    
    func loadBuildings() {
        Task {
            do {
                let response = try await BuildingsService.shared.fetchBuildings(
                    campaignId: campaignId
                )
                buildingFeatures = response.features
                
                await MainActor.run {
                    self.addBuildingsToMap(features: response.features)
                }
            } catch {
                print("Failed to load buildings: \(error)")
            }
        }
    }
    
    func addBuildingsToMap(features: [BuildingFeature]) {
        // Convert to Mapbox FeatureCollection
        let geoJSONSource = GeoJSONSource()
        
        // Build features array
        var mapboxFeatures: [Feature] = []
        
        for feature in features {
            guard let geometry = convertToMapboxGeometry(feature.geometry) else { continue }
            
            var properties = JSONObject()
            properties["gers_id"] = .string(feature.properties.gersId)
            properties["height_m"] = .number(feature.properties.heightM)
            properties["levels"] = feature.properties.levels.map { .number(Double($0)) } ?? .null
            properties["address_text"] = feature.properties.addressText.map { .string($0) } ?? .null
            properties["scans_total"] = .number(0)  // Will update from realtime
            properties["status"] = .string("not_visited")
            
            let mapboxFeature = Feature(
                geometry: geometry,
                properties: properties
            )
            mapboxFeatures.append(mapboxFeature)
        }
        
        let featureCollection = FeatureCollection(features: mapboxFeatures)
        geoJSONSource.data = .featureCollection(featureCollection)
        
        // CRITICAL: Use promoteId to enable feature state by gers_id
        geoJSONSource.promoteId = .string("gers_id")
        
        do {
            // Remove existing source if any
            if mapView.mapboxMap.style.sourceExists(withId: "campaign-buildings") {
                try mapView.mapboxMap.style.removeSource(withId: "campaign-buildings")
            }
            
            try mapView.mapboxMap.style.addSource(geoJSONSource, id: "campaign-buildings")
            
            // Add 3D fill-extrusion layer
            addBuildingLayer()
            
        } catch {
            print("Error adding source: \(error)")
        }
    }
    
    func addBuildingLayer() {
        var layer = FillExtrusionLayer(id: "buildings-3d")
        layer.source = "campaign-buildings"
        
        // Height from properties
        layer.fillExtrusionHeight = .expression(
            Exp(.get) { "height_m" }
        )
        
        // Base at ground level
        layer.fillExtrusionBase = .constant(0)
        
        // Opacity
        layer.fillExtrusionOpacity = .constant(0.85)
        
        // Color based on status/scans (PRIORITY ORDER)
        // 1. Yellow if scanned (scans_total > 0)
        // 2. Blue if status = "hot"
        // 3. Green if status = "visited"
        // 4. Red default (not visited)
        layer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                // Priority 1: QR Scanned (YELLOW)
                Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
                UIColor(hex: "#facc15")
                
                // Priority 2: Hot/Conversation (BLUE)
                Exp(.eq) { Exp(.get) { "status" }; "hot" }
                UIColor(hex: "#3b82f6")
                
                // Priority 3: Visited/Touched (GREEN)
                Exp(.eq) { Exp(.get) { "status" }; "visited" }
                UIColor(hex: "#22c55e")
                
                // Default: Not visited (RED)
                UIColor(hex: "#ef4444")
            }
        )
        
        do {
            try mapView.mapboxMap.style.addLayer(layer)
        } catch {
            print("Error adding layer: \(error)")
        }
    }
    
    // Helper: Convert geometry
    func convertToMapboxGeometry(_ geometry: PolygonGeometry) -> MapboxMaps.Geometry? {
        // Parse GeoJSON coordinates to Mapbox geometry
        // This is simplified - handle Polygon and MultiPolygon cases
        guard let polygonCoords = geometry.coordinates.first else { return nil }
        
        var ring = Ring(coordinates: [])
        for coordSet in polygonCoords {
            for point in coordSet {
                guard point.count >= 2 else { continue }
                ring.coordinates.append(
                    CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
                )
            }
        }
        
        return .polygon(Polygon([ring]))
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
```

### Step 3: Real-time Color Updates

```swift
import Supabase

extension CampaignMapViewController {
    
    func subscribeToRealtimeUpdates() {
        // Subscribe to building_stats table for this campaign
        let channel = supabase.channel("building-updates-\(campaignId!)")
        
        channel
            .on(
                "postgres_changes",
                filter: ChannelFilter(
                    event: "*",
                    schema: "public",
                    table: "building_stats",
                    filter: "campaign_id=eq.\(campaignId!)"
                )
            ) { [weak self] payload in
                self?.handleBuildingStatUpdate(payload: payload)
            }
            .subscribe()
    }
    
    func handleBuildingStatUpdate(payload: SupabaseChannelPayload) {
        // Extract data from payload
        guard let newData = payload.new else { return }
        
        let gersId = newData["gers_id"] as? String
        let scansTotal = newData["scans_total"] as? Int ?? 0
        let status = newData["status"] as? String ?? "not_visited"
        
        guard let gersId = gersId else { return }
        
        DispatchQueue.main.async {
            // Update feature state - this changes color instantly
            // without re-rendering the entire layer
            try? self.mapView.mapboxMap.setFeatureState(
                sourceId: "campaign-buildings",
                featureId: gersId,  // matches promoteId
                state: [
                    "scans_total": scansTotal,
                    "status": status
                ]
            )
        }
    }
}

// Supabase client setup
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://kfnsnwqylsdsbgnwgxva.supabase.co")!,
    supabaseKey: "your-anon-key"
)
```

---

## 🗄️ Database Schema Reference

### campaign_snapshots (Metadata Only)

```sql
CREATE TABLE public.campaign_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id),
    
    -- S3 Location
    bucket TEXT NOT NULL,              -- "flyr-snapshots"
    prefix TEXT NOT NULL,              -- "campaigns/{uuid}/"
    
    -- S3 Keys (for server-side regeneration)
    buildings_key TEXT,                -- "campaigns/{uuid}/buildings.json.gz"
    addresses_key TEXT,
    roads_key TEXT,
    
    -- Presigned URLs (iOS uses these indirectly via API)
    buildings_url TEXT,                -- Full S3 URL
    addresses_url TEXT,
    roads_url TEXT,
    
    -- Counts
    buildings_count INTEGER,
    addresses_count INTEGER,
    roads_count INTEGER,
    
    -- Expiration (30 days)
    expires_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT unique_campaign_snapshot UNIQUE (campaign_id)
);
```

### building_stats (Real-time Updates)

```sql
CREATE TABLE public.building_stats (
    building_id UUID PRIMARY KEY,
    gers_id TEXT UNIQUE,               -- Links to S3 GeoJSON
    campaign_id UUID,
    
    status TEXT,                       -- 'not_visited', 'visited', 'hot'
    scans_total INTEGER DEFAULT 0,     -- Total QR scans
    scans_today INTEGER DEFAULT 0,
    last_scan_at TIMESTAMP,
    
    updated_at TIMESTAMP
);

-- Enable realtime for instant updates
ALTER PUBLICATION supabase_realtime ADD TABLE building_stats;
```

---

## 🔗 API Endpoints

### GET /api/campaigns/{campaignId}/buildings

Returns building GeoJSON for the campaign. Server fetches from S3 and returns decompressed GeoJSON.

**Response:**
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "08a2b4c5d6e7f8g9",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[...]]]
      },
      "properties": {
        "gers_id": "08a2b4c5d6e7f8g9",
        "height_m": 8.5,
        "levels": 2,
        "address_text": "123 Main St",
        "feature_status": "linked"
      }
    }
  ]
}
```

### GET /api/campaigns/{campaignId}/addresses

Returns addresses as GeoJSON (from Supabase, for pins/markers).

### Supabase RPC: rpc_get_campaign_full_features

Alternative: Direct RPC call (returns same data as API):

```swift
let geojson = try await supabase
    .rpc("rpc_get_campaign_full_features", params: ["campaign_id": campaignId])
    .execute()
    .value
```

---

## ⚠️ Important Notes

### 1. **Presigned URL Expiration**

S3 presigned URLs in `campaign_snapshots` expire after ~1 hour. The API endpoint (`/api/campaigns/{id}/buildings`) handles refreshing these URLs server-side. **iOS should always use the API endpoint, not direct S3 URLs.**

### 2. **Gzip Compression**

S3 files are stored as `.json.gz`. The API decompresses them before returning to iOS. No decompression needed in the app.

### 3. **Feature State Performance**

Use `setFeatureState()` for real-time updates instead of re-adding the source. This is O(1) vs O(n) for re-rendering.

### 4. **GERS ID Consistency**

Always use `gers_id` as the feature ID:
- In S3 GeoJSON: `feature.id` and `properties.gers_id`
- In Supabase: `building_stats.gers_id`
- In Mapbox: `promoteId = "gers_id"`

### 5. **Color Priority**

Building colors follow this priority (highest to lowest):
1. **Yellow** (`#facc15`) - QR scanned (scans_total > 0)
2. **Blue** (`#3b82f6`) - Hot lead/conversation (status = 'hot')
3. **Green** (`#22c55e`) - Visited (status = 'visited')
4. **Red** (`#ef4444`) - Default/not visited

---

## 🧪 Testing Checklist

- [ ] Call `/api/campaigns/{id}/buildings` and verify GeoJSON response
- [ ] Parse features and extract `gers_id` and `height_m`
- [ ] Add GeoJSON source with `promoteId: "gers_id"`
- [ ] Render FillExtrusionLayer with height from properties
- [ ] Subscribe to `building_stats` realtime channel
- [ ] Test color change when scan occurs (use test QR code)
- [ ] Verify `setFeatureState` updates color without flicker
- [ ] Test with 1000+ buildings (performance check)

---

## 📚 Related Documentation

- `FLYR_PRO_TECHNICAL_REFERENCE.md` - Complete API reference
- `SNAPSHOT_ROUTING_IMPLEMENTATION.md` - Lambda/S3 architecture
- `MOTHERDUCK_ARCHITECTURE.md` - Data source details
- `README_TILES.md` - Tile-based data organization

---

## 🆘 Troubleshooting

| Issue | Solution |
|-------|----------|
| Buildings not appearing | Check API response, verify GeoJSON parsing |
| Wrong colors | Verify `promoteId` is set to `"gers_id"` |
| Realtime not working | Check RLS policies, verify channel subscription |
| Map slow with many buildings | Enable clustering or viewport-based loading |
| URL expired error | Use `/api/campaigns/{id}/buildings` not direct S3 |

---

**Questions?** Check the technical reference or ask the backend team about the Lambda/S3 pipeline.
