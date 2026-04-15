# GPS To Green House Workflow Guide

This guide traces the current FLYR iOS flow from live GPS intake to a house turning green on the map. It is based on the code that currently runs in the app, not just older docs.

## What "green house" actually means

A house turning green is not a single write. The app currently has three related but distinct tracks:

1. `sessions` / `session_events`
   Records that a session target was completed during an active session.
2. `address_statuses` / `campaign_addresses.visited`
   Records the address-level outcome like `delivered`, `talked`, `no_answer`.
3. `building_stats` + map feature state
   Drives the building polygon color and live visual updates.

Those tracks often move together, but not always. That is the core thing to understand before optimizing.

## End-to-end architecture

```text
CLLocationManager
  -> SessionManager
      -> GPS acceptance filters
      -> raw path append
      -> optional road/corridor normalization
      -> visit inference
          -> local completion state
          -> map notification / local style update
          -> VisitsAPI outcome write
          -> SessionEventsAPI session event write
          -> SessionsAPI progress/session row update
              -> Supabase tables / RPCs
                  -> address_statuses
                  -> campaign_addresses.visited
                  -> session_events
                  -> sessions.completed_count
                  -> building_stats (directly or via backend triggers)
                      -> BuildingStatsSubscriber
                          -> CampaignMapView / MapLayerManager
                              -> building turns green
```

## Primary source files

- `FLYR/Features/Map/SessionManager.swift`
- `FLYR/Features/Map/Views/CampaignMapView.swift`
- `FLYR/Features/Map/FlyerModeManager.swift`
- `FLYR/Features/Campaigns/API/VisitsAPI.swift`
- `FLYR/Features/Map/API/SessionEventsAPI.swift`
- `FLYR/Features/Map/Services/SessionsAPI.swift`
- `FLYR/Features/Map/Services/BuildingStatsSubscriber.swift`
- `FLYR/Features/Map/GPSNormalization/LocationAcceptanceFilter.swift`
- `FLYR/Features/Map/GPSNormalization/ScoredVisitEngine.swift`
- `supabase/migrations/20260328103000_fix_address_statuses_campaign_id_in_outcome_rpc.sql`

## 1. Session start

Session start begins in `CampaignMapView.startBuildingSession(...)`, which resolves targets and centroids, then calls `SessionManager.startBuildingSession(...)`.

At session start, `SessionManager`:

1. creates a `sessions` row through `SessionsAPI.createSession(...)`
2. stores target ids and centroids in memory
3. loads road corridors when Pro mode is enabled
4. creates:
   - `SessionTrailNormalizer`
   - `ScoredVisitEngine`
5. requests location authorization and starts `CLLocationManager`
6. logs `session_started` through `SessionEventsAPI.logLifecycleEvent(...)`

Important details:

- `autoCompleteEnabled` is `false` for door knocking and `true` for flyer mode.
- If campaign roads are missing and Pro mode is on, session start can be blocked.
- The session row is created before tracking begins.

## 2. GPS intake

GPS points enter through `SessionManager.locationManager(_:didUpdateLocations:)`.

`SessionManager` always updates `currentLocation`, but only accepted points are added to the tracked path.

### Filter layer A: Pro acceptance filter

When Pro normalization is enabled, `LocationAcceptanceFilter` rejects points if:

- `horizontalAccuracy <= 0`
- `horizontalAccuracy > maxHorizontalAccuracy`
- displacement from the last accepted point is below `minMovementDistance`
- implied speed is above `maxWalkingSpeedMetersPerSecond`

Default config in `GPSNormalizationConfig`:

- max horizontal accuracy: `20m`
- min movement: `4m`
- max walking speed: `3.2 m/s`

### Filter layer B: session anti-drift filter

After that, `SessionGPSFilter` and local guards inside `SessionManager` further suppress:

- tiny movement
- idle drift
- impossible jumps
- long-gap segment continuity errors

Key constants in `SessionManager`:

- base moving threshold: `3m`
- stationary threshold: `8m`
- stationary speed threshold: `0.4 m/s`
- stationary min implied speed: `0.55 m/s`
- hard max implied speed: `10 m/s`
- segment break trigger: `>15s` gap plus `>30m` displacement

## 3. Path recording and rendering

When a point is accepted:

1. it is appended to `SessionManager.pathCoordinates`
2. distance is added to `distanceMeters`
3. the normalizer processes the point if Pro mode is active
4. session progress sync is queued
5. live activity is updated

The app renders:

- normalized path when Pro mode has valid normalized output
- otherwise a simplified raw path

Rendering path:

- `SessionManager.renderPathSegments()`
- `CampaignMapView.updateSessionPathOnMap()`
- Mapbox GeoJSON line source update

Important invariant from `ScoredVisitEngine.swift`:

> visit inference uses accepted raw points plus corridor context only, never the rendered path

That separation is good and should be preserved.

## 4. How GPS decides a target is visited

There are two visit inference engines in play.

### Path A: scored visit engine

Used when Pro mode roads are loaded and `useScoredVisitEngine` is active.

`ScoredVisitEngine.process(...)` scores each incomplete target using:

- proximity tier 1
- proximity tier 2
- corridor progress past frontage
- dwell/slowdown
- repeated nearby confirmations
- wrong-side penalty

Default score config:

- proximity tier 1: `15m`
- proximity tier 2: `15m`
- dwell min: `3s`
- slowdown max speed: `0.6 m/s`
- repeated nearby count: `2`
- visit threshold: `2`

Because both proximity tiers are `15m`, one accepted fix within `15m` can be enough to complete a target.

When a target crosses threshold:

1. `SessionManager.applyLocalCompletionState(...)` inserts it into `completedBuildings`
2. a map notification is posted: `.sessionBuildingAutoCompleted`
3. a share-card pin is appended

For door knocking, this local auto-complete happens before the server side is guaranteed to persist.

### Path B: legacy dwell completion

`SessionManager.checkAutoComplete(...)` is still active for door knocking, and is also the fallback when scored inference is unavailable.

Requirements:

- nearest incomplete centroid within `15m`
- speed below `2.5 m/s`
- dwell for `8s`
- debounce window of `3s`

When it fires:

1. local completion state is updated
2. auto-complete notification is posted
3. share-card pin is appended

Again, this is local-first.

## 5. The exact "turn green" flow on the map

When `SessionManager` posts `.sessionBuildingAutoCompleted`, `CampaignMapView` receives it and calls `markAutoCompletedBuildingDelivered(gersId:)`.

That method:

1. resolves all address ids linked to the building
2. filters out addresses already marked delivered
3. calls `VisitsAPI.updateTargetStatus(...)` with:
   - `status = .delivered`
   - `sessionId`
   - `sessionTargetId = gersId`
   - `sessionEventType = .flyerLeft`
4. updates local address state cache
5. recomputes the building status
6. calls `layerManager.updateBuildingState(...)`

So the green house effect is currently produced by a mix of:

- immediate local feature-state update
- address outcome persistence
- later realtime or polling updates from `building_stats`

## 6. Database writes involved

### Session row

`SessionsAPI.createSession(...)` inserts into `sessions` with:

- `campaign_id`
- `target_building_ids`
- `completed_count`
- `path_geojson`
- auto-complete settings
- counters like `flyers_delivered`, `conversations`, `leads_created`

`SessionsAPI.updateSession(...)` later updates:

- `completed_count`
- `distance_meters`
- `active_seconds`
- `path_geojson`
- `path_geojson_normalized`
- counters
- `end_time`

### Session event RPC

`SessionEventsAPI.logEvent(...)` calls `rpc_complete_building_in_session`.

This is used for:

- `completed_manual`
- `completed_auto`
- `completion_undone`
- lifecycle events

This is the main session-completion write path.

### Address outcome RPC

`VisitsAPI.updateStatus(...)` and `VisitsAPI.updateTargetStatus(...)` prefer the RPC:

- `record_campaign_address_outcome`

That RPC currently:

1. validates campaign and session ownership
2. upserts into `address_statuses`
3. updates `campaign_addresses.visited`
4. optionally inserts into `session_events`
5. optionally increments or decrements `sessions.completed_count`

This means the outcome RPC overlaps with work the session RPC also does.

## 7. Why a house can turn green even if persistence is inconsistent

There are multiple local-first paths:

- `SessionManager.completeBuilding(...)` marks local completion before RPC success
- scored auto-complete marks local completion before persistence
- legacy dwell marks local completion before persistence
- `CampaignMapView.flyerAddressCompleted(...)` updates local map state immediately

This is great for responsiveness, but it means visual state can get ahead of server truth.

## 8. Restore behavior after app kill

`SessionManager.restoreActiveSessionIfNeeded()` reloads the active session, but it cannot fully resume GPS-based building matching until centroids are restored.

That is why `CampaignMapView.rehydrateSessionVisitInferenceIfNeeded()` matters:

1. map features load
2. targets are rebuilt from building and address features
3. `SessionManager.rehydrateVisitInferenceFromMapTargets(...)` repopulates centroids
4. scored visit inference can work again

Without that rehydration, active session restore can have a path and session id but no valid target matching.

## 9. Realtime path for durable green state

`BuildingStatsSubscriber` subscribes to `building_stats` via:

- Supabase Realtime WebSocket when available
- 5-second polling fallback otherwise

When updates arrive, `CampaignMapView` calls `updateBuildingColor(...)`, which forwards to `MapLayerManager.updateBuildingState(...)`.

This is the durable visual sync path for building colors across devices and app refreshes.

## 10. Current behavior by mode

### Door knocking

- GPS drives completion primarily through `SessionManager`
- building ids are session targets
- local completion happens fast
- auto-complete notification triggers address outcome sync in `CampaignMapView`
- green building can appear before all writes settle

### Flyer mode

- targets are typically address ids
- `FlyerModeManager` owns proximity UX
- scored completion or legacy dwell marks addresses `delivered`
- map updates address state first, then building state derived from all units
- if a building has multiple units, green only happens when all relevant unit statuses qualify as visited

## 11. Known coupling and duplication

These are the places most likely to create bugs or drift.

### A. Two persistence systems can both affect completion counts

- `SessionEventsAPI.logEvent(...)` via `rpc_complete_building_in_session`
- `VisitsAPI.updateTargetStatus(...)` via `record_campaign_address_outcome`

Both can touch `session_events` and `sessions.completed_count`, depending on which path is used.

### B. Local UI state leads server state

Local map styling and `completedBuildings` update before persistence succeeds in several paths.

### C. Door-knocking still has dual inference paths

Both scored inference and legacy dwell can run in the same session. That improves resilience, but it also creates overlap and can make debugging harder.

### D. Building color is derived from address status in some paths, and from `building_stats` in others

That means your green house can come from:

- locally derived address state
- realtime `building_stats`
- session completion-only local feature state

Those are not one canonical source of truth.

### E. Restore depends on map feature rehydration

Session restore is not fully self-contained. GPS matching needs the map load path to rebuild centroids.

## 12. Optimization opportunities

### Highest value

1. Pick one canonical completion write path.
   Use either:
   - session event RPC as the single completion authority, or
   - address outcome RPC as the single completion authority for target completion

   Right now both can represent completion and update counters.

2. Separate visual optimism from persisted truth explicitly.
   Add a transient local state like `pendingVisitedTargets` instead of immediately treating local completion as durable completion.

3. Make building color derive from one canonical state machine.
   The cleanest option is usually:
   - address statuses are the truth for outcome
   - building status is a server-derived aggregate
   - UI consumes that aggregate consistently

4. Make restore self-sufficient.
   Persist target centroids or a resolvable target snapshot with the session so GPS inference does not depend on a later map feature rehydration pass.

### Medium value

5. Remove or gate the legacy dwell fallback more explicitly.
   If scored inference is healthy, keep dwell off or log when it becomes the active fallback.

6. Instrument rejection reasons and completion reasons.
   Log counts for:
   - poor accuracy rejects
   - too-close rejects
   - too-fast rejects
   - scored completions
   - dwell completions
   - local complete / server failed cases

7. Push more business logic into one backend function.
   If "house turns green" means all addresses for a target are delivered or otherwise visited, let one backend RPC own:
   - address outcome upsert
   - session event insert
   - session completed count
   - building aggregate update

### Lower value but still useful

8. Reduce duplicated local recomputation in `CampaignMapView`.
   Building status recalculation is scattered across multiple handlers.

9. Make polling fallback campaign-filtered server side if possible.
   Current polling reads `building_stats` by campaign and diffs locally every 5 seconds.

10. Add a debug screen for one target.
   Show:
   - latest accepted GPS
   - corridor context
   - scored visit score
   - centroid distance
   - last persisted address status
   - last building_stats status

## 13. Recommended target architecture

If you want the cleanest future system:

1. GPS only decides "candidate target reached"
2. one RPC accepts that candidate and owns all persistence
3. server derives building aggregate state
4. UI shows optimistic pending state until the server confirms
5. realtime `building_stats` becomes the durable cross-device source for green/red/blue buildings

That keeps:

- GPS logic on device
- business truth on backend
- rendering logic thin

## 14. Fast review checklist

- Is a target marked locally before persistence?
- Which RPC wrote the durable completion?
- Did `address_statuses` update?
- Did `campaign_addresses.visited` update?
- Did `session_events` get a row?
- Did `sessions.completed_count` change once or twice?
- Did `building_stats` update?
- Did the map turn green from local state, realtime state, or both?

## Bottom line

Today, the workflow works, but it is split across local optimistic state, session RPCs, outcome RPCs, and realtime building aggregation. The biggest optimization is not GPS math. It is simplifying the ownership model so one completion event produces one durable chain of truth, and the map becomes a clean reflection of that chain.
