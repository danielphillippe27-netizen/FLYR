# Campaign provision & session readiness — regression checklist

Run after backend (`/api/campaigns/provision`) and Supabase migrations deploy.

## Map polygon campaign (happy path)

1. Create campaign from drawn polygon with name + territory.
2. Confirm logs: road prep completes, then `provision` returns HTTP 200 with `success: true`, `roads_count` > 0, `addresses_saved` > 0.
3. Confirm `campaigns.provision_status` = `ready`.
4. Confirm `campaign_road_metadata`: `roads_status` = `ready`, `road_count` > 0.
5. Open campaign map; start door-knocking session — should succeed without “roads not ready” / provision alerts.

## Map campaign — roads missing

1. Simulate or use a campaign with `address_source` = `map` and no `campaign_road_metadata` row (or `road_count` = 0).
2. Call `POST /api/campaigns/provision` — expect **422**, `success: false`, `provision_status` = `failed`, body includes `readiness_checks`.

## Visit status persistence

1. Start a session on a fully ready map campaign.
2. Mark a house with a non-`none` status (e.g. delivered).
3. Query `address_statuses` for that `campaign_id` — expect a row with matching `campaign_address_id` / `status`.
4. Repeat as workspace **member** (not owner) — expect same success after RLS/RPC updates.

## iOS decoding

1. Fetch statuses — rows using `campaign_address_id` in JSON should map to in-app address IDs.
2. No RPC calls with `p_status` = `untouched` (should use `none`).
