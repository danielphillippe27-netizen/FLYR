# Android Campaign Creation, Map Bundle, And Display Guide

This is the Android handoff for matching the current iOS campaign creation and map-loading behavior one-to-one. The primary contract is now the canonical campaign map bundle:

```http
GET /api/campaigns/{campaignId}/map-bundle
Authorization: Bearer <supabase-access-token>
```

Android should use this endpoint as the first-class map payload. The older buildings, addresses, parcels, and roads endpoints are fallback/debug paths only.

Legacy import/closest-home flows are intentionally out of scope except where they share campaign metadata, visit status, or display behavior.

## Source Map

Use these files as the source of truth while building Android parity:

| Area | Files |
| --- | --- |
| Campaign creation UI and loading page | `FLYR/Feautures/Campaigns/Views/NewCampaignScreen.swift`, `FLYR/Feautures/Campaigns/Views/CampaignCreatingOverlayView.swift`, `FLYR/MainTabView.swift` |
| Provision progress persistence | `FLYR/Services/Notifications/CampaignProvisionMonitor.swift`, `FLYR/Shared/AppUIState.swift` |
| Campaign API wrapper | `FLYR/Feautures/Campaigns/CampaignsAPI.swift` |
| Map bundle client models/API | `FLYR/Features/Buildings/Services/BuildingLinkService.swift` |
| iOS map feature coordinator | `FLYR/Services/MapFeaturesService.swift` |
| iOS offline campaign cache | `FLYR/Offline/Repositories/CampaignRepository.swift`, `FLYR/Offline/OfflineMigrations.swift` |
| iOS Mapbox rendering | `FLYR/Features/Map/Views/CampaignMapView.swift`, `FLYR/Services/MapLayerManager.swift` |
| Backend map bundle route | `backend-api-routes/app/api/campaigns/[campaignId]/map-bundle/route.ts` |
| Backend map bundle builder | `backend-api-routes/lib/services/CampaignMapBundleService.ts` |
| Bundle DB/RPC contract | `supabase/migrations/20260529120000_canonical_campaign_map_bundles.sql`, `supabase/migrations/20260529124500_include_polished_cache_in_map_source_version.sql` |
| Auto-linking RPC | `supabase/migrations/20260526111000_create_auto_link_campaign_addresses.sql` |

Note the existing repo path typo: campaign files live under `Feautures`, not `Features`.

## End-To-End Lifecycle

Android should treat territory campaign creation as an asynchronous map-bundle-first workflow:

1. User draws a territory polygon.
2. App creates a draft campaign shell in Supabase.
3. App writes the territory boundary GeoJSON, region, and bbox to the campaign.
4. App calls `POST /api/campaigns/provision`.
5. App shows the full-screen campaign loading page and tracks background progress.
6. App polls campaign provision state until the campaign is map usable.
7. App fetches `GET /api/campaigns/{campaignId}/map-bundle`.
8. App atomically persists the returned bundle locally.
9. App renders buildings, addresses, parcels, roads, and links from that bundle.
10. On later opens, app draws from local cache first and refreshes the bundle in the background with the cached `asset_signature`.

The critical rule: Android should not send client-side address lists for map-created campaigns. The backend owns address discovery, building geometry, roads/parcels, and canonical linking after it receives the campaign polygon.

## Campaign Creation

### Draw Polygon

Android requirements:

- Store polygon points as latitude/longitude for UI drawing.
- When serializing to GeoJSON, convert each point to `[longitude, latitude]`.
- Close the ring by appending the first coordinate to the end if needed.
- Reject polygons with fewer than 3 unique points.
- Keep the polygon locally until shell creation, boundary upload, and provisioning have all started successfully.

GeoJSON shape:

```json
{
  "type": "Polygon",
  "coordinates": [
    [
      [-79.4010, 43.6510],
      [-79.4020, 43.6520],
      [-79.4000, 43.6530],
      [-79.4010, 43.6510]
    ]
  ]
}
```

### Create Campaign Shell

iOS creates the campaign shell directly through Supabase. Android can mirror that table insert or use an equivalent backend endpoint if one is introduced later.

For territory campaigns, create the shell with:

- `address_source = "map"`
- `address_target_count = 0`
- `addresses_json = []`
- user-entered name/details
- selected workspace/team context where applicable

Do not wait for addresses before creating the campaign shell. Address rows are produced during provisioning.

### Upload Boundary

Before provisioning, write the drawn territory to the campaign:

- `territory_boundary`: GeoJSON polygon
- `region` / seed query: inferred region code, uppercased when available
- bbox fields or equivalent boundary metadata used by the backend

If boundary upload fails, keep the draft campaign and allow retry from the same polygon. Do not call provisioning without a saved boundary.

## Campaign Loading Page

iOS now shows a full-screen campaign creation overlay while provisioning and map preparation run. Android should mirror this page, not a small inline spinner.

### UI Contract

Show:

- Full-screen background that matches light/dark mode.
- FLYR loading animation or Android-equivalent brand animation.
- Title: `Creating campaign`.
- Large percent text.
- Activity text.
- Destructive `Cancel` button while progress is below 100.
- Footer text: `You can exit the app and come back when it's ready.`
- Error text when cancel/provision fails.
- Ready reveal when progress reaches 100 and a polygon is available.

The Cancel button:

- Starts disabled/loading state with label `Cancelling`.
- Cancels local campaign creation/provisioning tasks.
- If no campaign ID exists yet, dismisses the creation flow.
- If a campaign ID exists, deletes the campaign row from Supabase, removes it from local stores, clears tracked provision state, clears selected map state if needed, then dismisses.
- If delete fails, stays on the loading page and shows `Could not cancel campaign setup: <error>`.

### Persisted Background Progress

Android should persist the latest in-progress campaign setup so users can leave the app and return:

- `campaignId`
- `campaignName`
- badge/state enum
- user-facing status text
- progress percent

Resume behavior:

- On app start/foreground, refresh the latest provision state.
- If the tracked campaign is still running, re-open the campaign creation/loading screen.
- If it is ready, let the ready reveal or normal campaign open flow finish.
- If it failed, show needs-attention state with retry/error messaging.
- Clear the tracked state after cancel, successful dismissal, or when the user handles the failure.

### Progress Mapping

Mirror iOS progress:

| Backend phase/status | Progress | Activity text |
| --- | ---: | --- |
| `created` | 5 | `Creating campaign` |
| `pending` with no phase | 8 | `Creating campaign` |
| `source_probed` | 18 | `Finding homes` |
| `addresses_loading` | 35 | `Saving addresses` |
| `addresses_ready` | 50 | `Preparing map` |
| `map_ready` | 68 | `Preparing map` |
| `optimizing` | 82 | `Finalizing map` |
| `linked` | 95 | `Finalizing map` |
| `optimized` or ready/map usable | 100 | `Campaign is ready` |
| `failed` | no percent | `Setup needs attention` |

Clamp progress to `0..100` and never animate backwards unless restarting a brand-new campaign.

## Provisioning

Provision request:

```http
POST /api/campaigns/provision
Authorization: Bearer <supabase-access-token>
Content-Type: application/json

{
  "campaign_id": "campaign-uuid"
}
```

iOS supports accepted/background provisioning. Android should treat all of these as valid:

- immediate `ready`
- `accepted: true`
- `provision_status: "pending"`
- HTTP success with post-processing deferred

After the request succeeds, poll campaign state from Supabase:

```sql
select id,
       provision_status,
       provision_source,
       provision_phase,
       provisioned_at,
       addresses_ready_at,
       map_ready_at,
       optimized_at,
       snapshot_bucket,
       snapshot_prefix,
       snapshot_buildings_url,
       snapshot_roads_url,
       address_source,
       coverage_score,
       data_quality,
       standard_mode_recommended,
       data_quality_reason,
       provision_timings,
       provision_error,
       provision_message
from campaigns
where id = :campaignId
```

Map usable rule:

- `provision_status = "ready"` and phase is map usable opens the campaign.
- `linking_failed` can still open in standard/address mode when the campaign is otherwise ready.
- `failed` stops polling and shows backend `provision_message` or `provision_error`.

Recommended polling interval: 2 seconds while the loading screen is visible, with a longer backoff in background if Android needs to conserve work.

## Canonical Map Bundle

### Request

```http
GET /api/campaigns/{campaignId}/map-bundle
Authorization: Bearer <supabase-access-token>
```

If Android has a cached bundle with an `asset_signature`, pass it:

```http
GET /api/campaigns/{campaignId}/map-bundle?signature={cachedAssetSignature}
Authorization: Bearer <supabase-access-token>
```

Auth/access behavior:

- `401`: refresh Supabase session or route to sign-in.
- `403`: show no-access state and do not mutate local campaign data.
- `500`: keep usable local cache if present; otherwise show map-data-not-ready/retry.

The backend sends no-store JSON headers and may include `Server-Timing` for debugging.

### Response Statuses

| Status | Android behavior |
| --- | --- |
| `200` | Decode the bundle, atomically replace the local render cache, apply to map if this campaign is still active. |
| `304` | Keep the local cached bundle exactly as-is and draw from it. Record local validation time if useful. |
| `401` | Refresh auth or sign in. Do not clear cache. |
| `403` | Show forbidden/no-access. Do not clear cache automatically. |
| `500`/network error | Use cached bundle if available; otherwise show retry/error. |

The `304` path is valid only when Android passed a signature. The body is empty.

### Response Shape

The `200` response body is:

```json
{
  "campaign_id": "campaign-uuid",
  "asset_signature": "campaign:bundle:signature",
  "source_version": "source-version-hash",
  "display_mode_hint": "buildings",
  "links_status": "fresh",
  "addresses": { "type": "FeatureCollection", "features": [] },
  "buildings": { "type": "FeatureCollection", "features": [] },
  "parcels": { "type": "FeatureCollection", "features": [] },
  "roads": { "type": "FeatureCollection", "features": [] },
  "links": [],
  "counts": {
    "addresses": 0,
    "buildings": 0,
    "parcels": 0,
    "roads": 0,
    "links": 0
  },
  "layer_fetched_at": {
    "addresses": "2026-05-29T16:00:00.000Z",
    "buildings": "2026-05-29T16:00:00.000Z",
    "parcels": "2026-05-29T16:00:00.000Z",
    "roads": "2026-05-29T16:00:00.000Z"
  },
  "built_at": "2026-05-29T16:00:00.000Z",
  "expires_at": "2026-05-29T16:15:00.000Z",
  "updated_at": "2026-05-29T16:00:01.000Z"
}
```

Required top-level fields Android must model:

- `campaign_id`
- `asset_signature`
- `source_version`
- `display_mode_hint`
- `links_status`
- `addresses`
- `buildings`
- `parcels`
- `roads`
- `links`
- `counts`
- `layer_fetched_at`
- `built_at`
- `expires_at`
- `updated_at`

Enums:

| Field | Values | Meaning |
| --- | --- | --- |
| `display_mode_hint` | `buildings`, `addresses` | Server recommendation for initial display mode. |
| `links_status` | `fresh` | Backend refreshed links successfully. Android should not run client linking. |
| `links_status` | `stale_reused` | Backend reused strict previous links after refresh budget expired. Render them and refresh later. |
| `links_status` | `client_fallback_required` | Backend could not provide links. Android may run client linking if implemented. |

### Link Shape

Bundle links use this shape:

```json
{
  "id": "optional-link-id",
  "building_id": "public-building-id",
  "address_id": "campaign-address-id",
  "match_type": "containment_verified",
  "confidence": 1.0,
  "distance_meters": 0.0
}
```

Android should treat `building_id` as the public/canonical building identifier used in the returned building features. Use `address_id` to update matching address features.

When applying links:

- Keep the highest-confidence link per address.
- Add `building_gers_id` to linked address properties.
- Add `address_ids`, `address_count`, and `is_linked` to linked building properties where useful for rendering/details.
- Preserve manual local links over generated/bundle links for the same address.

### Backend Bundle Freshness

The backend rebuilds a bundle when:

- source version changed
- current bundle expired
- map bundle cache version changed
- parcel backfill is needed
- polished building cache has newer/more complete features

Layer TTLs:

- addresses: 15 minutes
- buildings/parcels/roads: 24 hours

Android does not need to reimplement this freshness logic. It should send the cached `asset_signature` and trust `200`/`304`.

### Local Cache Contract

Android cache must be render-ready, not just raw fragments.

Store:

- campaign ID
- `asset_signature`
- `source_version`
- `display_mode_hint`
- `links_status`
- `counts`
- `layer_fetched_at`
- `built_at`
- `expires_at`
- `updated_at`
- building GeoJSON features
- address GeoJSON features
- parcel GeoJSON features
- road GeoJSON features
- bundle links
- manual links, if Android supports manual link editing
- client-generated links, if Android creates them

Atomic replace behavior for a `200` bundle:

1. Begin DB transaction.
2. Read and protect manual links for this campaign.
3. Delete old generated bundle/cache records for buildings, addresses, parcels, roads, and non-manual generated links.
4. Insert bundle buildings, addresses, parcels, and roads.
5. Insert bundle links, skipping any address protected by a manual link.
6. Re-apply manual links to address/building render properties.
7. Save bundle metadata.
8. Commit.

Do not partially replace only one layer. A half-updated map bundle can desync buildings, addresses, and links.

Cache-first load behavior:

1. If a cached bundle exists, draw it immediately.
2. If online, call `/map-bundle?signature=<cached asset_signature>` in the background.
3. If response is `304`, keep the existing local bundle.
4. If response is `200`, atomically replace cache and redraw.
5. If offline and cache exists, open from cache.
6. If offline and no cache exists, block with a clear offline-cache-missing reason.

## Map Rendering

Android should render from the canonical bundle first.

Primary render order:

1. `buildings` FeatureCollection
2. `addresses` FeatureCollection
3. `parcels` FeatureCollection
4. `roads` FeatureCollection
5. `links` applied to local feature state/properties
6. visit/status/selected feature state

### Display Modes

iOS has two campaign display modes:

- building mode
- address mode

Use `display_mode_hint` to choose the initial mode:

- `buildings`: show building polygons/extrusions when more than one renderable building exists.
- `addresses`: show address markers/proxies prominently and keep parcels/addresses visible across zoom levels.

Rules:

- If `display_mode_hint = "addresses"`, start in address mode.
- If no renderable building features exist but addresses do, render address mode instead of a blank map.
- If building mode is active, address layers may be hidden unless edit/linking/session UX needs them.
- If address mode is active, keep addresses and parcels visible across the useful camera range.

### Layers

Android layer names do not need to match iOS, but responsibilities should.

| Layer responsibility | iOS source/layer concept |
| --- | --- |
| Building GeoJSON source | `buildings-source` |
| Building extrusion/fill | `buildings-extrusion` |
| Selected building overlay | selected building/glow layers |
| Townhome/multi-unit overlay | townhome overlay layers |
| Address point/proxy source | `campaign-address-points` |
| Address point extrusion/fill | `campaign-address-points-extrusion` |
| Selected address overlay | `campaign-address-points-selected-extrusion` |
| Address number labels | address numbers source/layer |
| Roads source/layer | `roads-source`, `roads-line` |
| Parcels source/layers | parcel fill/line/selected layers |

Road overlay note: iOS loads campaign roads into the source but currently hides the extra visual overlay on the main campaign map so the base map's native road styling stays clean. Android can do the same: keep road data available for GPS/session logic without forcing a visible overlay.

### Feature Properties To Preserve

Building features may include:

```json
{
  "id": "building-row-or-public-id",
  "building_id": "building-row-id",
  "gers_id": "public-building-id",
  "public_building_id": "public-building-id",
  "canonical_building_id": "public-building-id",
  "address_id": "address-id",
  "address_ids": ["address-id-1", "address-id-2"],
  "address_count": 2,
  "units_count": 2,
  "is_linked": true,
  "status": "not_visited",
  "height": 9,
  "height_m": 9,
  "min_height": 0,
  "source": "silver"
}
```

Address features may include:

```json
{
  "id": "address-id",
  "address_id": "address-id",
  "formatted_address": "123 Main St, Toronto, ON",
  "address_text": "123 Main St",
  "house": "123",
  "street": "Main St",
  "city": "Toronto",
  "postal_code": "M5V 2T6",
  "longitude": -79.4010,
  "latitude": 43.6510,
  "building_gers_id": "public-building-id",
  "status": "not_visited",
  "scans": 0
}
```

Renderable building geometries:

- `Polygon`
- `MultiPolygon`

Filter out tiny non-manual building polygons if the Android map becomes noisy. iOS filters very small linkable footprints before display.

### Status Colors And Feature State

Android should preserve the same display meanings:

| State | Display intent |
| --- | --- |
| QR scanned | Purple/highest priority. |
| Hot lead / lead / appointment / future seller | Gold. |
| Visited | Green. |
| Default / not visited | Red. |
| Orphan/unlinked | Gray or subdued. |
| Selected/highlighted | Selected overlay or feature-state style. |

Feature state updates should affect buildings, addresses, parcels, and future vector/PMTiles layers if Android adds them later.

## Client Linking

Android should not run client linking when `links_status` is `fresh` or `stale_reused` and the returned features already contain linked address identity.

Run client linking only if:

- `links_status = "client_fallback_required"`, or
- the cached bundle has buildings and addresses but no linked address identity, or
- Android is in a manual repair/edit flow.

If Android implements client linking:

- Keep generated links separate from manual links.
- Do not overwrite manual links.
- Publish generated links to the backend client-links endpoint if parity with iOS client fallback is required.
- Refresh `/map-bundle` after publishing so future clients hydrate from canonical state.

For initial parity, rendering bundle links correctly is more important than implementing a full Android client linker.

## Legacy Fallback And Debug Endpoints

These endpoints still exist and are useful for debugging, partial fallback, or client-fallback repair. They are not the primary Android map load path.

### Buildings Debug/Fallback

```http
GET /api/campaigns/{campaignId}/buildings
Authorization: Bearer <supabase-access-token>
```

Optional retry:

```http
GET /api/campaigns/{campaignId}/buildings?cache=bypass
Authorization: Bearer <supabase-access-token>
```

Use only when:

- no local bundle exists,
- `/map-bundle` failed online,
- Android needs a temporary visual fallback,
- or debugging backend building output.

### Addresses Debug/Fallback

```http
GET /api/campaigns/{campaignId}/addresses
Authorization: Bearer <supabase-access-token>
```

Use only when bundle addresses are missing and Android needs an address-only fallback.

### Parcels Debug/Fallback

```http
GET /api/campaigns/{campaignId}/parcels
Authorization: Bearer <supabase-access-token>
```

Use only when bundle parcels are missing and parcel display/debugging is needed.

### Roads Debug/Fallback

Roads are included in the map bundle. If Android has an existing campaign road service, it can still fetch roads separately for GPS/session recovery, but campaign map rendering should prefer `bundle.roads`.

### Diamond Manifest / PMTiles

```http
GET /api/campaigns/{campaignId}/diamond-manifest
Authorization: Bearer <supabase-access-token>
```

Android can add PMTiles/vector rendering later. For parity with the current iOS flow, map-bundle GeoJSON is the required path. If a Diamond manifest says buildings render as `map_bundle`, Android must use the canonical bundle buildings.

## Session Start And Offline Gating

Online gating:

- Fetch campaign session gate metadata.
- If `provision_status = "failed"`, block with retry/support messaging.
- If `provision_status != "ready"`, block with `Campaign is still provisioning`.
- If ready, open and load bundle/cache.

Offline gating:

- If cached map bundle exists, allow session start.
- If explicit offline download state says ready, allow session start.
- Otherwise block with: `This campaign is not stored on this device yet. Reconnect for a moment so FLYR can prepare the area automatically, then try again.`

Do not mark a failed/empty online provision as successful just to allow offline mode.

## Error Handling And Edge Cases

| State | Android behavior |
| --- | --- |
| Polygon has fewer than 3 unique points | Keep user in drawing flow and show validation. |
| Campaign shell create fails | Do not upload boundary or provision; allow retry. |
| Boundary upload fails | Keep campaign draft and polygon; allow retry. |
| Provision returns accepted/pending | Show loading page, persist tracking, poll state. |
| Provision stays pending | Keep polling while visible; resume after foreground/reopen. |
| Provision failed | Stop polling, show backend message/error, keep retry path. |
| Unsupported region `422` | Show unsupported region message; do not fabricate local data. |
| First online bundle load `200` | Persist atomically, render bundle. |
| Cached first draw | Render local bundle immediately before network refresh. |
| Bundle `304` | Keep local bundle; do not clear or rewrite features. |
| Stale bundle | Draw local data, refresh `/map-bundle` in background. |
| `client_fallback_required` | Render available data, optionally run Android client linker. |
| Bundle has no buildings but has addresses | Start address mode and render address proxies. |
| Offline with cache | Open cached bundle. |
| Offline without cache | Block session with clear explanation. |
| Cancel before campaign ID | Cancel local tasks and dismiss creation flow. |
| Cancel after campaign ID | Delete campaign, remove local store/tracked state, dismiss. |
| Cancel delete failure | Stay on loading page and show cancel error. |
| Ready reveal | On 100 percent, reveal campaign map/territory then continue to the new campaign. |
| Auth `401` | Refresh session or route to sign-in without corrupting cache. |
| Access `403` | Show no-access; do not mutate local campaign. |
| Manual link exists | Bundle/client-generated links do not overwrite it. |

## Android Implementation Checklist

Creation/loading:

- Implement polygon drawing, close-ring behavior, and validation.
- Create campaign shell with map address source and empty address list.
- Upload boundary, region, and bbox before provisioning.
- POST `/api/campaigns/provision`.
- Show the full-screen loading page with progress/activity text.
- Persist tracked background provisioning state.
- Implement destructive Cancel before and after campaign ID exists.
- Poll provision state until map usable or failed.
- Trigger ready reveal at 100 percent.

Map bundle:

- Normalize backend API base URL from config.
- Attach Supabase bearer token to every backend request.
- Fetch `/api/campaigns/{id}/map-bundle` after provision is map usable.
- Pass `?signature=<asset_signature>` for cached refreshes.
- Handle `200`, `304`, `401`, `403`, network failure, and server failure.
- Persist `200` bundles atomically.
- Draw cached bundle first on repeat opens.
- Respect `expires_at` as local staleness metadata, but trust server `304` when validating.

Display:

- Render bundle buildings, addresses, parcels, and roads.
- Apply bundle links to feature state/properties.
- Use `display_mode_hint` for initial building/address mode.
- Avoid blank maps by falling back to address mode when buildings are unavailable.
- Apply status colors and selected/highlighted feature state.
- Keep road data available even if visual road overlay is hidden.

Linking/offline:

- Prefer backend bundle links.
- Preserve manual links over generated links.
- Run client linking only for `client_fallback_required` or explicit repair flows.
- Save render-ready campaign bundles for offline use.
- Allow offline sessions only when a usable cached bundle/download exists.

## Test Matrix

| Scenario | Expected result |
| --- | --- |
| Polygon campaign happy path | Shell create succeeds, boundary uploads, provision reaches map usable, `/map-bundle` returns `200`, bundle renders. |
| Async provision | Loading page persists progress and resumes after leaving/reopening app. |
| Immediate provision ready | Android skips unnecessary waiting and fetches map bundle. |
| First online bundle load | `200` bundle is atomically cached and rendered. |
| Cached first draw | Cached bundle renders before network refresh. |
| Bundle `304` | Android keeps local cache unchanged and continues rendering. |
| Stale bundle refresh | Android draws stale cache, fetches bundle, replaces cache on `200`. |
| `client_fallback_required` | Android renders available bundle and runs/link-repair fallback only if implemented. |
| Offline after prior successful load | Android opens cached map bundle. |
| Offline before map cache exists | Android blocks session with clear offline-cache-missing message. |
| Cancel before campaign ID | Local tasks cancel and creation screen dismisses. |
| Cancel after campaign ID | Campaign deletes, local/tracked state clears, screen dismisses. |
| Cancel delete failure | Loading page remains visible and shows cancel error. |
| Provision failed | Android shows backend message/error and retry path. |
| Ready reveal | Progress hits 100, reveal runs, then app opens/returns to new campaign. |
| Unsupported region | Android shows unsupported region error and does not fabricate map data. |
| Auth expired | Android refreshes session or routes to sign-in without corrupting cached bundle. |
| Workspace shared campaign | Android respects backend access and displays if authorized. |
| Manual link exists | Auto/client-generated links do not overwrite it. |
| Visit/status update | Building/address/parcel colors update for visited, QR scanned, lead, appointment, selected. |

## Minimal Android Pseudocode

```kotlin
suspend fun createPolygonCampaign(input: CampaignInput, polygon: List<LatLng>): Campaign {
    require(uniquePointCount(polygon) >= 3)

    val region = inferOrSelectRegion(polygon)?.uppercase()
    val boundary = polygon.toClosedGeoJsonLonLat()
    val bbox = boundary.computeBbox()

    val campaign = campaignRepository.createShell(
        name = input.name.ifBlank { "Untitled Campaign" },
        description = input.description,
        type = input.type,
        addressSource = "map",
        addressTargetCount = 0,
        seedQuery = region,
        addressesJson = emptyList(),
        workspaceId = input.workspaceId
    )

    provisionTracker.track(
        campaignId = campaign.id,
        campaignName = campaign.name,
        progressPercent = 5,
        activityText = "Creating campaign"
    )

    campaignRepository.updateTerritoryBoundary(
        campaignId = campaign.id,
        territoryBoundary = boundary,
        region = region,
        bbox = bbox
    )

    backend.provisionCampaign(campaign.id)

    val state = campaignRepository.pollProvisionUntilMapUsable(
        campaignId = campaign.id,
        intervalSeconds = 2,
        onProgress = { provisionTracker.update(it.toAndroidProgress()) }
    )

    if (state.isFailed) {
        throw CampaignProvisionException(state.messageOrError)
    }

    val bundle = backend.fetchMapBundle(
        campaignId = campaign.id,
        cachedSignature = null
    )

    mapBundleCache.replaceAtomically(
        campaignId = campaign.id,
        bundle = bundle,
        preserveManualLinks = true
    )

    provisionTracker.updateReady(campaign.id)
    return campaignRepository.refreshCampaign(campaign.id)
}

suspend fun openCampaignMap(campaignId: UUID): CampaignMapBundle {
    val cached = mapBundleCache.read(campaignId)

    if (cached != null) {
        mapRenderer.render(cached)
        if (!network.isOnline()) return cached
    } else if (!network.isOnline()) {
        throw OfflineCampaignNotCachedException()
    }

    val response = backend.fetchMapBundleResponse(
        campaignId = campaignId,
        cachedSignature = cached?.assetSignature
    )

    return when (response) {
        is BundleResponse.NotModified -> cached ?: throw MissingBundleAfter304Exception()
        is BundleResponse.Bundle200 -> {
            mapBundleCache.replaceAtomically(
                campaignId = campaignId,
                bundle = response.bundle,
                preserveManualLinks = true
            )
            mapRenderer.render(response.bundle)
            response.bundle
        }
    }
}

suspend fun cancelCampaignCreation(activeCampaignId: UUID?) {
    campaignCreationJob?.cancel()
    provisionJob?.cancel()

    if (activeCampaignId == null) {
        provisionTracker.clear()
        navigation.dismissCreation()
        return
    }

    try {
        campaignRepository.deleteCampaign(activeCampaignId)
        localCampaignStore.remove(activeCampaignId)
        mapSelection.clearIfSelected(activeCampaignId)
        provisionTracker.clear(activeCampaignId)
        navigation.dismissCreation()
    } catch (error: Throwable) {
        loadingUi.showCancelError("Could not cancel campaign setup: ${error.message}")
    }
}
```

## Final Android Parity Rule

For first parity, Android should behave like current iOS:

- Territory polygon is the creation input.
- Supabase stores the campaign shell and provision metadata.
- Backend provisioning creates addresses, buildings, roads, parcels, snapshots, and links.
- Android shows the campaign creation loading page with cancellable background provisioning.
- Android renders and caches `GET /api/campaigns/{campaignId}/map-bundle` first.
- Legacy per-layer endpoints are fallback/debug tools, not the normal map path.
- Offline sessions depend on a previously cached render-ready campaign map bundle.
