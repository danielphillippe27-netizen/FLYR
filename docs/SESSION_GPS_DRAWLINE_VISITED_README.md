# Session GPS -> Draw Line -> Visited README

This is the current end-to-end implementation for campaign sessions in FLYR.

## 1) How GPS is collected

- Session start path:
  - `CampaignMapView.startBuildingSession(...)`
  - `SessionManager.startBuildingSession(...)`
- `SessionManager` configures Core Location with:
  - `desiredAccuracy = kCLLocationAccuracyBest`
  - `distanceFilter = 2.0`
  - background updates enabled
- GPS samples arrive through:
  - `SessionManager.locationManager(_:didUpdateLocations:)`

## 2) How GPS points are accepted/rejected

There are two filter layers before a point is appended to the session path:

### 2.1 Pro acceptance filter (`LocationAcceptanceFilter`)

When Pro normalization is enabled, samples are first checked by:
- `FLYR/Features/Map/GPSNormalization/LocationAcceptanceFilter.swift`

Rules:
- Reject if horizontal accuracy is invalid or above `maxHorizontalAccuracy` (default `15m`).
- Reject if distance from last accepted point is below `minMovementDistance` (default `4m`).
- Reject if implied speed is above `maxWalkingSpeedMetersPerSecond` (default `2.2 m/s`).

### 2.2 SessionManager anti-drift filter

After acceptance filter, `SessionManager` applies additional guards:
- reject impossible jumps (`impliedSpeed >= 10 m/s`)
- reject sub-min speed updates when speed is valid
- require minimum displacement from the prior accepted point

The displacement threshold is now **accuracy-aware** while stationary:
- base threshold = `8m` when stationary (`speed < 0.4`) or `3m` when moving
- dynamic threshold = `max(base, (lastAccuracy + currentAccuracy) * 0.9)`
- for stationary updates, require implied speed at least `0.55 m/s`

This suppresses route growth from idle GPS drift.

## 3) How the line is drawn on map

### 3.1 Stored raw path

Accepted points are appended to:
- `SessionManager.pathCoordinates`

Distance is accumulated in:
- `SessionManager.distanceMeters`

### 3.2 Pro normalized path (display + export)

If campaign roads are available, `SessionManager` creates:
- `SessionTrailNormalizer`

Normalizer pipeline:
- corridor projection to campaign roads
- side-of-street inference
- progress constraint (prevents backward bouncing)
- smoothing

Rendered path selection:
- `SessionManager.renderPathSegments()`
  - uses normalized path when available
  - otherwise uses simplified raw path

Map drawing:
- `CampaignMapView.updateSessionPathOnMap()`
- `SessionMapboxViewRepresentable.Coordinator.updatePath(...)`

Both update a Mapbox line source/layer with one or more line segments.

## 4) How proximity turns homes to "visited"

There are two completion flows depending on mode.

### 4.1 Door-knocking mode (`SessionMode.doorKnocking`)

Main behavior:
- session is started with `autoCompleteEnabled: false` in `CampaignMapView`
- completion is typically manual via UI actions that call:
  - `SessionManager.completeBuilding(...)`

When completion happens:
- building is added to `completedBuildings`
- session events + session counters are synced
- map building style is updated to visited

If auto-complete is enabled, `SessionManager.checkAutoComplete(...)` can complete by centroid proximity:
- nearest incomplete target centroid
- within threshold (`15m`)
- dwell (`8s`)
- speed below max (`2.5 m/s`)
- debounce (`3s`)
- posts `.sessionBuildingAutoCompleted` so map turns building green immediately

### 4.2 Flyer mode (`SessionMode.flyer`)

Flyer auto-complete is handled by:
- `FLYR/Features/Map/FlyerModeManager.swift`

Flow:
- observes `SessionManager.$currentLocation`
- computes nearest address target
- adaptive threshold:
  - base `10m`
  - scales with horizontal accuracy up to `20m`
- requires dwell `5s`
- blocks completion if moving too fast (`> 2.5 m/s`)

When an address completes:
- `CampaignMapView.flyerAddressCompleted(...)` runs
- address state set to delivered on map
- corresponding building state updated (visited/delivered visual state)
- session target/building may be marked complete (`SessionManager.completeBuilding(...)`)
- delivered count increments (`SessionManager.recordAddressDelivered()`)
- server visit status is written via `VisitsAPI.updateStatus(..., status: .delivered)`

## 5) What gets persisted

During session:
- periodic session progress sync (`SessionsAPI.updateSession`) including path, distance, counters.

On session end:
- raw path is saved as `path_geojson`
- normalized path is saved as `path_geojson_normalized` when available
- lifecycle/session events are logged

## 6) Key files

- GPS intake + session state: `FLYR/Features/Map/SessionManager.swift`
- Pro GPS filtering config: `FLYR/Features/Map/GPSNormalization/GPSNormalizationConfig.swift`
- Pro acceptance filter: `FLYR/Features/Map/GPSNormalization/LocationAcceptanceFilter.swift`
- Road normalization pipeline: `FLYR/Features/Map/GPSNormalization/SessionTrailNormalizer.swift`
- Flyer proximity completion: `FLYR/Features/Map/FlyerModeManager.swift`
- Campaign map path rendering + visited paint: `FLYR/Features/Map/Views/CampaignMapView.swift`
- Session map renderer: `FLYR/Features/Map/SessionMapboxViewRepresentable.swift`
