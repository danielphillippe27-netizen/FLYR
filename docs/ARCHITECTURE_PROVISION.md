# Provision Architecture (Lambda + S3)

Short reference for how campaign provisioning works after the migration from MotherDuck to Lambda + S3.

## Flow Summary

1. **User draws polygon** on the create-campaign map. The map control yields a GeoJSON polygon: `{ type: 'Polygon', coordinates: number[][][] }`.

2. **Polygon is stored in Supabase** when the campaign is created (e.g. `CampaignsService.createV2()` or POST `/api/campaigns`) with `territory_boundary`. No polygon is sent to MotherDuck or S3 at create time; only the campaign row is stored.

3. **Provision is triggered** when the client calls `POST /api/campaigns/provision` with `{ campaign_id }`.

4. **Server loads polygon and calls Lambda**: The provision API loads the campaign from Supabase (including `territory_boundary` and region), then sends that polygon (and region/campaign_id) to the Tile Lambda (e.g. `TileLambdaService.generateSnapshots()`). Lambda does not read from Supabase.

5. **Lambda gets buildings and addresses from S3**: Lambda uses the polygon to query S3 (extract/data-lake buckets): buildings from tiled parquet (DuckDB + ST_Intersects), addresses from parquet in the addresses bucket. Lambda writes gzipped GeoJSON to the snapshot bucket (e.g. `campaigns/{campaignId}/buildings.geojson.gz`, `addresses.geojson.gz`) and returns s3_keys and presigned URLs.

6. **Provision ingests addresses and stores snapshot metadata**: The backend downloads addresses from the snapshot URL and inserts them into Supabase `campaign_addresses`. It stores snapshot metadata (bucket, keys, counts) in Supabase `campaign_snapshots`. Building geometry stays in S3; only addresses and snapshot metadata are in Supabase.

7. **Linking**: Backend runs StableLinkerService (spatial join between snapshot buildings and campaign address points → `building_address_links`) and TownhouseSplitterService (multi-unit splits → `building_units`).

8. **Map rendering**: The map does not read S3 directly. It uses:
   - **GET /api/campaigns/[campaignId]/buildings**: Server reads `campaign_snapshots` for bucket/buildings_key, then GetObject from S3, gunzip, return building GeoJSON.
   - **building_units** from Supabase: Client (or backend) merges S3 parent footprints with Supabase unit polygons for townhouse extrusion.
   - Mapbox fill-extrusion layer renders the merged GeoJSON as 3D buildings.

## Data Ownership

| Data | Location |
|------|----------|
| Polygon, campaign metadata | Supabase `campaigns.territory_boundary` |
| Addresses | Supabase `campaign_addresses` |
| Snapshot metadata (bucket, keys, counts) | Supabase `campaign_snapshots` |
| Building geometry | S3 (snapshot bucket); served via GET buildings API |
| Address ↔ building links | Supabase `building_address_links` |
| Townhouse unit polygons | Supabase `building_units` |

No MotherDuck dependency; single source of truth for territory data is Supabase + S3 + Lambda.
