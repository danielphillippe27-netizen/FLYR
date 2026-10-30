# Campaign map editing

The hammer opens a map editor with Select, Move, Add, Undo, and More. The Select menu chooses addresses, buildings, parcels, or all items. Tap to toggle selection; multiple selections expose Remove directly. Moves operate on a single selected item. One finger drags that item; two fingers move the map. The map uses the exact Mapbox field geometry in edit mode and restores the normal renderer preference on exit. Automatic visit inference pauses during editing while GPS path recording continues. Existing sessions retain their saved membership/history; their coordinates and parcel completion shapes refresh from corrected field data.

## Corrections and preservation

Corrections are campaign overlays, stored separately from imported geometry and PMTiles. Removing a building or parcel hides it in that campaign and clears effective relationships. It does not delete source addresses, contacts, visits, or other campaign history. The older building/parcel removal menus use this same operation. Explicit legacy address/unit deletion outside this editor retains its existing semantics.

An address dropped into an unambiguous parcel links to that parcel. A single suitable building links automatically; multiple possible buildings open a choice. A drop directly into one footprint can resolve multiple buildings on the same parcel. Screen-scaled edge snapping is capped at three metres. Overlapping parcels remain ambiguous. Footprint tests check holes and boundary crossings. Intentional unlink flags prevent subsequent automatic matching from reconnecting an address unless the user deliberately moves/links it again.

Move linked items translates associated address points and buildings with the selected parcel/building. Address IDs remain unchanged. Townhome addresses retain their individual identities and parcel assignments. Group changes and relationship corrections form one undo command. Newly added homes use the existing creation queue; their undo hides the created address and fallback building.

## Persistence and sync

`CampaignMapEditStore` writes the journal atomically before publishing a committed edit. It scopes files by authenticated user, workspace, and campaign. Temporary drag previews are never persisted. The shared offline sync coordinator discovers pending journals after restart, including campaigns that are not reopened. Open maps refresh shared corrections periodically.

Each command has a UUID, expected revision, before-values, and a batch of overrides. `/api/campaigns/[campaignId]/map-edits` authenticates the user and checks campaign ownership/workspace membership. The `apply_campaign_map_edits` Postgres function locks the campaign edit state, applies the batch, records before-values, and increments its revision in one transaction. Duplicate retries return current state without applying twice. A stale unrelated change rebases; changes to the same item require an explicit choice. Undo is another ordered, durable command. It never drops an in-flight mutation.

Do not reinterpret old `delete_building` outbox entries: they retain their existing operation semantics. New editor removals use the separate correction journal.

## PMTiles and field behavior

PMTiles and exact geometry packages remain immutable. The renderer suppresses modified/removed stable IDs and draws only corrected features as GeoJSON, including parcels and labels. Undo removes overrides and restores the original tile IDs. Hit testing resolves full effective field geometry rather than clipped tile fragments. Selection survives source/style refreshes. Field cards, linked address lists, flyer coordinates, and parcel completion use effective corrections.

Saved corrections reapply over refreshed packages by stable identity. A missing source item does not create a phantom object; non-removal corrections with missing IDs are kept and flagged for review. If an exact tile index is unavailable but field shapes are loaded, the corrected GeoJSON snapshot renders instead. Original tiles are suppressed while saved corrections are being restored.

## Backend rollout

Apply `supabase/migrations/20261028180000_campaign_map_edit_overlays.sql` and deploy the new map-edits route before releasing the iOS app. The tables and RPC are service-role-only; mobile clients cannot bypass the route's campaign access check. No existing source rows need a backfill or rewrite. The app retains edits locally and reports sync availability if the endpoint is not yet deployed.

## Verification

The regression tests in `CampaignMapEditingTests` cover preservation, mixed selection, snapping, ambiguous links, explicit unlinks, linked moves, shape holes, invalid geometry, durable undo/reopen, account isolation, lost-response retries, revision conflicts, background recovery, and canonical tile render plans. `CanonicalTileVerificationView` also renders moves/removals over the real Bowmanville PMTiles fixture, reopens the journal, syncs through an isolated test transport, undoes both commands, and checks the restored tile hit. It is a DEBUG-only harness and performs no production edits.

Backend validation and authenticated request-flow tests:

```
cd backend-api-routes
./node_modules/.bin/tsx --test lib/services/__tests__/CampaignMapEdits.test.ts lib/services/__tests__/CampaignMapEditsAPI.test.ts
./node_modules/.bin/tsc --noEmit
```

Database transaction/permission tests run against an isolated Postgres engine using PGlite (`@electric-sql/pglite`, installed only in a test dependency directory):

```
WOLFGRID_TEST_PGLITE=/absolute/path/to/pglite/dist/index.js node scripts/test-campaign-map-edits-db.mjs
```

Build, test, and rendering evidence is saved under `TestArtifacts/map-edit-2026-10-28/`. The production migration and API were released on October 28, 2026. Twelve live integration checks passed on the staged build and again through `wolfgrid.app`, including exact source address/history preservation and fixture cleanup. Deployment: `dpl_DURhwaR36wvhM7uVnPK5s2A7Sos9`. A physical-phone field trial and App Store release have not been performed.

The owning production backend is `/Volumes/Samsung SSD/WolfGrid/Wolfgrid-WEB` (Vercel `flyrpro`, Supabase `kfnsnwqylsdsbgnwgxva`). The copied `backend-api-routes` folder and iOS root Supabase link point at different historical projects; do not use those links for production rollout. The additive route, helper, tests and migration are also saved in the owning web checkout so later releases retain them.

`scripts/test-map-edit-live.mjs` creates isolated, email-confirmed fixture accounts without sending email, exercises the live API, checks the source address remains byte-for-byte unchanged, then removes its fixtures. It reads the owning backend’s local configuration without logging credentials.
