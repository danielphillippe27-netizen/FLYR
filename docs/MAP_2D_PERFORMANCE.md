# 2D map performance checks

Run the geometry and pin-action regressions without a simulator:

```sh
bash scripts/test-standard-campaign-map.sh
```

The same cases are XCTest tests in `WolfGridTests`. They cover 1,000-home layouts,
all zoom levels, 10,000-home repeated updates, coordinate edits, invalid geometry,
and status actions chosen before a local pin write completes or after dismissal.

`StandardCampaignGoogleMapCoordinatorTests` additionally exercises real Google
overlays, marker callbacks, status updates and gesture/idle transitions. Run these
in Xcode with the WolfGrid test target and a configured Google Maps API key.

To open the real 2D renderer for profiling, set the Debug scheme environment
variable `WOLFGRID_MAP_FORCE_2D=1`. This is ignored by Release builds. Filter the
Xcode console for `flow=map_2d`:

- `quick_status_visible`: tap-to-overlay time, including the next SwiftUI render.
- `prepare_quick_status` and `marker_tap`: synchronous selection/callback work.
- `create_pin_locally`: durable pin and outbox creation, without waiting for geocoding.
- `sync_markers`: actual marker changes and update duration.
- `cluster_layout`: layout/apply duration, rebuild count and cluster overlay creations.
- `camera_gesture`: time from a user camera gesture until Google reports idle.

Unchanged data and fractional zoom within a grid must not increase rebuild count.
Gesture updates apply their latest geometry once at idle; individual pins appear
at zoom 18. These timings measure code paths, not display frame rate.

Device checks still required:

1. In 2D, tap an existing pin and a new home; choose each of the five statuses.
2. Choose a status immediately on a new pin, then repeat offline. Dismiss a new
   menu before its save finishes and verify it does not reopen.
3. Pinch/pan a 1,000-home area, cross zoom 18 in both directions, and tap after zooming.
4. Add a pin in 2D, switch to 3D building view, and confirm its push-pin model is
   visible beside buildings while regular address extrusions stay hidden.
5. Reload the campaign and confirm pin identity, location and status persist.

## 2D user location and selection feedback

The Google 2D renderer uses a cached blue location-dot icon, a GPS accuracy circle and a separate flat heading cone. The cone receives the existing reliable heading presentation, rotates in map coordinates, and hides when heading is unavailable. Both location overlays are reused for stationary compass updates; the 3D wolf is unchanged.

`StandardCampaignGoogleMapCoordinatorTests` includes overlay reuse across 355° → 5° heading updates and cleanup for unavailable heading/hidden location. These tests were typechecked against the real Google Maps SDK but require a simulator/device for execution.

House selections and new pins use `HapticManager.mapSelection()`, which plays the native success notification pattern previously used for saved pins. A 2D draft plays it when the menu opens; its later local save does not repeat it. Saved standalone selections suppress an additional highlight haptic. Both app targets share this behavior. Haptic helpers pass UIKit SDK typechecking; physical feel still requires a device.
