# Where buildings and addresses come from (0 buildings fix)

## When creating a campaign (provision)

**No.** During campaign creation we do **not** query or write `ref_buildings_gold` or `ref_addresses_gold`.

The provision flow (documented in `ARCHITECTURE_PROVISION.md` and `BACKEND_API_CONTRACT.md`) is:

1. iOS: create campaign → set `territory_boundary` → call **POST /api/campaigns/provision**.
2. Backend loads polygon from Supabase, calls **Tile Lambda**.
3. **Lambda reads from S3 parquet** (Overture tiled buildings/addresses), clips by polygon (DuckDB + ST_Intersects), writes GeoJSON to the snapshot bucket.
4. Backend ingests **addresses** into Supabase `campaign_addresses`; building geometry stays in **S3**; metadata in `campaign_snapshots`; linking → `building_address_links`, `building_units`.

So at **create/provision** time the data source is **S3 parquet** (Lambda), not the gold tables. To have creation use `ref_buildings_gold` / `ref_addresses_gold`, the **provision backend** (the service that implements POST /api/campaigns/provision, not in this repo) would need to be changed to read from those tables instead of or in addition to the Lambda/S3 path.

---

## When viewing a campaign (map / RPCs)

## Current state: we do **not** query `ref_buildings_gold` or `ref_addresses_gold`

All RPCs and app code in this repo use only:

| Source | Tables / API | Used by |
|--------|--------------|--------|
| **Supabase** | `public.buildings`, `public.campaign_addresses`, `public.roads` | `rpc_get_campaign_full_features`, `rpc_get_campaign_addresses`, `rpc_get_campaign_roads` |
| **S3 (Silver)** | GET `/api/campaigns/[id]/buildings` (snapshot from provision) | `BuildingLinkService.fetchBuildings()` → fallback when RPC returns no polygons |

So:

- **RPCs** (see `supabase/migrations/20250203_ios_map_features_rpc.sql`):
  - `rpc_get_campaign_full_features` → `FROM public.buildings b` (+ joins to `building_address_links`, `campaign_addresses`, `building_stats`)
  - `rpc_get_campaign_addresses` → `FROM public.campaign_addresses a`
  - `rpc_get_campaign_roads` → `FROM public.roads r`

- **Gold tables** `ref_buildings_gold` and `ref_addresses_gold` are **not** referenced in any migration or RPC in this repo. The guide `IOS_GOLD_SILVER_BUILDINGS_GUIDE.md` describes a design where Gold data lives there, but that path is not implemented in the DB layer here.

## Why you see 0 buildings

1. **RPC returns empty**  
   RPCs only read from `buildings` and `campaign_addresses`. If provision (or your ingest) writes elsewhere (e.g. only to S3, or only to `ref_*` tables), those Supabase tables stay empty for the campaign → RPC returns 0 features.

2. **Silver fallback**  
   The app then calls GET `/api/campaigns/{id}/buildings`. If that returns empty (e.g. no S3 snapshot, or snapshot not yet written), you still get 0 buildings.

So: **we are not querying `ref_buildings_gold` or `ref_addresses_gold`.** To get buildings from them you need either:

- **Option A – Backend ingest**  
  Have provision (or another job) that writes to `public.buildings` and `public.campaign_addresses` from your gold/silver pipeline so the existing RPCs and app code keep working.

- **Option B – Add Gold to the DB layer**  
  Add or change RPCs so they also read from `ref_buildings_gold` / `ref_addresses_gold` (e.g. `campaign_addresses.building_id` → `ref_buildings_gold.id` as in the guide). That requires a new migration that defines or uses those tables and updates the campaign feature RPCs to include Gold (e.g. UNION or prefer Gold when present).

If you share the schema of `ref_buildings_gold` and `ref_addresses_gold` (column names, FKs), we can add a migration that updates `rpc_get_campaign_full_features` / `rpc_get_campaign_addresses` to query them.
