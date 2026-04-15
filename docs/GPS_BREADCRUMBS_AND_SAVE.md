# GPS Breadcrumbs & Saving the Drawing

How FLYR uses GPS to build the session breadcrumb trail and how the drawing is stored and displayed.

---

## 1. Overview

Three logical layers (naming matters for future work):

| Layer | Meaning |
|-------|--------|
| **Observed raw** | Every GPS callback from `CLLocationManager`. Not stored; used only for acceptance filtering. |
| **Accepted raw** | Points that pass the acceptance filter. Used for distance, path length, and the stored “raw” path. This is what we persist as `path_geojson` — **not** every GPS sample. |
| **Normalized** | Snapped to roads + side offset + smoothing. Used for display and (when present) for `path_geojson_normalized`. |

- **Distance (km)** is always from **accepted raw** movement, not from the normalized line.
- **Two paths** are stored: **accepted raw** and **normalized** (road-snapped, side-offset, simplified for storage). The map and share card prefer the normalized path when available.

---

## 2. When a Session Starts (Building Session)

1. **Session row** is created in Supabase with empty `path_geojson` and no `path_geojson_normalized`.
2. **Campaign roads** are loaded for Pro GPS:
   - `CampaignRoadService.getRoadsForSession(campaignId)` → device cache first, then `rpc_get_campaign_roads_v2` if needed.
   - Roads are converted to `[StreetCorridor]` (polylines with cumulative distances).
3. If Pro mode is on and roads exist:
   - `SessionTrailNormalizer(config, corridors, buildingCentroids)` is created.
   - Corridors are also stored in `sessionRoadCorridors` so the map can draw road centerlines.
4. If no roads or Pro mode off: no normalizer; trail will be raw (and later simplified for display).

---

## 3. GPS → Breadcrumb Pipeline (Live)

Each `CLLocation` from `CLLocationManager` goes through:

### 3.1 Session gate

- If there’s no `sessionId`, we only update `currentLocation` and return (no path/distance).

### 3.2 Acceptance filter (Pro mode)

When **Pro GPS normalization** is enabled, `LocationAcceptanceFilter` decides whether to use the point for the trail:

| Check | Reject if |
|-------|-----------|
| Accuracy | `horizontalAccuracy <= 0` or `> maxHorizontalAccuracy` (default 20 m) |
| Too close | Distance from last accepted point `< minMovementDistance` (default 3 m) |
| Too fast | Implied speed (distance / time delta) `> maxWalkingSpeedMetersPerSecond` (default 2.2 m/s) |

Rejected points are not appended to `pathCoordinates` and are not passed to the normalizer.

### 3.3 Legacy checks (always)

Even when Pro filter passes, we still require:

- Implied speed &lt; 10 m/s (spike filter).
- Minimum speed or movement (stationary vs moving thresholds).
- Movement ≥ `requiredMovementDistance` (uses `minPathMovementMeters` and GPS accuracy when stationary).

### 3.4 Append to accepted raw path and distance

- **Accepted raw path:** `pathCoordinates.append(location.coordinate)`. Only points that passed all filters above are appended. So **`path_geojson` is not literally every GPS sample — it is every accepted sample.** Rejected samples are never written to the path or to storage.
- **Distance:** `distanceMeters += distance(from: lastLocation)` (only for accepted points).
- **Segment break:** If time gap &gt; 15 s and distance &gt; 30 m from last point, we insert a segment break so the trail can have multiple polylines (e.g. after a drive). Segment breaks are currently **implicit** (indices in memory); see §4.5 and §5.1 for storing them as first-class geometry.

### 3.5 Normalization (Pro mode only)

If a `SessionTrailNormalizer` exists, we call:

`trailNormalizer?.process(acceptedLocation: location)`.

For each accepted point the normalizer:

1. **Projects** the point onto the nearest **StreetCorridor** within `maxLateralDeviation` (default 10 m).
2. Runs **corridor-switch stabilization** before changing roads:
   - Compares the current corridor vs candidate corridor at the same raw point.
   - Requires a minimum lateral improvement (`corridorSwitchHysteresisMeters`, default 4 m).
   - Requires repeated confirmation (`corridorSwitchConfirmationPoints`, default 2 points).
   - If not confident, it stays on the current corridor for this point.
3. If a switch is committed:
   - Inserts a **segment break** in the normalized trail.
   - Resets **progress** and **side-of-street** state for the new street.
4. **Progress constraint:** Rejects large backward jumps along the corridor (beyond `backwardToleranceMeters`, default 8 m); keeps previous normalized point if rejected.
5. **Side-of-street:** Infers left/right from the user position and optional building centroids; applies a **perpendicular offset** from the road centerline (default **5 m**).
6. **Smoothing:** Applies a small moving-average window (default 3 points) to the offset point.
7. Appends the resulting coordinate to the **normalized** trail.

### 3.6 Projection dropout behavior (anti-hallucination)

When a point cannot be projected within `maxLateralDeviation`, we avoid drawing raw drift unless we are truly away from roads:

- If nearest corridor is still close (`<= maxProjectionGapBeforeRawFallbackMeters`, default 45 m), we **hold last normalized point**.
- If nearest corridor is far (`> maxProjectionGapBeforeRawFallbackMeters`), we fallback to raw for that point.

This prevents single noisy samples from drawing fake branches across yards/blocks while still allowing true off-network movement when needed.

So: **breadcrumb = sequence of normalized points** (or raw when no projection), with segment breaks at corridor switches.

### 3.7 What the map draws

- **Session path:** `SessionManager.renderPathSegments()`:
  - Pro mode + normalizer has points → **normalized segments** (with segment breaks).
  - Otherwise → **simplified accepted raw path** (Douglas–Peucker style simplification per segment).
- Map updates when `pathCoordinates.count` changes; it re-reads `renderPathSegments()` and pushes them to the session line GeoJSON source.
- **Roads:** Campaign road centerlines (`sessionRoadCorridors`) are drawn as a separate layer so the trail aligns with the road network.

So the **drawing** the user sees is the normalized (or simplified accepted raw) breadcrumb trail, continuous across 90° turns (segment break only affects smoothing/progress, not continuity of the line).

---

## 4. Saving the Drawing

### 4.1 During the session (progress sync)

Periodically and on background/foreground, we call `SessionsAPI.updateSession(...)` with:

- `pathGeoJSON` = **accepted raw** path: `coordinatesToGeoJSON(pathCoordinates)`.

So the **accepted raw breadcrumb** is saved incrementally. `path_geojson_normalized` is **not** sent during the session; it is only set at session end.

### 4.2 When the session ends (`stopBuildingSession`)

1. **Accepted raw path:**  
   `pathGeoJSON = coordinatesToGeoJSON(pathCoordinates)`  
   → same accepted points as during sync.

2. **Normalized path:**  
   - `normalizedPath = trailNormalizer?.finalizeNormalizedTrail() ?? pathCoordinates`  
   - `finalizeNormalizedTrail()` runs **Douglas–Peucker** on the normalized points (default tolerance 1.5 m) to reduce point count for storage.  
   - `pathGeoJSONNormalized = coordinatesToGeoJSON(normalizedPath)` (or `nil` if empty).

3. **Single update** to Supabase:
   - `path_geojson` = accepted raw path.
   - `path_geojson_normalized` = normalized, simplified path (when Pro was used and we have normalized points).
   - Also: `distance_meters`, `active_seconds`, `completed_count`, `flyers_delivered`, `conversations`, `end_time`, etc.

So we **always save the accepted raw drawing**; we **additionally save the normalized drawing** when Pro GPS produced one.

### 4.3 End-session summary and share card

- **Summary path:**  
  `summaryPath = normalizedPath.isEmpty ? pathCoordinates : normalizedPath`  
  So the end-session sheet and share card use the **normalized** path when available.

- **Share card:**  
  `SessionShareCardView` and `ShareCardGenerator.generateShareImages(data:)` use `SessionSummaryData.pathCoordinates`. That data comes from the snapshot above (normalized if available). So the **share card uses the same (normalized) drawing** as the summary.

### 4.4 Loading a past session (e.g. share card from history)

- `SessionRecord` decodes path from DB:
  - `decodedPathCoordinates()` returns **normalized** if `path_geojson_normalized` is present and non-empty.
  - Otherwise it uses **accepted raw** `path_geojson`.
- `toSummaryData()` uses that decoded path as `pathCoordinates`. So when you open a past session for the share card, you again see the **normalized drawing** when it was saved.

### 4.5 Segment breaks and storage shape (recommendation)

Today, segment breaks are **implicit**: we store a single LineString (flat coordinate array) and maintain break indices only in memory for rendering and normalized segmentation. That works for display but is weaker for:

- Long sessions with a drive in between (disjoint movement can look or analyze oddly).
- Share cards, history, and analytics that want **true multi-segment geometry**.
- Replay, exports, and tools that expect disjoint segments to be explicit.

**Recommended direction:** treat segment breaks as first-class data:

- **Raw path:** store as **MultiLineString** (one LineString per segment), not a single LineString. Same accepted-raw points, but segments are explicit.
- **Normalized path:** store as **MultiLineString** as well, so corridor switches and time-gap breaks are explicit in the geometry.

That future-proofs replay, exports, and advanced analytics without changing the live pipeline — only the serialization and DB shape.

---

## 5. Design notes, risks & future work

### 5.1 Segment breaks as first-class

See §4.5. Right now segment breaks are implicit in rendering / normalized segmentation. Storing both paths as **MultiLineString** would make disjoint movement explicit and improve long-session appearance, share cards, and analytics.

### 5.2 Corridor switch: visual harshness (status: partially mitigated)

On **new corridor → segment break, reset progress, reset side-of-street**, the logic is correct, but this is where users are most likely to see odd behavior at:

- Intersections  
- Curved roads  
- Short connector streets  
- Cul-de-sacs  
- Brief road crossings  

Risks: false corridor changes near intersections, ping-pong switching between adjacent streets, line “teleporting” across the road. We now mitigate this with hysteresis + confirmation, but edge cases still exist at complex intersections and cul-de-sacs.

Implemented:

- **Corridor hysteresis** (`corridorSwitchHysteresisMeters`) — new corridor must be meaningfully better.
- **Switch confirmation** (`corridorSwitchConfirmationPoints`) — avoid switching on a single noisy point.

Still worth considering:

- Dynamic thresholds by road density (tight downtown grids vs suburban streets).
- Temporal confidence scoring (e.g. switch confidence decay/recovery instead of fixed point count).

### 5.3 Projection dropouts and raw drift (status: mitigated)

Historically, if projection failed for one or two points, the trail used raw GPS and could "hallucinate" side branches.

Implemented:

- **Near-road dropout hold** (`maxProjectionGapBeforeRawFallbackMeters`) keeps the trail anchored when projection briefly fails.

Residual risk:

- If GPS quality is consistently poor for long stretches, anchored points can create visible pauses/flat segments until projection recovers.

### 5.4 Side-of-street: confidence and overconfidence

Side-of-street + 5 m offset is premium when correct, but when wrong it can look like the user walked through lawns, was on the wrong side, or jumped across streets. Recommendations:

- **Confidence-aware offset:**  
  - High confidence → full offset (e.g. 5 m).  
  - Medium confidence → smaller offset.  
  - Low confidence → centerline (0 m).  
- Allow the side offset to be disabled or softened per point when confidence is low so the trail feels more natural and less “fake.”

### 5.5 Simplification tolerance by use case

Douglas–Peucker at session end is good, but one tolerance for everything can be limiting. Different use cases may want different tolerances:

| Use case | Typical need |
|----------|----------------|
| **DB storage** | Fewer points, smaller payload. |
| **Map rendering** | Balance fidelity and performance. |
| **Share card** | Clean, beautiful line (possibly more aggressive simplification). |
| **History replay** | Higher fidelity. |

Consider separate tolerances (or separate simplified variants) for storage vs. display vs. share so each consumer gets the right tradeoff.

---

## 6. Tuning Guide (Production)

Recommended tuning order when diagnosing bad trails:

1. **Acceptance quality first** (`maxHorizontalAccuracy`, `minMovementDistance`, `maxWalkingSpeedMetersPerSecond`).
2. **Corridor lock/stability** (`maxLateralDeviation`, `corridorSwitchHysteresisMeters`, `corridorSwitchConfirmationPoints`).
3. **Dropout handling** (`maxProjectionGapBeforeRawFallbackMeters`).
4. **Visual feel** (`preferredSideOffset`, `smoothingWindow`, simplification tolerance).

Practical starting profile for suburban door-knocking:

- `maxHorizontalAccuracy`: 20
- `minMovementDistance`: 4
- `maxLateralDeviation`: 22
- `corridorSwitchHysteresisMeters`: 4
- `corridorSwitchConfirmationPoints`: 2
- `maxProjectionGapBeforeRawFallbackMeters`: 45
- `preferredSideOffset`: 5
- `smoothingWindow`: 3

If you still see ping-pong at intersections:

- Raise `corridorSwitchHysteresisMeters` to 5-7.
- Raise `corridorSwitchConfirmationPoints` to 3.
- Optionally reduce `maxLateralDeviation` slightly (e.g. 22 -> 18-20) if roads are dense.

If you see too many frozen points (path not advancing during weak GPS):

- Lower `maxProjectionGapBeforeRawFallbackMeters` (e.g. 45 -> 30-35) so fallback to raw happens sooner.

## 7. Summary Table

| What | Source |
|------|--------|
| **Distance (km)** | Accepted raw GPS only (`distanceMeters`). |
| **Live map trail** | Normalized path (Pro) or simplified accepted raw path. |
| **Progress sync (during session)** | Accepted raw path only → `path_geojson`. |
| **At session end** | Both: accepted raw → `path_geojson`, normalized (simplified) → `path_geojson_normalized`. |
| **End-session summary & share card** | Normalized path if present, else accepted raw. |
| **Historical session share card** | Prefer `path_geojson_normalized`, else `path_geojson`. |

---

## 8. File reference

| Role | File(s) |
|------|--------|
| Location updates, path append, distance, progress sync | `FLYR/Features/Map/SessionManager.swift` |
| Pro acceptance filter | `FLYR/Features/Map/GPSNormalization/LocationAcceptanceFilter.swift` |
| Normalizer (project → side → offset → smooth) | `FLYR/Features/Map/GPSNormalization/SessionTrailNormalizer.swift` |
| Project onto roads | `FLYR/Features/Map/GPSNormalization/CorridorProjectionService.swift` |
| Side-of-street inference | `FLYR/Features/Map/GPSNormalization/SideOfStreetInference.swift` |
| Progress / backward rejection | `FLYR/Features/Map/GPSNormalization/ProgressConstraint.swift` |
| Smoothing | `FLYR/Features/Map/GPSNormalization/TrailSmoothing.swift` |
| Config (accuracy, offset, switch/dropout controls) | `FLYR/Features/Map/GPSNormalization/GPSNormalizationConfig.swift` |
| Geometry helpers | `FLYR/Features/Map/GPSNormalization/GeospatialUtilities.swift` |
| Road corridors | `FLYR/Features/Map/GPSNormalization/StreetCorridor.swift` |
| Map: path segments source | `FLYR/Features/Map/SessionMapboxViewRepresentable.swift` (uses `renderPathSegments()`) |
| Session API (path_geojson, path_geojson_normalized) | `FLYR/Features/Map/Services/SessionsAPI.swift` |
| Session model & summary path preference | `FLYR/Features/Map/Models/SessionRecord.swift` |
| Share card view | `FLYR/Features/Map/Views/SessionShareCardView.swift` |
| Campaign roads load for session | `FLYR/Services/CampaignRoadService.swift` |

---

## 9. Source of truth hierarchy

- **Movement truth:** accepted raw GPS.
- **Distance truth:** accepted raw GPS.
- **Display truth:** normalized path when available.
- **Storage truth:** accepted raw always; normalized optionally.
- **Historical display truth:** normalized preferred, accepted raw fallback.

This makes the philosophy explicit for future changes and for anyone working on replay, exports, or analytics.

---

## 10. Related docs

- **Campaign roads (where corridors come from):** `docs/CAMPAIGN_ROADS_TECHNICAL.md`
- **Road architecture (Supabase, web):** `FLYR_PRO_ROAD_ARCHITECTURE.md`
