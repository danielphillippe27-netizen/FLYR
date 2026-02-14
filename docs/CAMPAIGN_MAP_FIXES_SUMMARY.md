# Campaign Map Decode and Mapbox Fixes – What Changed

**Summary:** Addressed decode errors (addresses array vs dictionary, statuses missing `id`, geometry coordinates "Unsupported type"), Mapbox FillBucket LineString-in-fill warnings, MapView sizing/content-scale warnings, and matchedGeometry multiple-source warnings.

- **A) Addresses/roads/buildings RPC decode:** `SupabaseClientShim` now has `callRPCData` and logs first 2KB of raw JSON for map RPCs in DEBUG. `MapFeaturesService` uses `decodeFeatureCollection` so all three campaign RPCs accept either a top-level object `{ type, features }` or a top-level array of features; decoding is in [MapFeaturesService.swift](FLYR/Services/MapFeaturesService.swift), [SupabaseClientShim.swift](FLYR/Config/SupabaseClientShim.swift).
- **B) Statuses decoding:** `AddressStatusRow` uses a custom `init(from decoder:)` that decodes `id` from `"id"` when present, otherwise uses `"address_id"` as the stable `id`. `VisitsAPI.fetchStatuses` logs raw JSON in DEBUG and decodes from `response.data` manually. Files: [CampaignDBModels.swift](FLYR/Feautures/Campaigns/Models/CampaignDBModels.swift), [VisitsAPI.swift](FLYR/Features/Campaigns/API/VisitsAPI.swift).
- **C) GeoJSON geometry coordinates:** Replaced `AnyCodable` for coordinates with `GeoJSONCoordinatesNode` (recursive number/array decoder) and added `LossyDouble` (Double or String). `MapFeatureGeoJSONGeometry` now decodes Point, LineString, Polygon, MultiPolygon, MultiLineString. File: [MapFeaturesService.swift](FLYR/Services/MapFeaturesService.swift).
- **D) Fill layer geometry:** `MapLayerManager.updateBuildings` decodes as `BuildingFeatureCollection`, keeps only features with `geometry.type == "Polygon"` or `"MultiPolygon"`, re-encodes and updates the source. Fill-extrusion layer has an explicit `geometryType` filter (Polygon/MultiPolygon). File: [MapLayerManager.swift](FLYR/Services/MapLayerManager.swift).
- **E) SQL RPC:** Migration comments state that iOS expects a single jsonb object (FeatureCollection) and supports an array fallback; geometry should be GeoJSON; `address_statuses` has `id` and iOS supports `address_id` as fallback. Files: [supabase/migrations/20250203_ios_map_features_rpc.sql](supabase/migrations/20250203_ios_map_features_rpc.sql), [supabase/migrations/20250205000000_create_address_statuses.sql](supabase/migrations/20250205000000_create_address_statuses.sql).
- **F) MapView size and matchedGeometry:** `CampaignMapView` wraps content in `GeometryReader` and only creates `CampaignMapboxMapViewRepresentable` when `size.width > 0 && size.height > 0`; representable takes `preferredSize` and uses `max(320, width)`, `max(260, height)` for the MapView frame. In `NewCampaignDetailView`, inline map uses `matchedGeometryEffect(..., isSource: !isMapFullscreen)` and fullscreen map uses `isSource: true` so only one view is the geometry source. Files: [CampaignMapView.swift](FLYR/Features/Map/Views/CampaignMapView.swift), [NewCampaignDetailView.swift](FLYR/Feautures/Campaigns/Views/NewCampaignDetailView.swift).

---

## Sanity Checklist (Expected Logs)

- **No decode errors:** No "typeMismatch … Expected to decode Dictionary … but found an array", no "dataCorrupted … geometry.coordinates … Unsupported type", no "keyNotFound(\"id\")".
- **RPC responses:** In DEBUG, first 2KB of raw JSON logged for `rpc_get_campaign_addresses`, `rpc_get_campaign_roads`, `rpc_get_campaign_full_features`, and for `address_statuses` fetch.
- **Counts:** After load, logs like "Loaded N building features", "Loaded N addresses for campaign", "Loaded N roads for campaign" with N ≥ 0; roads count > 0 if campaign has roads.
- **Mapbox:** No "FillBucket: adding non-polygon geometry (LineString)" when viewing campaign map; optional log "Updated buildings source (X polygons, filtered Y non-polygons)" if any non-polygons were filtered.
- **MapView:** No "Invalid size fallback {64,64}, content scale factor nan"; no "SwiftUI matchedGeometry: multiple views isSource true".

**Quick verification:** Open a campaign detail screen, wait for features to load; confirm no decode errors in console, buildings/addresses/roads counts present, and no FillBucket or MapView size/matchedGeometry warnings.
