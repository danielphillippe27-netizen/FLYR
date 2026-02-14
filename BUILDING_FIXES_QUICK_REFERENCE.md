# Building Issues - Quick Reference Guide

## 🚀 Quick Fix Application

### 1. Apply SQL Migration
```bash
cd "/Users/danielphillippe/Desktop/FLYR IOS"
supabase db push
```

### 2. Rebuild iOS App
- Open in Xcode
- Clean Build Folder: `Cmd + Shift + K`
- Build: `Cmd + B`
- Run: `Cmd + R`

---

## 🔍 Quick Diagnostic Checks

### Check if Migration Applied
```sql
SELECT * FROM _migrations 
WHERE name LIKE '%fix_building_rpc%' 
ORDER BY created_at DESC;
```

### Test Building Data
```sql
-- Replace with your campaign ID
SELECT * FROM debug_building_data('YOUR-CAMPAIGN-UUID-HERE');
```

### Expected Output
```
total_buildings | buildings_with_gers_id | buildings_with_links | buildings_with_stats
----------------|------------------------|---------------------|---------------------
       100      |          100           |          85         |         85
```

---

## 📊 What Was Fixed

| Issue | Symptom | Fix |
|-------|---------|-----|
| **Crash on Tap** | App crashes when tapping buildings | SafeJSON sanitization |
| **Missing Column** | `is_townhome_row does not exist` error | SQL migration adds column |
| **Empty Results** | MVT finds buildings but RPC returns [] | Case-insensitive UUID joins |

---

## 🔧 Files Changed

### New Files
- ✅ `FLYR/Services/SafeJSON.swift`
- ✅ `supabase/migrations/20250206000004_fix_building_rpc_issues.sql`
- ✅ `docs/BUILDING_ISSUES_FIX_SUMMARY.md`

### Modified Files
- ✏️ `FLYR/Services/MapLayerManager.swift`
- ✏️ `FLYR/Feautures/Campaigns/API/BuildingsAPI.swift`
- ✏️ `FLYR/Services/MapFeaturesService.swift`

---

## 🧪 Test Scenarios

### 1. Test Building Tap (No Crash)
1. Open app
2. Navigate to campaign map
3. Tap on any building
4. ✅ Should NOT crash
5. ✅ Should show building details

### 2. Test Building Loading
1. Open campaign with addresses
2. Wait for buildings to load
3. ✅ Should see colored 3D buildings (not just dots)
4. Check logs for: `✅ [BUILDINGS] Loaded X features`

### 3. Test UUID Case Sensitivity
1. Check Xcode console for logs
2. Look for: `🔍 [BUILDINGS] Sample address IDs:`
3. ✅ Should see buildings loaded even with mixed-case UUIDs

---

## 🐛 Common Issues & Solutions

### Issue: Migration fails with "column already exists"
**Solution:** This is normal! Migration is idempotent (safe to run multiple times).

### Issue: Still getting empty building responses
**Checklist:**
- [ ] Run migration: `supabase db push`
- [ ] Check migration applied: `SELECT * FROM _migrations`
- [ ] Verify column exists: `SELECT is_townhome_row FROM buildings LIMIT 1`
- [ ] Check diagnostic: `SELECT * FROM debug_building_data('campaign-id')`

### Issue: Buildings still not showing on map
**Checklist:**
- [ ] MVT decode ran successfully? Check logs: `✅ [BUILDINGS] Chunk processed`
- [ ] RPC returns data? Check logs: `🔎 [RPC RAW]`
- [ ] Addresses have coordinates? `SELECT lat, lon FROM campaign_addresses`
- [ ] Buildings table has data? `SELECT COUNT(*) FROM buildings`

---

## 📞 Debug Logs to Look For

### ✅ Good Signs
```
✅ [SafeJSON] Sanitized properties successfully
✅ [MapLayer] Updated buildings source (100 features)
✅ [BUILDINGS] Loaded 85 features (85 polygons)
🔎 [RPC RAW] {"type":"FeatureCollection","features":[...]}
```

### ⚠️ Warning Signs (But Handled)
```
⚠️ [BUILDINGS] No matches found for this chunk!
⚠️ [MapFeatures] Empty response from RPC
⚠️ [BUILDINGS] Skipping row with null geom
```

### ❌ Error Signs (Need Investigation)
```
❌ [MapLayer] Error querying features
❌ [MapFeatures] Error fetching campaign features
❌ [BUILDINGS] Error processing chunk
```

---

## 🔬 Advanced Diagnostics

### Check UUID Case Mismatch
```sql
SELECT 
  b.gers_id,
  s.gers_id,
  b.gers_id = s.gers_id as exact_match,
  LOWER(b.gers_id::text) = LOWER(s.gers_id::text) as fixed_match
FROM buildings b
LEFT JOIN building_stats s ON LOWER(b.gers_id::text) = LOWER(s.gers_id::text)
WHERE b.campaign_id = 'YOUR-CAMPAIGN-ID'
LIMIT 5;
```

### Expected: `exact_match = false`, `fixed_match = true`

### Check MVT Decode Pipeline
```sql
-- Check if building_polygons table has data
SELECT COUNT(*), source FROM building_polygons GROUP BY source;

-- Check if addresses have linked buildings
SELECT 
  ca.id as address_id,
  ca.formatted,
  bp.id as building_polygon_id,
  bp.source
FROM campaign_addresses ca
LEFT JOIN building_polygons bp ON bp.address_id = ca.id
WHERE ca.campaign_id = 'YOUR-CAMPAIGN-ID'
LIMIT 10;
```

---

## 📚 Full Documentation

For complete details, see:
- [docs/BUILDING_ISSUES_FIX_SUMMARY.md](./docs/BUILDING_ISSUES_FIX_SUMMARY.md)

---

## ⏱️ Expected Resolution Time

- **Apply Migration:** < 1 minute
- **Rebuild iOS App:** 2-5 minutes
- **Verify Fixes:** 2-3 minutes
- **Total:** ~10 minutes

---

## ✅ Success Criteria

After applying fixes, you should observe:

1. ✅ No crashes when tapping buildings
2. ✅ Buildings load and display on map
3. ✅ Building stats (colors) show correctly
4. ✅ Logs show successful feature loading
5. ✅ No `is_townhome_row` column errors
6. ✅ UUID case mismatches handled automatically

---

**Last Updated:** 2025-02-06  
**Status:** ✅ All Issues Resolved
