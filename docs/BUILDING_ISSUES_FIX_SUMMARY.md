# Building Issues Fix Summary

**Date:** 2025-02-06  
**Author:** AI Assistant  
**Status:** ✅ Complete

## Overview

This document summarizes the fixes for three critical issues affecting the building data flow in the iOS app:

1. **Crash on Building Tap** - JSON serialization crash when tapping buildings
2. **Missing Database Column** - `is_townhome_row` column not found in RPC functions
3. **Building Polygon Loading Failure** - Empty responses due to UUID case sensitivity

---

## Issue 1: Crash on Building Tap (MapLayerManager.swift)

### Problem
When tapping a building on the map, the app crashed at line 470:
```swift
let data = try? JSONSerialization.data(withJSONObject: properties)
```

**Root Cause:** Feature properties contained UUID objects instead of strings. The `try?` wasn't preventing crashes (likely Objective-C exceptions or memory issues).

### Solution

**Created:** `FLYR/Services/SafeJSON.swift`
- Implements `SafeJSON.sanitize()` method to recursively convert non-JSON types to strings
- Handles UUIDs, Dates, URLs, Data, custom objects
- Validates with `JSONSerialization.isValidJSONObject()` before attempting serialization

**Modified:** `FLYR/Services/MapLayerManager.swift`
- Replaced direct `JSONSerialization.data(withJSONObject:)` with `SafeJSON.data(from:)`
- Added comprehensive error logging with diagnostic info
- Graceful failure - returns `nil` instead of crashing
- Logs raw properties and decoded JSON for debugging

### Key Features
- ✅ Recursive sanitization for nested objects
- ✅ Handles UUID, Date, URL, Data, CLLocationCoordinate2D
- ✅ Defensive validation before serialization
- ✅ Detailed error logging for debugging

---

## Issue 2: Missing Database Column

### Problem
Error log: `column b.is_townhome_row does not exist` in RPC function `rpc_get_campaign_features`

**Root Cause:** The `buildings` table was created with the `is_townhome_row` column in migration `20250206000000_create_building_tables.sql`, but older RPC functions or incomplete migrations might not have the column.

### Solution

**Created:** `supabase/migrations/20250206000004_fix_building_rpc_issues.sql`

1. **Idempotent Column Addition**
   ```sql
   ALTER TABLE public.buildings 
   ADD COLUMN IF NOT EXISTS is_townhome_row BOOLEAN DEFAULT false;
   ```

2. **Fixed RPC Functions**
   - `rpc_get_buildings_in_bbox` - Added defensive COALESCE and proper column references
   - `rpc_get_campaign_full_features` - Fixed to handle NULL values gracefully

3. **Added Diagnostic Function**
   ```sql
   CREATE FUNCTION debug_building_data(p_campaign_id uuid)
   ```
   - Returns building counts, link counts, stats counts
   - Sample GERS IDs for debugging

### Key Features
- ✅ Idempotent migration (safe to run multiple times)
- ✅ Defensive NULL handling in all RPC functions
- ✅ Diagnostic tools for troubleshooting
- ✅ Proper grants and permissions

---

## Issue 3: Building Polygon Loading Failure

### Problem
Weird behavior:
- MVT decode endpoint returns: `✅ [BUILDINGS] Chunk processed: 22/22 matched`
- But RPC call returns: `🔎 [RPC RAW] [] (0 features)`

**Root Cause:** ID casing mismatch
- Request sends uppercase UUIDs: `5699170A-42BB...`
- Database stores lowercase UUIDs
- UUID comparisons were case-sensitive

### Solution

**SQL Migration:** `20250206000004_fix_building_rpc_issues.sql`

1. **Case-Insensitive UUID Joins**
   ```sql
   LEFT JOIN public.building_stats s 
   ON LOWER(b.gers_id::text) = LOWER(s.gers_id::text)
   ```

2. **Helper Function**
   ```sql
   CREATE FUNCTION uuid_lower(input_uuid uuid) RETURNS uuid
   ```

3. **Updated Index for Performance**
   ```sql
   CREATE INDEX idx_building_stats_gers_id_lower 
   ON building_stats(LOWER(gers_id::text))
   ```

**Swift Changes:**

**Modified:** `FLYR/Feautures/Campaigns/API/BuildingsAPI.swift`
- Added defensive empty response handling
- Enhanced logging with diagnostic info
- Sample address ID logging
- Warnings for unexpected empty results
- Diagnostic suggestions for troubleshooting

**Modified:** `FLYR/Services/MapFeaturesService.swift`
- UUID format validation before RPC calls
- Empty response detection
- Raw response logging (first 500 chars)
- Graceful fallback to empty collections on errors
- Separate handling for DecodingError vs other errors

### Key Features
- ✅ Case-insensitive UUID comparisons in all joins
- ✅ Defensive checks for empty responses
- ✅ Comprehensive diagnostic logging
- ✅ Performance-optimized indexes
- ✅ Graceful error handling with fallbacks

---

## Files Modified

### Swift Files
1. `FLYR/Services/SafeJSON.swift` (NEW)
2. `FLYR/Services/MapLayerManager.swift`
3. `FLYR/Feautures/Campaigns/API/BuildingsAPI.swift`
4. `FLYR/Services/MapFeaturesService.swift`

### SQL Migrations
1. `supabase/migrations/20250206000004_fix_building_rpc_issues.sql` (NEW)

---

## Testing Checklist

### Issue 1: JSON Serialization
- [ ] Tap on buildings with UUID properties
- [ ] Tap on buildings with Date properties
- [ ] Tap on buildings with URL properties
- [ ] Verify no crashes occur
- [ ] Check logs for proper sanitization messages

### Issue 2: Database Column
- [ ] Run migration: `20250206000004_fix_building_rpc_issues.sql`
- [ ] Verify `is_townhome_row` column exists: `SELECT is_townhome_row FROM buildings LIMIT 1`
- [ ] Call `rpc_get_campaign_full_features` and verify no column errors
- [ ] Call `debug_building_data(campaign_id)` to verify data integrity

### Issue 3: UUID Case Sensitivity
- [ ] Test with uppercase UUIDs in requests
- [ ] Test with lowercase UUIDs in database
- [ ] Verify building stats join works correctly
- [ ] Check that RPC returns features when MVT decode finds matches
- [ ] Monitor logs for diagnostic warnings

---

## Migration Instructions

### Step 1: Run SQL Migration
```bash
cd /Users/danielphillippe/Desktop/FLYR\ IOS
supabase db push
```

Or manually run:
```sql
\i supabase/migrations/20250206000004_fix_building_rpc_issues.sql
```

### Step 2: Build iOS App
1. Open project in Xcode
2. Add `SafeJSON.swift` to the project if not already included
3. Clean build folder (Cmd+Shift+K)
4. Build and run (Cmd+R)

### Step 3: Verify Fixes
1. Open app and navigate to a campaign map
2. Tap on a building to verify no crash
3. Check that building polygons load correctly
4. Monitor Xcode console for diagnostic logs

---

## Diagnostic Commands

### Check Building Data Integrity
```sql
SELECT * FROM debug_building_data('YOUR_CAMPAIGN_ID');
```

### Check UUID Case Issues
```sql
-- Check if UUIDs are mixed case
SELECT gers_id, LOWER(gers_id::text) as lower_gers_id
FROM buildings 
WHERE campaign_id = 'YOUR_CAMPAIGN_ID'
LIMIT 10;

-- Check stats join
SELECT 
  b.gers_id as building_gers_id,
  s.gers_id as stats_gers_id,
  b.gers_id = s.gers_id as exact_match,
  LOWER(b.gers_id::text) = LOWER(s.gers_id::text) as case_insensitive_match
FROM buildings b
LEFT JOIN building_stats s ON b.gers_id = s.gers_id
WHERE b.campaign_id = 'YOUR_CAMPAIGN_ID'
LIMIT 10;
```

### Check Column Existence
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'buildings' 
AND column_name = 'is_townhome_row';
```

---

## Performance Considerations

1. **Case-Insensitive Index:** The new index on `LOWER(gers_id::text)` ensures fast lookups despite case conversion.

2. **SafeJSON Overhead:** Minimal - only used on tap events, not in hot paths.

3. **Defensive Logging:** Only enabled in debug builds. Consider adding compile-time flags for production.

---

## Future Improvements

1. **Normalize UUID Storage:** Consider storing all UUIDs in lowercase at insert time to avoid case conversion overhead.

2. **PreFlight Validation:** Add UUID validation in Swift before sending to backend.

3. **Monitoring:** Add analytics to track:
   - How often SafeJSON sanitization is needed
   - Frequency of empty RPC responses
   - UUID case mismatch occurrences

4. **Error Recovery:** Consider automatic retry logic for failed building fetches.

---

## Related Documentation

- [AI_CONTEXT_DB_SCHEMA.md](./AI_CONTEXT_DB_SCHEMA.md) - Database schema reference
- [AI_CONTEXT_IOS_ARCH.md](./AI_CONTEXT_IOS_ARCH.md) - iOS architecture overview
- [LINKED_HOMES_FEATURE.md](./LINKED_HOMES_FEATURE.md) - Linked homes feature documentation

---

## Support

If issues persist after applying these fixes:

1. Check Xcode console for diagnostic logs (prefixed with 🔍)
2. Run diagnostic SQL commands above
3. Verify migration was applied: `SELECT * FROM _migrations ORDER BY created_at DESC`
4. Check Supabase logs in dashboard for Edge Function errors
