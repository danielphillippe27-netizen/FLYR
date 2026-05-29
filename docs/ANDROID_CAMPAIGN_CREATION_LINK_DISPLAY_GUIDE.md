# Android Campaign Creation, Linking, And Display Guide

This guide explains the current iOS and backend campaign lifecycle so Android can implement the same behavior. It focuses on territory-drawn campaigns: create a draft campaign shell, attach a polygon boundary, let the backend provision addresses/buildings, then fetch and render map data.

Legacy import/closest-home flows are intentionally out of scope except where they share models or display behavior.

## Source Map

Use these files as the source of truth while building Android parity:

| Area | Files |
| --- | --- |
| Campaign creation UI | `FLYR/Feautures/Campaigns/Views/NewCampaignScreen.swift`, `FLYR/Feautures/Campaigns/Views/MapDrawingView.swift` |
| Create payload and campaign models | `FLYR/Feautures/Campaigns/API/CampaignCreatePayloadV2.swift`, `FLYR/Feautures/Campaigns/Models/CampaignV2.swift` |
| iOS campaign API wrapper | `FLYR/Feautures/Campaigns/CampaignsAPI.swift` |
| iOS create hook | `FLYR/Feautures/Campaigns/Hooks/UseCreateCampaign.swift` |
| Backend provisioning | `backend-api-routes/app/api/campaigns/provision/route.ts` |
| Provision data providers | `backend-api-routes/lib/services/BedrockProvisionService.ts` |
| Stable address/building linker | `backend-api-routes/lib/services/StableLinkerService.ts` |
| Backend building endpoint | `backend-api-routes/app/api/campaigns/[campaignId]/buildings/route.ts` |
| Backend address endpoint | `backend-api-routes/app/api/campaigns/[campaignId]/addresses/route.ts` |
| Diamond manifest endpoint | `backend-api-routes/app/api/campaigns/[campaignId]/diamond-manifest/route.ts` |
| Client-generated link endpoint | `backend-api-routes/app/api/campaigns/[campaignId]/client-links/route.ts` |
| iOS building/address API client | `FLYR/Features/Buildings/Services/BuildingLinkService.swift` |
| iOS map feature coordinator | `FLYR/Services/MapFeaturesService.swift` |
| iOS Mapbox layer manager | `FLYR/Services/MapLayerManager.swift` |
| iOS campaign map screen | `FLYR/Features/Map/Views/CampaignMapView.swift` |
| iOS offline campaign cache | `FLYR/Offline/Repositories/CampaignRepository.swift` |

Note the existing repo path typo: campaign files live under `Feautures`, not `Features`.

## End-To-End Lifecycle

Android should treat campaign creation as a staged asynchronous workflow:

1. User draws a territory polygon.
2. App creates a draft campaign shell in Supabase.
3. App uploads the territory boundary GeoJSON to the campaign.
4. App calls the backend provision endpoint.
5. Backend resolves addresses and building geometry, writes snapshots, and links addresses to buildings.
6. App polls campaign provision state until the map is usable.
7. App fetches building and address GeoJSON.
8. App renders buildings, addresses, labels, roads, parcels, and selected/highlight state.
9. App caches map bundles for offline sessions.

The critical rule: Android should not send client-side address lists for map-created campaigns. The current backend provisioner owns address and building discovery after receiving the campaign polygon.

## Campaign Creation Flow

### 1. Draw Polygon

iOS implementation:

- `MapDrawingView.swift`
  - Tapping the map appends polygon vertices.
  - Tapping near the first vertex closes the polygon.
  - Finishing the polygon ensures the ring is closed before confirming.
- `NewCampaignScreen.swift`
  - Receives the drawn polygon.
  - Requires at least 3 unique vertices.
  - Converts the polygon into GeoJSON before backend provisioning.

Android requirements:

- Store polygon points as latitude/longitude for UI drawing.
- When serializing to GeoJSON, convert each point to `[longitude, latitude]`.
- Close the ring by appending the first coordinate to the end if needed.
- Reject polygons with fewer than 3 unique points.
- Keep the polygon available locally until the boundary upload and provision call complete.

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

### 2. Create Campaign Shell

iOS source:

- `CampaignCreatePayloadV2.swift`
- `UseCreateCampaign.swift`
- `CampaignsAPI.swift`
- `NewCampaignScreen.swift`

The current iOS flow creates a draft campaign shell before provisioning. The shell is inserted into the `campaigns` table with status `draft` and no addresses. Address rows arrive later from backend provisioning.

Important create payload fields:

| Field | Meaning |
| --- | --- |
| `name` | Initial name. iOS uses `Untitled Campaign` until details are saved. |
| `description` | Optional campaign description. |
| `type` | Optional campaign type, stored as a database enum/string. |
| `addressSource` | For map-created campaigns, use `map`. |
| `addressTargetCount` | Currently `0` for map-created campaigns because backend provisioning finds addresses. |
| `seedQuery` | Region code or inferred region hint. |
| `seedLon`, `seedLat` | Optional; current territory-first flow does not rely on them. |
| `addressesJSON` | Present for compatibility, but ignored for backend-provisioned map campaigns. Send an empty list. |
| `workspaceId` | Required when campaign belongs to a workspace. |

Android create request model should match:

```json
{
  "name": "Untitled Campaign",
  "description": "",
  "type": "seller",
  "addressSource": "map",
  "addressTargetCount": 0,
  "seedQuery": "CA",
  "seedLon": null,
  "seedLat": null,
  "tags": [],
  "addressesJSON": [],
  "workspaceId": "workspace-uuid"
}
```

iOS currently creates this shell directly through Supabase in `CampaignsAPI.createV2`. Android can either mirror that Supabase insert or use an equivalent backend endpoint if one is introduced later. For parity today, read `CampaignsAPI.createV2` as the table contract.

Shell defaults to preserve:

- `status`: `draft`
- `address_source`: `map`
- `scans`: `0`
- `conversions`: `0`
- `total_flyers`: `0`
- campaign address list: empty

### 3. Save Details

iOS lets the user rename and type the campaign after the shell exists. The details update is handled by `CampaignsAPI.updateCampaignDetails` and writes:

- `name`
- `title`
- `type`

Android should support updating these fields independently from provisioning. Do not block provisioning on the details screen if the shell and polygon are already available.

### 4. Upload Territory Boundary

iOS source: `CampaignsAPI.updateTerritoryBoundary`.

Before provisioning, Android must write the drawn polygon to the campaign:

```json
{
  "territory_boundary": {
    "type": "Polygon",
    "coordinates": [
      [
        [-79.4010, 43.6510],
        [-79.4020, 43.6520],
        [-79.4000, 43.6530],
        [-79.4010, 43.6510]
      ]
    ]
  },
  "region": "CA",
  "bbox": [-79.4020, 43.6510, -79.4000, 43.6530]
}
```

Behavior to mirror:

- Decode/validate GeoJSON polygon before writing it.
- Normalize `region` to uppercase.
- Store the computed bounding box.
- Do not store placeholder strings like `Polygon (12 points)` as the region.

### 5. Start Backend Provisioning

Backend source: `backend-api-routes/app/api/campaigns/provision/route.ts`.

Endpoint:

```http
POST /api/campaigns/provision
Authorization: Bearer <supabase-access-token>
Content-Type: application/json
```

Minimum body:

```json
{
  "campaign_id": "campaign-uuid"
}
```

Optional body fields supported by the backend:

```json
{
  "campaign_id": "campaign-uuid",
  "wait_for_linker": false,
  "wait_for_postprocess": false,
  "require_linked_homes": false
}
```

iOS calls provisioning with `waitUntilReady: false`, which allows the backend to accept the job and continue in the background. Android should support both immediate ready responses and async accepted/pending responses.

Expected accepted/pending response shape:

```json
{
  "success": true,
  "accepted": true,
  "provision_status": "pending",
  "provision_phase": "created",
  "message": "Provisioning started"
}
```

Expected ready-ish response fields may include:

```json
{
  "success": true,
  "addresses_saved": 1240,
  "buildings_saved": 980,
  "roads_saved": 42,
  "provision_status": "ready",
  "provision_phase": "linked",
  "provision_source": "diamond",
  "map_ready": true,
  "optimized": true,
  "postprocess_deferred": false,
  "linker_path": "in_memory",
  "building_link_confidence": 86,
  "map_mode": "hybrid",
  "coverage_score": 0.92,
  "data_quality": "good",
  "standard_mode_recommended": false
}
```

Unsupported region or invalid campaign responses may return `422` with an error body. Android should surface a retry/error state and not create fake local map data.

## Provisioning Internals Android Needs To Understand

The backend performs the heavy work in `app/api/campaigns/provision/route.ts`.

High-level worker stages:

1. Authenticate the Supabase user.
2. Verify campaign owner or workspace access.
3. Require `territory_boundary`.
4. Reset campaign provision fields to pending/created.
5. Resolve the campaign source:
   - Try Diamond when supported and address quality is acceptable.
   - Fall back to Bedrock country providers when Diamond is unavailable or unsuitable.
6. Insert campaign addresses through `add_campaign_addresses` RPC or fallback upserts.
7. Materialize building geometry into `campaign_polished_building_features`.
8. Write `campaign_snapshots` metadata and artifact URLs.
9. Materialize parcels where supported.
10. Auto-link addresses to buildings/parcels.
11. Update campaign status, phase, map mode, quality, and confidence fields.
12. Optionally send campaign-ready notification.

Provider source names are defined in `BedrockProvisionService.ts`:

- `bedrock_nz`
- `bedrock_au`
- `bedrock_ca`
- `bedrock_us`
- `bedrock_za`
- `bedrock_uk`

Diamond source is represented as:

- `diamond`

## Provision State And Map Readiness

iOS source:

- `CampaignsAPI.fetchProvisionState`
- `CampaignsAPI.waitForProvisionReady`
- `CampaignV2.CampaignProvisionStatus`
- `CampaignV2.CampaignProvisionPhase`
- `NewCampaignScreen.isMapUsable`

Campaign provision status values:

| Status | Meaning |
| --- | --- |
| `pending` | Provisioning is in progress. |
| `ready` | Provisioning produced usable campaign data. |
| `failed` | Provisioning failed. |

The decoder also treats legacy `complete` and `completed` values as `ready`.

Important provision phases:

| Phase | Meaning |
| --- | --- |
| `created` | Job accepted/reset. |
| `source_probed` | Backend chose/probed a data source. |
| `addresses_loading` | Addresses are being inserted. |
| `addresses_ready` | Address rows are available. |
| `map_ready` | Map data is available. |
| `optimizing` | Post-processing/linking is still improving data. |
| `linking_failed` | Map can still be usable, but building links are incomplete. |
| `linked` | Address/building links completed. |
| `optimized` | Fully optimized map artifacts/links are ready. |
| `failed` | Provision failed. |

Map usability rule:

```text
provision_status == "ready"
AND provision_phase is null or one of:
  - map_ready
  - linking_failed
  - linked
  - optimized
```

Android should keep polling while status is `pending`. Once the campaign is map usable, fetch buildings and addresses. If status is `failed`, stop polling and show the backend error/message if present.

Provision state fields selected by iOS:

- `id`
- `provision_status`
- `provision_source`
- `provision_phase`
- `provisioned_at`
- `addresses_ready_at`
- `map_ready_at`
- `optimized_at`
- `snapshot_bucket`
- `snapshot_prefix`
- `snapshot_buildings_url`
- `snapshot_roads_url`
- `address_source`
- `coverage_score`
- `data_quality`
- `standard_mode_recommended`
- `data_quality_reason`
- `provision_timings`

## Campaign List And Open Flow

iOS source:

- `CampaignsAPI.fetchCampaignsV2`
- `CampaignV2Store`
- `CampaignMapView.swift`
- `MapFeaturesService.fetchAllCampaignFeatures`

Android needs two separate flows:

1. Campaign list display.
2. Campaign map/session open.

### Campaign List Display

iOS loads campaign rows from Supabase and then enriches them with address counts and cached provision metadata.

List behavior to mirror:

- Fetch campaigns owned by the current user.
- Include campaigns available through the active workspace/shared campaign IDs when workspace access applies.
- Exclude hidden internal/demo campaigns the same way iOS does.
- Fetch address counts separately through `get_campaign_address_counts` instead of trusting shell-create counts.
- Cache campaign metadata locally so offline list display can show the latest known status.

Fields Android should keep for list cards:

```json
{
  "id": "campaign-uuid",
  "name": "Spring Listing Push",
  "title": "Spring Listing Push",
  "description": "Downtown west territory",
  "type": "seller",
  "status": "draft",
  "address_source": "map",
  "region": "CA",
  "workspace_id": "workspace-uuid",
  "total_flyers": 0,
  "address_count": 1240,
  "scans": 0,
  "conversions": 0,
  "provision_status": "ready",
  "provision_phase": "linked",
  "provision_source": "diamond",
  "map_mode": "hybrid",
  "building_link_confidence": 86,
  "coverage_score": 0.92,
  "data_quality": "good",
  "standard_mode_recommended": false,
  "snapshot_bucket": "bucket",
  "snapshot_prefix": "prefix"
}
```

List UI should distinguish:

| Campaign state | Android list behavior |
| --- | --- |
| Draft shell with no boundary | Show as draft/setup incomplete. |
| Boundary uploaded and `pending` | Show provisioning/loading state. |
| `ready` and map usable | Allow opening map/session. |
| `failed` | Show failed state and retry/recreate option. |
| Offline with cached metadata | Show last known metadata and cached/offline badge if desired. |

### Opening A Campaign

When the user taps a campaign:

1. Load the latest campaign metadata if online.
2. If offline, load cached campaign metadata and cached map bundle.
3. Check `CampaignsAPI.sessionStartBlockReason` equivalent rules:
   - Online: block failed or not-ready campaigns unless the map is usable.
   - Offline: require a cached campaign map bundle/downloaded state.
4. Set the selected campaign in app state.
5. Fetch all campaign map features.
6. Render once buildings or addresses are usable.

Android should avoid coupling the list card's address count to map readiness. A campaign can have address rows before building materialization/linking has finished, so opening should be gated by provision status/phase and cached map data, not by count alone.

## Map Data Fetching

Android should use the backend API base URL configured for the app and include the Supabase bearer token on every backend request.

iOS base URL logic lives in `BuildingLinkService.swift` and `CampaignsAPI.swift`:

- Read `FLYR_PRO_API_URL` from app config.
- If the host is apex `flyrpro.app`, normalize to `https://www.flyrpro.app`.

### Buildings

iOS source: `BuildingLinkService.fetchBuildings`.

Endpoint:

```http
GET /api/campaigns/{campaignId}/buildings
Authorization: Bearer <supabase-access-token>
```

Retry behavior:

- Use cached/offline bundle first when offline.
- If the online response fails, is empty, or has no polygon features, retry once with cache bypass:

```http
GET /api/campaigns/{campaignId}/buildings?cache=bypass
```

Backend building endpoint behavior:

- Authenticates user and campaign/workspace access.
- Checks polished cache in `campaign_polished_building_features`.
- Enriches features with persisted address/building links.
- Uses materialized building rows where available.
- Falls back through snapshots, RPCs, scoped PMTiles, S3 artifacts, and manual/address proxy features.
- Returns a GeoJSON `FeatureCollection`.
- Uses no-store JSON headers.

Building feature properties Android should preserve:

```json
{
  "id": "building-id",
  "building_id": "building-id",
  "building_gers_id": "gers-id",
  "public_building_id": "public-id",
  "canonical_building_id": "canonical-id",
  "building_identifier_source": "gold",
  "address_id": "address-id",
  "address_ids": ["address-id-1", "address-id-2"],
  "address_text": "123 Main St",
  "address_count": 2,
  "house": "123",
  "street": "Main St",
  "confidence": 0.91,
  "match_method": "stable_linker",
  "source": "gold",
  "status": "visited",
  "scans": 1,
  "height": 8,
  "height_m": 8,
  "min_height": 0,
  "is_townhome": false,
  "units_count": 1,
  "area": 120,
  "building_type": "residential",
  "qr_scanned": false,
  "is_linked": true
}
```

Renderable building geometries:

- `Polygon`
- `MultiPolygon`

iOS filters out tiny non-manual polygons below roughly 30 square meters before display. Android should apply a similar filter if the map becomes noisy.

### Addresses

iOS sources:

- `BuildingLinkService.fetchCampaignAddresses`
- `MapFeaturesService.fetchCampaignAddresses`
- Backend: `app/api/campaigns/[campaignId]/addresses/route.ts`

Endpoint:

```http
GET /api/campaigns/{campaignId}/addresses
Authorization: Bearer <supabase-access-token>
```

Backend behavior:

- Authenticates user and campaign/workspace access.
- Reads addresses through `rpc_get_campaign_addresses`.
- Falls back to direct `campaign_addresses` rows.
- For non-Diamond campaigns, can fall back to S3 snapshot address artifacts.
- Returns empty for Diamond when no address rows are available instead of fabricating data.

Address feature properties Android should preserve:

```json
{
  "id": "address-id",
  "address_id": "address-id",
  "formatted_address": "123 Main St, Toronto, ON",
  "address_text": "123 Main St",
  "house": "123",
  "street": "Main St",
  "city": "Toronto",
  "state": "ON",
  "postal_code": "M5V 2T6",
  "longitude": -79.4010,
  "latitude": 43.6510,
  "building_id": "building-id",
  "building_gers_id": "gers-id",
  "confidence": 0.91,
  "match_method": "stable_linker",
  "status": "not_visited",
  "scans": 0
}
```

Android should de-duplicate address features for display, especially when both building-enriched and address endpoint data contain the same home.

### Parcels

iOS source: `BuildingLinkService.fetchCampaignParcels` and `MapFeaturesService.fetchCampaignParcels`.

Endpoint:

```http
GET /api/campaigns/{campaignId}/parcels
Authorization: Bearer <supabase-access-token>
```

The backend parcel route is not the main campaign contract, but Android should support parcel rendering when features are available. Parcels help linking and can support selected/highlight state.

### Roads

iOS source:

- `MapFeaturesService.fetchCampaignRoads`
- `CampaignRoadService.getRoadsForSession`

Roads are fetched separately and cached with the campaign map bundle. They are useful visual context but should not block campaign map readiness.

### Diamond Manifest And PMTiles

Backend source: `app/api/campaigns/[campaignId]/diamond-manifest/route.ts`.

Endpoint:

```http
GET /api/campaigns/{campaignId}/diamond-manifest
Authorization: Bearer <supabase-access-token>
```

This endpoint can return address point manifests, backend vector tile URL templates, and PMTiles metadata. However, iOS currently has `diamondPMTilesRenderingEnabled = false` in `MapFeaturesService.swift`, so the production-equivalent Android path should render backend GeoJSON buildings and addresses first.

Android can add manifest/PMTiles support later, but it should not be required for parity with the current iOS app.

## Linking Model

There are three linking layers Android needs to understand:

1. Backend canonical/persisted links.
2. Manual links.
3. Optional client-generated links.

### Backend Auto-Linking

Backend sources:

- `app/api/campaigns/provision/route.ts`
- `StableLinkerService.ts`

The stable linker uses a tiered matching strategy:

- Direct building containment plus street verification.
- Parcel bridge.
- Point-on-surface.
- Proximity plus semantic matching.
- Fallback nearest candidate.

Provisioning writes building/address links into persisted tables and enriches building GeoJSON with:

- `address_id`
- `address_ids`
- `address_text`
- `house`
- `street`
- `confidence`
- `match_method`
- `is_linked`
- `address_count`

Android display code should prefer these server-enriched properties when present.

### Manual Links

Manual links represent user-corrected address/building relationships. The backend and local cache protect them from being overwritten by auto-linking.

Android rules:

- Never overwrite a manual link with an auto/client-generated link.
- When editing links locally, persist the manual link through the same backend/local contracts used by the app's manual linking feature.
- After manual changes, refresh buildings/addresses so enriched properties match the latest link state.

### Client-Generated Links

iOS source:

- `MapFeaturesService.scheduleClientLinkingIfReady`
- `MapFeaturesService.applyClientLinks`
- `BuildingLinkService.publishClientGeneratedLinks`
- Backend: `app/api/campaigns/[campaignId]/client-links/route.ts`

Endpoint:

```http
POST /api/campaigns/{campaignId}/client-links
Authorization: Bearer <supabase-access-token>
Content-Type: application/json
```

Payload:

```json
{
  "links": [
    {
      "address_id": "address-uuid",
      "building_gers_id": "building-gers-id",
      "confidence": 0.87,
      "match_source": "client_auto"
    }
  ]
}
```

Backend behavior:

- Authenticates user and campaign/workspace access.
- Caps payloads to protect the endpoint.
- Verifies addresses belong to the campaign.
- Skips manual links.
- Writes `building_gers_id`, `match_source = client_auto`, and confidence onto campaign addresses.

Android does not need client linking for initial parity if backend links are present. If Android implements it, use the endpoint above and keep generated links separate from manual links in local cache.

## Map Display Contract

iOS display sources:

- `CampaignMapView.swift`
- `MapFeaturesService.swift`
- `MapLayerManager.swift`
- `BuildingLinkModels.swift`

Primary Android rendering path:

1. Fetch campaign metadata.
2. Resolve `map_mode`, but default to GeoJSON building display.
3. Fetch buildings and addresses.
4. Render building polygons/extrusions when building features exist.
5. Render address points/labels in address mode or edit mode.
6. Render parcels and roads when available.
7. Apply selected/highlight/visited/scanned state.

Although `map_mode` may be `standard_pins`, iOS currently disables the standard pins renderer and still relies on the Mapbox GeoJSON route. Android should support address-only fallback for low-quality building links, but the first implementation should prioritize the GeoJSON building/address layer path.

### Display Modes

iOS has two primary campaign map modes:

- Building mode.
- Address mode.

Behavior to mirror:

- Building mode shows building polygons/extrusions.
- Address mode shows address points more prominently.
- In building mode, address layer is hidden unless edit/linking mode needs it.
- If no building features exist but addresses do, Android should render address proxy markers/polygons instead of showing a blank map.

### Layers

Mapbox source/layer names in iOS are in `MapLayerManager.swift`. Android names do not need to match exactly, but the layer responsibilities should.

| Layer responsibility | iOS source/layer concept |
| --- | --- |
| Building GeoJSON source | `buildings-source` |
| Building extrusion/fill | `buildings-extrusion` |
| Selected building overlay | selected building overlay layers |
| Townhome overlay | townhome overlay layers |
| Address point source | `campaign-address-points` |
| Address point extrusion/fill | `campaign-address-points-extrusion` |
| Selected address overlay | `campaign-address-points-selected-extrusion` |
| Address number labels | address numbers source/layer |
| Roads source/layer | `roads-source`, `roads-line` |
| Parcels source/layers | parcel fill/line/selected layers |

### Status Colors

iOS status color logic is in `BuildingLinkModels.swift`.

Android should preserve these meanings:

| State | Display intent |
| --- | --- |
| QR scanned | Purple/highest priority. |
| Hot lead / lead / appointment / future seller | Gold. |
| Visited | Green. |
| Default / not visited | Red. |
| Selected/highlighted | Selected overlay or feature-state style. |

Feature state updates should affect buildings, addresses, parcels, and any Diamond/vector layers Android later supports.

### Session Targets

iOS target resolution lives in `MapFeaturesService.CampaignTargetResolver`.

Rules to mirror:

- Prefer building targets when buildings exist and building mode is active.
- For flyer/address workflows, prefer address points.
- If a building maps cleanly to a single address, Android may use the building centroid as a target fallback.
- Coordinates should come from point geometry when available, otherwise from polygon centroid.

## Offline And Cache Behavior

iOS offline source: `CampaignRepository.swift`.

Android should cache enough data to open a campaign session without network once it has been loaded successfully.

Cache these campaign-level records:

- Campaign metadata.
- Building GeoJSON features.
- Address GeoJSON/features.
- Building/address links.
- Client-generated links if Android creates them.
- Roads.
- Parcels where available.
- Provision metadata needed to decide whether the map is usable.

iOS reconstructs an offline campaign map bundle from cached records and merges links back into features. Android should do the same: the cache should be render-ready, not just raw fragments.

Offline behavior:

- If online, fetch fresh data and update cache.
- If offline and cached bundle exists, open the campaign from cache.
- If offline and no cached map bundle exists, block the session with a clear reason.
- Do not mark a failed/empty online provision as successful just to allow offline mode.

## Error Handling And Edge Cases

Android should explicitly handle these states:

| State | Android behavior |
| --- | --- |
| Polygon has fewer than 3 unique points | Keep user in drawing flow and show validation. |
| Campaign shell create fails | Do not call boundary/provision; allow retry. |
| Boundary upload fails | Keep campaign draft; allow retry from the same polygon. |
| Provision returns `202`/accepted/pending | Start polling; show provisioning progress. |
| Provision status stays `pending` | Keep polling with backoff and allow user to leave/reopen campaign. |
| Provision status `failed` | Stop polling; show backend message/error and retry option. |
| Unsupported region `422` | Show unsupported region message; do not retry automatically. |
| Buildings endpoint empty | Retry with cache bypass; then fall back to address display if addresses exist. |
| Addresses endpoint empty | Continue if buildings exist; otherwise show map-data-not-ready state. |
| `linking_failed` phase | Still allow map display if status is `ready`; use address/building proxies as needed. |
| Low `building_link_confidence` | Prefer hybrid/address fallback UI; do not block campaign. |
| Auth `401` | Refresh session or send user to sign in. |
| Access `403` | Show no-access state; do not mutate local campaign. |
| Offline with cache | Open cached bundle. |
| Offline without cache | Block session with clear offline-cache-missing reason. |

## Android Implementation Checklist

Creation:

- Implement polygon drawing, vertex editing, close-ring behavior, and validation.
- Serialize GeoJSON polygons as `[longitude, latitude]`.
- Create the campaign shell with `addressSource = map`, `addressTargetCount = 0`, and `addressesJSON = []`.
- Upload `territory_boundary`, uppercase region, and bbox.
- POST `/api/campaigns/provision`.
- Handle accepted/pending/ready/failed/422 responses.
- Poll provision state until map usable.

Fetching:

- Normalize API base URL from config.
- Attach Supabase bearer token to every backend request.
- Fetch buildings with cache-bypass retry on empty/non-polygon response.
- Fetch addresses and de-duplicate for display.
- Fetch parcels/roads as non-blocking enhancements.
- Cache all successful map data.

Display:

- Render building polygons/extrusions first.
- Render address points/labels in address/edit/fallback modes.
- Render roads/parcels when available.
- Apply status colors and selected feature state.
- Avoid blank maps by falling back to address proxies when buildings are unavailable.

Linking:

- Prefer backend-enriched links.
- Preserve manual links.
- Optionally run client linker and publish generated links to `/client-links`.
- Refresh map features after manual or generated link updates.

Offline:

- Save render-ready campaign bundles.
- Rehydrate buildings, addresses, links, roads, and parcels from cache.
- Block offline sessions only when no usable cached bundle exists.

## Test Matrix

| Scenario | Expected result |
| --- | --- |
| Polygon campaign happy path | Shell create succeeds, boundary uploads, provision accepted, polling reaches map usable, buildings/addresses render. |
| Async provision | Backend returns accepted/pending; Android shows progress and continues polling after leaving/reopening screen. |
| Immediate provision ready | Android skips unnecessary waiting and fetches map data. |
| Unsupported region | Android shows unsupported region error and does not fabricate map data. |
| Provision failed | Android shows backend error/message and retry path. |
| Buildings empty once | Android retries with `?cache=bypass`. |
| Buildings empty but addresses present | Android renders address fallback/proxies. |
| `linking_failed` with ready status | Android opens map using available features. |
| Low link confidence | Android still opens campaign and favors address/hybrid fallback UI. |
| Offline after prior successful load | Android opens cached map bundle. |
| Offline before map cache exists | Android blocks campaign session with clear explanation. |
| Auth expired | Android refreshes session or routes to sign-in without corrupting campaign state. |
| Workspace shared campaign | Android respects backend access and displays if authorized. |
| Manual link exists | Auto/client-generated linking does not overwrite it. |
| Visit/status update | Building/address colors update for visited, QR scanned, lead, appointment, selected. |

## Minimal Android Pseudocode

```kotlin
suspend fun createPolygonCampaign(input: CampaignInput, polygon: List<LatLng>): Campaign {
    require(uniquePointCount(polygon) >= 3)

    val region = inferOrSelectRegion(polygon).uppercase()
    val geoJson = polygon.toClosedGeoJsonLonLat()
    val bbox = geoJson.computeBbox()

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

    campaignRepository.updateTerritoryBoundary(
        campaignId = campaign.id,
        territoryBoundary = geoJson,
        region = region,
        bbox = bbox
    )

    val provision = backend.provisionCampaign(campaign.id)

    if (provision.isAcceptedOrPending || provision.isReady) {
        waitUntilMapUsable(campaign.id)
    } else {
        throw CampaignProvisionException(provision.message)
    }

    val buildings = backend.fetchBuildings(campaign.id).retryWithCacheBypassIfEmpty()
    val addresses = backend.fetchAddresses(campaign.id)
    val parcels = backend.fetchParcelsOrNull(campaign.id)
    val roads = backend.fetchRoadsOrNull(campaign.id)

    val bundle = CampaignMapBundle(
        campaign = campaignRepository.refreshCampaign(campaign.id),
        buildings = buildings,
        addresses = addresses.deduped(),
        parcels = parcels,
        roads = roads
    )

    campaignCache.save(bundle)
    return bundle.campaign
}
```

## Final Android Parity Rule

For first parity, Android should behave like current iOS:

- Territory polygon is the creation input.
- Supabase stores the campaign shell and provision metadata.
- Backend provisioning creates addresses, buildings, snapshots, and links.
- Android renders backend GeoJSON buildings/addresses first.
- PMTiles/Diamond manifest support is optional future work, not required for current parity.
- Offline sessions depend on a previously cached render-ready campaign bundle.
