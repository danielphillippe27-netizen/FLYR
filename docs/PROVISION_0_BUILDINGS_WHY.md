# Why you see 0 buildings after creating a campaign (provision)

## What happens when you create a campaign

1. **iOS** creates the campaign, sets `territory_boundary`, then calls **POST /api/campaigns/provision**.
2. **Provision backend** (the service that implements that route, e.g. flyrpro.app) should:
   - Load polygon from Supabase, call Tile Lambda.
   - Lambda reads S3 parquet (Overture), clips by polygon, writes GeoJSON to S3 snapshot bucket.
   - Backend writes **addresses** into `campaign_addresses`, and **snapshot metadata** (bucket, keys) into `campaign_snapshots`. Building geometry stays in **S3**.
3. **iOS** then loads the map: calls **rpc_get_campaign_full_features** (Supabase) → 0 buildings, because the RPC reads from table `buildings`, and in this architecture buildings live in S3, not in that table.
4. **Silver fallback**: iOS calls **GET /api/campaigns/[id]/buildings**. That route must read `campaign_snapshots`, fetch building GeoJSON from S3, and return it. If that returns empty or 404, you get **0 buildings**.

So “not working” usually means one of these:

---

## 1. POST /api/campaigns/provision is not in this repo

The **provision** endpoint is not implemented in `backend-api-routes/` in this repo. The app calls whatever base URL is configured (e.g. `FLYR_PRO_API_URL` → flyrpro.app). So:

- If the **main backend** (flyrpro.app or your deployed API) does not implement **POST /api/campaigns/provision**, provision never runs and no snapshot is created.
- If it does implement it but **does not write** to `campaign_snapshots` (and S3) after Lambda runs, then GET buildings has nothing to serve.

**Check:** After creating a campaign, in Supabase run:

```sql
SELECT id, campaign_id, bucket, buildings_key, addresses_key, buildings_count, addresses_count
FROM campaign_snapshots
WHERE campaign_id = 'YOUR_CAMPAIGN_ID';
```

- If there is **no row**: provision either didn’t run or didn’t write to `campaign_snapshots`. Fix the backend that runs provision.
- If there is a row but **buildings_key is null**: Lambda or the ingest step didn’t write building GeoJSON to S3 / didn’t save the key. Fix the provision backend.

---

## 2. GET /api/campaigns/[id]/buildings was missing or returns empty

This repo **now** has **GET /api/campaigns/[campaignId]/buildings** in `backend-api-routes/`. It:

- Checks auth and campaign access (owner or workspace member).
- Reads `campaign_snapshots` for the campaign.
- If there is no snapshot or no `buildings_key`, it returns **200 + empty FeatureCollection** (so the app doesn’t 404).
- It does **not** fetch from S3 (no AWS SDK in this repo). So with only this route, the response is always empty.

So:

- If your **deployed API** is **this** repo’s backend: the route exists and returns valid JSON, but always with 0 features until you add S3 fetch (or another source) in that route.
- If your deployed API is **another** backend (e.g. flyrpro.app): that backend must implement GET buildings by reading `campaign_snapshots` and returning the building GeoJSON from S3. If it doesn’t, or if it returns empty, you get 0 buildings.

---

## 3. RLS: workspace members could not read campaign_snapshots

Previously, only `campaigns.owner_id = auth.uid()` could read `campaign_snapshots`. So if a **workspace member** (not the campaign owner) opened the campaign, the backend (when using the user’s JWT to read Supabase) might not see the snapshot row and would return empty.

**Fix applied in this repo:** Migration `20260220100000_campaign_snapshots_workspace_rls.sql` updates RLS so that **workspace members** can also SELECT from `campaign_snapshots` and `building_units` for campaigns in their workspace. Apply that migration and ensure the backend uses the user’s token when reading snapshot metadata if you want workspace members to see buildings.

---

## What to do

1. **Confirm provision runs and writes snapshot**  
   After create + provision, check `campaign_snapshots` for that campaign (query above). If the row is missing or `buildings_key` is null, fix the **provision backend** (the service that implements POST /api/campaigns/provision).

2. **Confirm GET buildings is implemented and uses S3**  
   The endpoint that serves GET /api/campaigns/[id]/buildings must read `campaign_snapshots`, then fetch building GeoJSON from S3 (using bucket + buildings_key) and return it. In this repo the route exists but does not perform the S3 fetch; add that in the backend that has S3/credentials, or ensure your main backend does it.

3. **Apply the workspace RLS migration**  
   Run `20260220100000_campaign_snapshots_workspace_rls.sql` so workspace members can read snapshot metadata (and building_units) for their workspace’s campaigns.

4. **Optional: use Supabase `buildings` table**  
   If you prefer not to rely on S3, you can have provision (or another job) write building rows into the `buildings` table. Then `rpc_get_campaign_full_features` would return them and the map would show buildings without needing GET buildings or S3.
