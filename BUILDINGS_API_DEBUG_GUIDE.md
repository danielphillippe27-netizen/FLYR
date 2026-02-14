# Buildings API Debug Guide

This guide helps you debug why the iOS app shows "No building polygons found for campaign" errors when the backend returns empty building snapshots.

## Quick Start

### Option 1: Bash Script (Simple)

```bash
# Test a specific campaign
./test_buildings_api.sh 6824DF05-1234-5678-9ABC-DEF012345678

# Test against local backend
./test_buildings_api.sh 6824DF05-1234-5678-9ABC-DEF012345678 http://localhost:3000
```

### Option 2: Python Script (Detailed)

```bash
# Basic test
python3 test_buildings_api.py 6824DF05-1234-5678-9ABC-DEF012345678

# Verbose output with full response
python3 test_buildings_api.py 6824DF05-1234-5678-9ABC-DEF012345678 --verbose

# Test local backend
python3 test_buildings_api.py 6824DF05-1234-5678-9ABC-DEF012345678 --base-url http://localhost:3000
```

## Understanding the Results

### Result Matrix

| Buildings | Roads | Meaning |
|-----------|-------|---------|
| ✅ Has features | ✅ Has features | **Normal** - Everything is working |
| ✅ Has features | ❌ 404 | **Normal** - Buildings work, roads optional |
| ❌ Empty | ✅ Has features | **Problem** - Buildings snapshot empty, roads OK |
| ❌ Empty | ❌ 404 | **Problem** - Campaign may not be provisioned |
| ❌ 404 | ❌ 404 | **Problem** - Campaign doesn't exist or not provisioned |

### Common Scenarios

#### Scenario 1: Buildings Empty, Roads Exist

**What it means:**
- The `campaign_snapshots` row EXISTS in Supabase
- The S3 bucket has snapshot files
- But the buildings file is empty or corrupted

**Check in Supabase:**
```sql
SELECT campaign_id, buildings_key, addresses_key, roads_key, created_at
FROM campaign_snapshots 
WHERE campaign_id = '6824DF05-...';
```

**Check S3 directly:**
```bash
# List files
aws s3 ls s3://flyr-snapshots/campaigns/6824DF05-.../

# Check buildings file size
aws s3 ls s3://flyr-snapshots/campaigns/6824DF05-.../buildings.geojson.gz

# Download and check content
aws s3 cp s3://flyr-snapshots/campaigns/6824DF05-.../buildings.geojson.gz - | \
  gunzip | jq '.features | length'
```

**Likely causes:**
1. Lambda query returned no results for the territory polygon
2. Territory boundary is in an area with no building data
3. S3 file was overwritten with empty content
4. Decompression error on backend

#### Scenario 2: Both Buildings and Roads Return 404

**What it means:**
- Campaign may not exist
- Campaign exists but has no snapshot metadata
- Campaign not yet provisioned

**Check in Supabase:**
```sql
-- Check if campaign exists
SELECT id, provision_status, territory_boundary IS NOT NULL as has_boundary
FROM campaigns 
WHERE id = '6824DF05-...';
```

**Likely causes:**
1. Wrong campaign ID
2. Campaign never provisioned (provision_status is NULL or 'pending')
3. Provision failed

**Fix:**
```bash
# Trigger provision
curl -X POST https://flyrpro.app/api/campaigns/provision \
  -H "Content-Type: application/json" \
  -d '{"campaign_id": "6824DF05-..."}'
```

#### Scenario 3: Buildings Empty, Roads 404

**What it means:**
- Snapshots table may exist but be incomplete
- Partial provisioning failure

**Likely causes:**
1. Provision partially succeeded (buildings written but no roads)
2. Roads are optional and weren't generated

### iOS Log Interpretation

When you see these logs in iOS:

```
[BUILDINGS] Snapshot request campaign=6824DF05-... url=... at=...
[BUILDINGS] Loaded 0 features from GET buildings API (S3 snapshot)
[BUILDINGS] snapshot_empty campaign=6824DF05-...
```

This confirms:
1. ✅ iOS is calling the correct API endpoint
2. ✅ Backend is responding with HTTP 200
3. ✅ Response is valid GeoJSON
4. ❌ But `features` array is empty

## Debugging Checklist

### Step 1: Verify Campaign Exists
```sql
SELECT id, name, provision_status, 
       territory_boundary IS NOT NULL as has_boundary,
       created_at
FROM campaigns 
WHERE id = 'YOUR_CAMPAIGN_ID';
```

Expected: `provision_status` = 'ready', `has_boundary` = true

### Step 2: Verify Snapshot Metadata
```sql
SELECT campaign_id, buildings_key, addresses_key, roads_key,
       building_count, address_count, created_at
FROM campaign_snapshots 
WHERE campaign_id = 'YOUR_CAMPAIGN_ID';
```

Expected: `buildings_key` is not null, `building_count` > 0

### Step 3: Check S3 Content
```bash
# Get the buildings key from step 2
aws s3 cp s3://flyr-snapshots/BUILDINGS_KEY_FROM_STEP_2 - | \
  gunzip | jq '{type: .type, feature_count: (.features | length)}'
```

Expected: `feature_count` > 0

### Step 4: Check Provision Logs
```sql
SELECT * FROM provision_logs 
WHERE campaign_id = 'YOUR_CAMPAIGN_ID' 
ORDER BY created_at DESC 
LIMIT 5;
```

Look for errors or incomplete provisions.

### Step 5: Verify Territory Boundary
```sql
-- Check if territory has buildings in Overture data
SELECT COUNT(*) 
FROM overture_buildings 
WHERE ST_Intersects(
    geometry, 
    (SELECT territory_boundary FROM campaigns WHERE id = 'YOUR_CAMPAIGN_ID')
);
```

If this returns 0, the territory is in an area with no building data.

## Quick Fixes

### Re-provision a Campaign

If the campaign exists but snapshots are corrupted:

```bash
curl -X POST https://flyrpro.app/api/campaigns/provision \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"campaign_id": "YOUR_CAMPAIGN_ID"}'
```

### Force Re-provision (Delete First)

```sql
-- Delete existing snapshots
DELETE FROM campaign_snapshots WHERE campaign_id = 'YOUR_CAMPAIGN_ID';

-- Reset provision status
UPDATE campaigns SET provision_status = NULL WHERE id = 'YOUR_CAMPAIGN_ID';
```

Then re-provision via API.

## Tools Reference

### Required Tools
- `curl` - HTTP requests (built-in on macOS/Linux)
- `jq` - JSON parsing (`brew install jq` on macOS)

### Optional Tools
- `aws-cli` - For direct S3 inspection
- `psql` - For direct database queries

## Files in This Directory

| File | Purpose |
|------|---------|
| `test_buildings_api.sh` | Bash script for quick API testing |
| `test_buildings_api.py` | Python script with detailed analysis |
| `BUILDINGS_API_DEBUG_GUIDE.md` | This guide |

## Need More Help?

If you've gone through this checklist and still have issues:

1. Save the output from the test script
2. Check the provision logs in Supabase
3. Verify the Lambda logs in CloudWatch
4. Compare with a known-good campaign ID

Common working campaign IDs can be found with:
```sql
SELECT c.id, c.name, cs.building_count
FROM campaigns c
JOIN campaign_snapshots cs ON c.id = cs.campaign_id
WHERE c.provision_status = 'ready'
  AND cs.building_count > 0
ORDER BY c.created_at DESC
LIMIT 5;
```
