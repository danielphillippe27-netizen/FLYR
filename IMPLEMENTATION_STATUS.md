# Implementation Status - Tilequery Fixes

## ✅ Step 1: RPC Parameter Fix - COMPLETE

**Migration**: `20250108000000_fix_get_buildings_rpc_text_array.sql`
- RPC function now accepts `text[]` and casts to `uuid`
- Returns `bp.geom` directly (already a GeoJSON Feature)
- Swift code passes string array directly (Supabase SDK handles encoding)

**Files Updated**:
- `supabase/migrations/20250108000000_fix_get_buildings_rpc_text_array.sql`
- `FLYR/Feautures/Campaigns/API/BuildingsAPI.swift` - uses direct array passing

**Status**: ✅ Code compiles, ready to test

---

## ⚠️ Step 2: Mapbox Token - VERIFY

**Current Status**: Token is set in Supabase secrets (shown as hash)

**Action Required**: 
- Verify token starts with `sk.` (secret token)
- Verify token has `tilesets:read` scope
- If not, update with:
  ```bash
  supabase secrets set MAPBOX_ACCESS_TOKEN=sk.your_secret_token_here
  supabase functions deploy tilequery_buildings
  ```

---

## ✅ Step 3: Tileset Verification - COMPLETE

**Tileset**: `mapbox.mapbox-buildings-v3` ✅
- URL format: `.../v4/mapbox.mapbox-buildings-v3/tilequery/{lon},{lat}.json?radius=50&limit=8&access_token=...`
- No `layers` parameter needed (building-only tileset)
- Initial radius: 50m
- Retry radius: 75m

**Files Verified**:
- `supabase/functions/tilequery_buildings/index.ts` - uses buildings-v3

---

## 📋 Step 4: Sanity Test - READY

**Test Script**: `test_tilequery_coverage.sh`

**Quick Test Commands**:

```bash
# Orono (may be 0 - sparse coverage)
curl "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-78.62245,43.98785.json?radius=75&limit=8&access_token=YOUR_TOKEN"

# Toronto CBD (should return features)
curl "https://api.mapbox.com/v4/mapbox.mapbox-buildings-v3/tilequery/-79.3832,43.6532.json?radius=50&limit=8&access_token=YOUR_TOKEN"
```

**Expected Results**:
- Toronto: > 0 features (urban area)
- Orono: 0 features possible (rural area) → proxies expected

---

## Next Steps

1. **Apply RPC Migration** (if not already applied):
   ```bash
   supabase db push
   ```

2. **Verify/Update Mapbox Token**:
   ```bash
   # Check current token (will show hash)
   supabase secrets list
   
   # Update if needed (use sk. token with tilesets:read)
   supabase secrets set MAPBOX_ACCESS_TOKEN=sk.your_token
   supabase functions deploy tilequery_buildings
   ```

3. **Run Coverage Test**:
   ```bash
   # Set your token
   export MAPBOX_ACCESS_TOKEN=sk.your_token
   
   # Run test
   ./test_tilequery_coverage.sh
   ```

4. **Test in App**:
   - Load campaign map
   - Verify red outlines appear for addresses with polygons
   - Verify proxy circles appear for addresses without polygons

---

## All Good Checklist

- [x] RPC accepts text[] and casts to uuid
- [x] Swift passes string array (no encoding errors)
- [x] Edge Function uses mapbox-buildings-v3
- [x] URL format: {lon},{lat} order
- [x] Radius: 50m initial, 75m retry
- [x] Logging: URL (masked), status, candidates, geometry type
- [x] Geometry filtering: Polygon/MultiPolygon only
- [x] Red outlines: 2.0px width, systemRed, round joins/caps
- [ ] Mapbox token verified (sk. with tilesets:read)
- [ ] Coverage test run (Toronto > 0, Orono may be 0)
- [ ] App tested (red outlines visible)

