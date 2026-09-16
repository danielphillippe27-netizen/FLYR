# Wolfy Companion + Live Pack — implementation status

Updated 2026-09-15. **Partial implementation; not a production release.**
This work preserves the pre-existing humanoid Wolfy and all unrelated dirty changes.

## Implemented and verified

- Original four-legged pup prototype: 6,758 vertices / 13,360 triangles, fifteen
  skeleton joints, seven sampled clips, editable Blender source, hashed binary
  runtime assets, source render and physical-device map captures.
- Five preliminary stage shape studies and editable Blender files are in
  `art/wolfy-v2/stages`. They vary head, torso, leg, chest and tail proportions.
  These rough development assets are now bundled for the debug Pack renderer; they do
  not yet meet the requested natural-anatomy and final-animation quality.
- Custom Metal skeletal renderer inside Mapbox 11.25.0. Uses double-precision
  geographic matrix composition, terrain elevation when supplied, and Mapbox's
  depth buffer. A synthetic extruded wall exercises depth occlusion.
- Debug app launch argument `--wolfy-map-prototype`. This bypasses normal routing
  for a synthetic map, not an authenticated campaign. Backgrounding stops its
  repaint loop. No production map or Home replacement is enabled.
- Fixed a prototype animation freeze by using the app's existing
  `DisplayLinkRecoveringMapView`. Phone diagnostic samples advanced from frame
  243 to 266 and animation sample 0 to 21; resulting images differ.
- Pure Swift five-stage rules, priority/coalescing state policy, inactivity
  postures, no-repeat pools, fix validation, stale/hidden boundaries, packet/jump
  rejection and feedback budgets. Tests cover these policies.
- Native debug-only More → Team → Live Pack roster and compact card, backed by
  a versioned permission-filtered snapshot. Send Howl uses a stable request ID.
  Snapshot failures and scope changes clear in-memory locations. An optional debug
  Mapbox Pack map now renders this roster; the full manager dashboard remains pending.
- Pending SQL: one-time user XP import, private profile/config/ledger tables,
  explicit sharing settings, validated presence RPC, protected raw presence reads,
  snapshot projection, and idempotent/rate-limited direct howls.
- Fresh disposable PostgreSQL 17 fixture tests pass for the above APIs, including
  cross-workspace denial, teammate visibility, membership revocation, stale fixes,
  paused sessions, direct-table denial and one-time import.
- Pending activity adapters now award saved session doors/conversations, field
  leads, appointments, verified sales and explicitly completed calendar follow-ups.
  Session door identities survive retries and pauses. An append-only ledger records
  compensating entries for undo, cancellation, deletion and sale reassignment;
  each fact retains its originally applied reward configuration. Daily reporting
  intervals freeze the timezone and personal door goal. Door milestones and daily
  goals reconcile when corrected activity crosses their thresholds.
- A private debug Your Wolfy screen shows lifetime progression, daily totals,
  current live session streak, recent applied rewards and server-backed preferences.
  Its follow-up list reads only the signed-in user's existing calendar; explicit
  completion and undo persist through an ownership-checked RPC. No customer data
  was added to Pack payloads. These views require the pending SQL and have only
  been build-verified, not exercised against hosted APIs on a phone.
- Disposable database tests additionally pass: 60-door reward totals, conversation
  deduplication, literal property matching, frozen day/goal/reward configuration,
  undo/redo, cascade deletion, repeated sale reassignment, follow-up completion
  retries/reversal, private snapshot import totals and denied client award access.
- Pack publication is now wired through `SharedLiveCanvassingService` using only
  existing accepted CLLocation values. A small versioned runtime RPC selects the
  server-flagged path; older deployments retain legacy publication. Movement is
  limited to five-second updates and stationary updates to thirty seconds. Actual
  fix time, accuracy, course, speed and fix-derived sequence are sent to the
  validated RPC. Separate heartbeats preserve fix time and coordinates; pausing
  or ending a persisted session clears precise presence immediately on the server.
- Existing map marker decoding now preserves heartbeat and GPS fix timestamps
  separately. It uses actual fix age for fading/removal and replaces visibility
  from refreshed snapshots. A standalone Swift test verifies old payload support,
  stale markers despite fresh heartbeats, and removal at 180 seconds.
- Offline session event projection now uses persisted timestamp/ID order instead
  of upload arrival order. Database tests cover late completion/conversation after
  undo and late undo before a newer completion. Cross-day reconciliation and
  concurrent-device integration still need broader validation.
- Campaign-scoped Pack statistics now derive from persisted session events,
  contacts, appointments and verified sales independently of the personal XP flag.
  They count unique campaign properties per reporting day, omit customer fields,
  return only scoped earned XP, and honor field-sales revenue visibility. A private
  source projection supports persisted session participant attribution; shared
  participant presence/XP compatibility still needs end-to-end validation.
- Native debug Pack Stats provides Today / This Week / This Month / Campaign,
  per-rep results, conversion, scoped earned XP, live session streaks, stage badges,
  and permitted revenue. Manager goal configuration leaves unset targets absent
  and freezes campaign reporting timezone after activity begins. It is accessible
  from Live Pack and teammate View Stats; integration into the main leaderboard
  remains pending. Currency formatting reuses the existing field-sales formatter.
- Transactional Pack claims cover 100/250/500/1,000 doors and configured daily
  goals, with no personal XP bonus. Claims survive corrections and goal edits
  without replay. Events include an applied target and synchronized start/window;
  the client exposes the current event phase for the future multiplayer renderer.
  Native banners prioritize/coalesce events, and return summaries exclude howls.
- Fresh database tests pass for statistics with personal XP disabled, timezone
  boundaries, goal authorization, revenue privacy, duplicate/corrected claims,
  synchronized event windows, summaries without replay, and two independent
  database connections crossing the same goal/milestone concurrently. No hosted
  APIs or device UI were exercised for these new stats/goals screens.
- Signed Debug device build passed. Prototype installed and launched on Daniel's
  iPhone 16 Pro (iOS 26.6.1). Captures in `art/wolfy-v2/` are actual device captures
  of synthetic test geometry, not evidence of live teammate activity.

## Latest implementation work

- Added a debug multi-character Mapbox Metal renderer with shared stage resources,
  instanced draws, per-character poses and triple-buffered GPU uploads. A pure Swift
  motion controller handles ordered fixes, bounded interpolation/extrapolation,
  stale fading, removal, culling and selected/local priority. Fifty-member policy
  tests pass for eight full plus eight simplified characters and remaining markers.
  Simplified characters currently reduce animation frequency, not mesh complexity.
- Added collision-aware first-name labels, a local YOU indicator, tap selection,
  background suspension, Reduce Motion handling and thermal/low-power budgets to
  the debug Pack map. Real campaign-map integration and property-label priority
  still need completion and visual verification.
- All five draft stage manifests pass binary hash/bounds/joint/animation validation.
  The main signed Debug build passes. An isolated `WolfyValidation` app builds and
  installs separately from the main app with fifty synthetic members. A console launch exposed a missing framework runtime search path in the isolated
  project generator; that packaging issue is being corrected. No new Pack GPU,
  frame time, memory, battery or live teammate result is verified by installation.
- Additive pending migrations now recognize existing joined session participants
  for presence, nonspatial roster, Send Howl and current-session statistics. Leaving,
  deleting or changing participation clears the old precise presence; host pause
  also clears participant presence. Authenticated-role database tests cover these
  paths, including direct raw-table denial after departure.
- Participant business activity is attributed to the rep rather than the host.
  Persisted event time is checked against the recorded joined/left interval, so
  eligible offline uploads can arrive after departure. Duplicate uploads do not
  repeat XP; undo can compensate previously earned activity after departure.
  A private interval history now preserves earlier participation across leave/rejoin
  and row deletion. Tests reject activity during the absence and prevent heartbeat
  edits from widening historical eligibility. Private and campaign projections
  apply the same post-departure undo, and both show joined-session live streaks.
  Existing history before migration is limited to the participant row retained by
  the legacy system; unavailable earlier join/leave windows cannot be reconstructed.

## Important deployment boundary

SQL is intentionally in `supabase/pending/wolfy-v2`, outside the automatic migration
folder. **Do not deploy these files as a finished feature.** Both flags default off.
While Pack is OFF, legacy presence visibility is preserved, except for explicit
sharing opt-outs. Enabling Pack requires fresh, permitted active-session fixes.
No hosted migrations, pushes, TestFlight releases or production deployments occurred.

The client uses a permission-checked five-second snapshot fallback. Private realtime
subscriptions, immediate revocation notifications and event acknowledgements are
not implemented. Resume summaries currently cover recent Pack goals/door milestones;
other achievement categories and per-user acknowledgement remain pending. Direct event-table reads remain denied.
The publisher is integrated behind the server flag, but has not been exercised
against a hosted campaign with multiple phones. Team locations therefore cannot
be advertised as verified end to end.

## Required remaining implementation

1. Finish the first renderer gate in the real campaign map: terrain fixtures,
   building depth correctness, hit testing, instrumentation and oldest-device budget.
2. Refine the pup anatomy/skin/foot contact; refine all five stage studies,
   complete every requested clip pool, add LODs and compressed animation/texture
   delivery, and produce turntables and full animation previews. Current art is a
   procedural prototype, not premium final character art.
3. Connect the behavior controller to accepted session GPS, safe walking geometry,
   turning/acceleration, next targets, inactivity/coaching and local event reactions.
4. Complete personal record claims, all remaining celebration tiers, broader
   correction/reassignment cases and end-to-end offline reconciliation. The pending
   adapters are fixture-tested but not deployed; no v2 reward rules are live.
   Verify real schemas and existing trigger interactions before promotion.
5. Replace Home/Den with the new assets and private lifetime progression; remove
   legacy storefront UI only when the replacement passes its gate. Connect the
   foreground feedback driver to confirmed events. Settings and status currently
   exist only through the debug Team entry.
6. Validate the integrated presence publisher and add private realtime subscriptions;
   finish production integration and verification of the debug multi-wolf renderer,
   interpolation, resource sharing, culling and labels; add meeting detection, team feedback, progress and event prioritization.
7. Integrate synchronized Pack Howl animation, campaign completion, competitive
   moments, assignments, cross-campaign manager aggregation and the main leaderboard.
   Profile the new statistics/event queries on production-sized fixtures before release.
8. Run real authenticated multi-device flows, 50-member performance tests and the
   two-hour matched field battery/GPS test. Then promote reviewed migrations and
   enable staged production flags. Do not claim these tests from simulator or
   synthetic-map evidence.

## Reproduce available checks

From the WolfGrid-IOS root:

```sh
swiftc WolfGrid/Features/WolfyV2/WolfyCompanionPolicy.swift scripts/test-wolfy-v2.swift -o /tmp/test-wolfy-v2
/tmp/test-wolfy-v2
python3 scripts/validate-wolfy-v2-assets.py
swiftc WolfGrid/Features/Map/Models/SharedLiveCanvassingModels.swift scripts/test-wolfy-presence-compat.swift -o /tmp/test-wolfy-presence-compat
/tmp/test-wolfy-presence-compat
bash supabase/tests/wolfy-v2/run.sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/wolfy-v2/scripts/build_prototype.py
```

The PostgreSQL runner starts a uniquely named local Docker container and removes it
on exit. Its fixture must never be applied to a hosted WolfGrid database. This tests
schema/authorization behavior, not hosted Supabase Realtime delivery.

Build log: `/tmp/wolfy-v2-build.log`; isolated DerivedData: `/tmp/wolfy-v2-build`.
Device screenshot data is saved by the debug entry into the app's Documents folder;
retrieve only its `wolfy-prototype-*` files with devicectl, not other app data.
