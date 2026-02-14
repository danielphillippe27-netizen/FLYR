
# Load Walkway Data to Supabase

## Problem
The RPC functions query the `overture_transportation` table in Supabase, but it's likely **empty**.

## Solution

### Option 1: Quick SQL Load (Recommended)

Run this SQL in **Supabase SQL Editor**:

```sql
-- 1. Create the table if not exists
CREATE TABLE IF NOT EXISTS public.overture_transportation (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    gers_id text UNIQUE,
    class text,
    subclass text,
    geom geometry(LineString, 4326),
    created_at timestamptz DEFAULT now()
);

-- 2. Enable PostGIS if not already
CREATE EXTENSION IF NOT EXISTS postgis;

-- 3. Create spatial index
CREATE INDEX IF NOT EXISTS idx_transport_geom 
ON public.overture_transportation USING GIST (geom);

-- 4. Check if empty
SELECT COUNT(*) as current_count FROM overture_transportation;
```

### Option 2: Load from Overture S3 (Full Dataset)

```bash
# Export walkways to CSV
cd scripts
BBOX_WEST=-79.5 BBOX_EAST=-78.0 BBOX_SOUTH=43.5 BBOX_NORTH=44.2 \
npx tsx load-walk-network-to-supabase.ts --include-road-fallback

# This creates: data/walk_network.csv
```

Then load via Supabase Dashboard:
1. Go to **Table Editor** → **overture_transportation**
2. Click **Import Data**
3. Upload the CSV

### Option 3: Direct INSERT from S3 (Using DuckDB)

In Supabase SQL Editor:

```sql
-- Note: This requires pgduckdb extension or external processing
-- For now, use Option 1 or 2
```

## Verify Loading

After loading, test with:

```sql
-- Check counts
SELECT class, subclass, COUNT(*) 
FROM overture_transportation 
GROUP BY class, subclass;

-- Test RPC
SELECT * FROM find_nearest_walkway_segment_with_geom(-78.675, 43.928, 100);
```

## Expected Results

```
 class    | subclass  | count
----------+-----------+-------
 footway  | sidewalk  |  3172
 footway  | crosswalk |  1350
 footway  |           |  6182
 path     |           |  2449
 ...
```

## Then Re-Optimize Routes

After loading walkways, re-run route optimization and check browser console:

```
[StreetSideRoute] RPC Result: {
  walkwayFound: true,
  class: 'footway',
  subclass: 'sidewalk',
  hasGeom: true
}
```

**The routes should now snap to sidewalks!** 🚶‍♂️
