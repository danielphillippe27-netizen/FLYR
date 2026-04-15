# GPS Tracking, Proximity Knocking, and Breadcrumb Trails

Status: current implementation in this repo as inspected on 2026-03-13.

This document explains exactly what FLYR is doing today for:

- GPS breadcrumb tracking during sessions
- proximity-based completion for doorknocking
- proximity-based completion for flyer mode
- what gets stored in Supabase
- whether this is a Pro feature or related to the Gold building pipeline

## Short Answer

Door knocking and flyer mode use the same GPS session engine and the same breadcrumb trail pipeline.

The main difference is the auto-complete target:

- Doorknocking proximity is building-based
- Flyer proximity is address-based

This is not the same thing as the Gold building pipeline, and it is not generally gated as a Pro feature.

Gold/Silver/address-point affects how homes/buildings are loaded and linked on the map. It does not change how breadcrumb GPS tracking works once the session starts.

Quick Start is the only nearby-home flow here that is Pro-gated or limited, not the campaign session tracking itself.

## 1. Shared GPS Engine

Both modes run through `SessionManager`.

Relevant code:

- `FLYR/Features/Map/SessionManager.swift`
- `FLYR/Features/Map/Views/CampaignMapView.swift`

What `SessionManager` does for both modes:

- owns `pathCoordinates`, `distanceMeters`, `elapsedTime`, `currentLocation`, `sessionMode`
- starts Core Location updates
- filters noisy GPS samples
- appends accepted points to the breadcrumb trail
- syncs session progress back to Supabase while the session is running
- writes the final `path_geojson` breadcrumb when the session ends

Important implementation details:

- location updates use `desiredAccuracy = kCLLocationAccuracyBest`
- `distanceFilter = 2.0`
- background location updates are enabled
- heading updates are also tracked

Source:

- `FLYR/Features/Map/SessionManager.swift:145`
- `FLYR/Features/Map/SessionManager.swift:156`

## 2. Breadcrumb Trail Logic

The breadcrumb trail is the same concept in both modes.

Accepted GPS points are added to `pathCoordinates`, then displayed on the map as a red line and stored as a GeoJSON `LineString`.

### GPS filtering before a point is accepted

The app rejects points when:

- horizontal accuracy is worse than 15 m
- implied speed between samples is 10 m/s or faster
- reported speed is below the minimum movement threshold
- movement is too small to be real walking instead of GPS drift

Thresholds in code:

- max horizontal accuracy: `15.0 m`
- minimum movement: `3.0 m`
- stationary movement requirement: `8.0 m`
- max segment time gap before a visual line break: `15 s`
- max distance for a continuous segment across a gap: `30 m`

Source:

- `FLYR/Features/Map/SessionManager.swift:118`
- `FLYR/Features/Map/SessionManager.swift:124`
- `FLYR/Features/Map/SessionManager.swift:862`
- `FLYR/Features/Map/SessionManager.swift:931`

### Visual breadcrumb rendering

On the campaign map, the breadcrumb is rendered as:

- a red line layer
- a current-location puck

Before rendering, the path is simplified with a 5 m tolerance and split into separate segments so large time/location gaps do not draw fake bridges.

Source:

- `FLYR/Features/Map/Views/CampaignMapView.swift:1269`
- `FLYR/Features/Map/Views/CampaignMapView.swift:1304`
- `FLYR/Features/Map/SessionManager.swift:935`
- `FLYR/Features/Map/SessionManager.swift:1002`

### What is stored

The breadcrumb is stored in `sessions.path_geojson` as GeoJSON text.

Schema/source:

- `supabase/migrations/20250201000000_create_sessions_table.sql:13`
- `FLYR/Features/Map/Services/SessionsAPI.swift:96`
- `FLYR/Features/Map/Services/SessionsAPI.swift:130`
- `FLYR/Features/Map/Models/SessionRecord.swift:56`

## 3. Door-Knocking Proximity

Door-knocking proximity is building-based.

When a building session starts, the app builds a centroid map for each target building and stores those centroids in `SessionManager.buildingCentroids`.

Source:

- `FLYR/Features/Map/Views/CampaignMapView.swift:1516`
- `FLYR/Features/Map/SessionManager.swift:290`

### Auto-complete rules for doorknocking

Auto-complete only runs when `autoCompleteEnabled` is true.

That proximity check:

- finds the nearest incomplete building centroid
- requires the user to be within `15.0 m`
- requires dwell time of `8 s`
- requires speed below `2.5 m/s`
- debounces repeat completions for `3 s`

When it fires, the app:

- marks the building complete in memory
- logs a `completed_auto` session event with lat/lon and metadata
- updates `sessions.completed_count`

Source:

- `FLYR/Features/Map/SessionManager.swift:108`
- `FLYR/Features/Map/SessionManager.swift:113`
- `FLYR/Features/Map/SessionManager.swift:754`
- `FLYR/Features/Map/API/SessionEventsAPI.swift:12`
- `supabase/migrations/20250208000000_session_recording.sql:130`

Important: in the current campaign map start flow, doorknock mode starts with `autoCompleteEnabled: false`, so manual completion is the default path there.

Source:

- `FLYR/Features/Map/Views/CampaignMapView.swift:1536`

## 4. Flyer Mode Proximity

Flyer mode uses the same `SessionManager` GPS breadcrumbs, but proximity completion is handled by `FlyerModeManager`.

That is the biggest implementation difference between the two modes.

Relevant code:

- `FLYR/Features/Map/FlyerModeManager.swift`
- `FLYR/Features/Map/Views/CampaignMapView.swift`

### Flyer auto-complete target

Flyer mode works per address, not per building.

It loads addresses from:

- address point features first
- building feature centroids as a fallback when address points are missing

Source:

- `FLYR/Features/Map/FlyerModeManager.swift:28`
- `FLYR/Features/Map/FlyerModeManager.swift:66`
- `FLYR/Features/Map/FlyerModeManager.swift:87`

### Flyer proximity rules

Flyer proximity:

- starts from a base threshold of `10.0 m`
- expands adaptively up to `20.0 m` based on GPS horizontal accuracy
- requires `5 s` dwell
- blocks auto-complete if moving faster than `2.5 m/s`

When it fires, the app:

- calls the UI completion callback
- marks the address `delivered`
- updates the address and building states on the map
- logs a delivered visit through `VisitsAPI`
- records the address as delivered in `SessionManager`
- also completes the building in the session if that address maps back to a building

Source:

- `FLYR/Features/Map/FlyerModeManager.swift:15`
- `FLYR/Features/Map/FlyerModeManager.swift:159`
- `FLYR/Features/Map/FlyerModeManager.swift:210`
- `FLYR/Features/Map/Views/CampaignMapView.swift:523`

### Flyer mode session start behavior

When flyer mode starts from the campaign map:

- display mode switches to `Addresses`
- the app asks for `Always` location if it does not already have it
- the session still starts even if the user chooses not to upgrade permission

The reason for the prompt is background reliability, not because flyer mode uses a different breadcrumb implementation.

Source:

- `FLYR/Features/Map/Views/CampaignMapView.swift:808`
- `FLYR/Features/Map/Views/CampaignMapView.swift:836`
- `FLYR/Features/Map/SessionManager.swift:158`
- `FLYR/Info.plist:61`

## 5. Are the Breadcrumbs Similar?

Yes. Operationally they are the same breadcrumb system.

Both modes:

- use the same `SessionManager.pathCoordinates`
- use the same GPS sample filtering
- use the same live map line rendering
- sync the same breadcrumb path to `sessions.path_geojson`
- produce the same end-session summary path

The difference is not the breadcrumb trail. The difference is what counts as a completed target.

## 6. Is It "Pro Mode"?

Not for campaign session GPS tracking.

The campaign map exposes both:

- `Doorknock`
- `Flyers`

without a Pro entitlement check in that session-start flow.

Source:

- `FLYR/Features/Map/Views/CampaignMapView.swift:754`

What is Pro-gated is Quick Start / Quick Campaign:

- `SessionStartView` sends non-Pro users to the paywall for Quick Campaign
- `QuickStartMapView` says Quick Start is a Pro feature after the free allowance is exhausted

Source:

- `FLYR/Features/Map/Views/SessionStartView.swift:90`
- `FLYR/Features/QuickStart/QuickStartMapView.swift:23`
- `FLYR/Features/QuickStart/QuickStartMapView.swift:77`

So:

- campaign doorknock/flyer GPS tracking: not a Pro-only system
- Quick Start nearby-home creation: Pro/limited

## 7. Is It the "Gold Standard"?

No, not in the data-pipeline sense.

"Gold" in this repo refers to Gold reference building/address data, not to the GPS tracking engine.

Gold/Silver/address-point affects:

- how homes/buildings are loaded
- whether polygons or address points are shown
- how addresses are linked to buildings

It does not define the breadcrumb logic or session GPS recording.

Source:

- `docs/IOS_GOLD_SILVER_BUILDINGS_GUIDE.md`

The only intersection is indirect:

- flyer mode prefers address points when they exist
- if address points are sparse, it falls back to building-derived centroids

That changes the target geometry, not the breadcrumb tracker itself.

## 8. What Gets Written to the Database

### Session row

The active session row contains or is updated with:

- `start_time`
- `end_time`
- `distance_meters`
- `goal_type`
- `goal_amount`
- `path_geojson`
- `target_building_ids`
- `completed_count`
- `flyers_delivered`
- `conversations`
- `active_seconds`
- auto-complete settings

Source:

- `FLYR/Features/Map/Services/SessionsAPI.swift:83`
- `FLYR/Features/Map/Services/SessionsAPI.swift:128`
- `supabase/migrations/20250208000000_session_recording.sql:21`

### Session event rows

The app also logs `session_events` for:

- `session_started`
- `session_paused`
- `session_resumed`
- `session_ended`
- `completed_manual`
- `completed_auto`
- `completion_undone`

Those event rows can contain:

- `lat`
- `lon`
- `event_location`
- `building_id`
- `address_id`
- metadata

Source:

- `supabase/migrations/20250208000000_session_recording.sql:56`
- `FLYR/Features/Map/API/SessionEventsAPI.swift:12`

## 9. Best Single-Sentence Summary

FLYR currently uses one shared GPS breadcrumb tracker for both doorknock and flyer sessions; doorknock proximity is building-centroid based, flyer proximity is address based, and neither mode is inherently the Gold data path or a Pro-only campaign-session feature.
