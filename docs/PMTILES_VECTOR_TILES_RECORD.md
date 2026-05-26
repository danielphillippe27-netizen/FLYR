# Architecture Record: PMTiles and Vector Tiles for Campaign Geometry

**Status:** Accepted
**Date:** 2026-05-06
**Owners:** FLYR iOS + backend

## Context

FLYR campaign maps have historically moved building, address, parcel, and road geometry around as GeoJSON FeatureCollections. That worked while campaign geometry was small, but it makes larger territories expensive to download, parse, diff, cache, and render. The current app already has a Diamond geometry path that can install Mapbox vector sources from a campaign manifest, while the older contract still describes S3-backed gzipped GeoJSON snapshots.

We are moving away from GeoJSON as the primary map geometry transport.

## Decision

Use **PMTiles-backed vector tiles** as the primary campaign geometry record and delivery format for renderable map geometry.

The campaign manifest is the client contract. For Diamond/vector geometry it must describe:

| Field | Purpose |
| --- | --- |
| `geometry_provider` | `pmtiles` or `pmtiles_zxy` |
| `geometry_version` | Monotonic version for invalidation |
| `geometry_etag` | Cache identity for the current tile archive |
| `tilejson_url` | Optional TileJSON endpoint |
| `vector_tile_url_template` | Z/X/Y tile URL template consumed by Mapbox |
| `source_layers` | Layer names for `buildings`, `address_circles`, `addresses`, and `parcels` |
| `promote_ids` | Stable feature IDs per source layer for feature state |
| `join_key` | Stable join key, normally `address_id` or building/address assignment key |
| `primary_state_layer` | Layer whose features receive status state first |
| `bounds`, `minzoom`, `maxzoom` | Tile coverage and zoom contract |
| `fallback_geometry_provider` | Temporary fallback while campaigns migrate |

Vector tile layers should carry stable properties needed for rendering and status joins, not full relational state. Mutable campaign state stays in Supabase and is applied through feature state or a small state sync payload.

## Target Flow

1. User creates a campaign and stores the territory polygon in Supabase.
2. Provisioning loads the campaign polygon and generates clipped campaign geometry.
3. The geometry pipeline writes a PMTiles archive or PMTiles-addressable vector tile set for the campaign.
4. Backend stores/serves a manifest with the vector tile URL template, source layers, promoted IDs, bounds, and version metadata.
5. iOS fetches the manifest through `DiamondManifestAPI`.
6. `VectorTileDiamondGeometryProvider` installs a Mapbox `VectorSource` and renders buildings, address cylinders, parcels, labels, and selection/status layers from vector source layers.
7. Address statuses, hidden buildings, manual edits, and teammate/session overlays remain separate mutable state paths and update independently from the immutable geometry archive.

## GeoJSON Boundaries

GeoJSON is no longer the default geometry transport for campaign rendering.

Keep GeoJSON only where it is still the right shape:

- User-drawn territory polygons and lightweight request bodies.
- Session paths and breadcrumbs.
- Manual shape editing APIs while edit tooling is not tile-native.
- Legacy campaign fallback until a PMTiles manifest exists.
- Debug/export tooling where human-readable geometry is useful.

Avoid adding new user-facing map rendering paths that require downloading full campaign GeoJSON FeatureCollections.

## Implementation Notes

- iOS already recognizes `geometry_provider` values `pmtiles` and `pmtiles_zxy` in `DiamondManifest`.
- iOS already installs vector tile geometry through `VectorTileDiamondGeometryProvider`.
- Address cylinders require an `address_circles` polygon source layer. Point-only address layers are not enough for the current 3D cylinder renderer.
- `promote_ids` must be stable and match the join keys used by status/state updates.
- Tile archives should be immutable per `geometry_version`/`geometry_etag`; publish a new version instead of mutating tiles in place.
- The old GET `/api/campaigns/[id]/buildings` GeoJSON endpoint should be treated as legacy fallback, not the strategic path.

## Consequences

Benefits:

- Smaller initial map payloads.
- Progressive loading by viewport and zoom.
- Better offline/cache behavior.
- Cleaner separation between immutable geometry and mutable campaign state.
- Less client-side JSON parsing and source replacement work.

Costs:

- Requires a tile generation and manifest publishing pipeline.
- Requires source layer/property compatibility tests.
- Requires legacy fallback during migration.
- Manual geometry edits need an explicit retile/versioning story.

## Migration Checklist

- [ ] Add or confirm backend endpoint for `GET /api/campaigns/[campaignId]/diamond-manifest`.
- [ ] Generate PMTiles/vector tiles during provisioning for Diamond campaigns.
- [ ] Store manifest metadata with campaign snapshot/provision state.
- [ ] Keep GeoJSON fallback for existing campaigns without a renderable manifest.
- [ ] Add contract tests for source layer names, promoted IDs, bounds, and required properties.
- [ ] Add iOS regression tests around manifest decoding and vector source installation.
- [ ] Plan a retile path for manual building/address edits.
