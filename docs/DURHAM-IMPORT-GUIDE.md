# 🧩 Durham Civic Address Import — Overlap-Safe Merge

## Current Status
✅ **ODA Data**: 4,033,020 addresses imported  
⏳ **Durham Data**: Ready for import when CSV is available

## When You Have Durham_Civic_Addresses.csv

### Option 1: Simple Script (Recommended)
```bash
export DATABASE_URL="postgresql://postgres:nrHZPmg85EXt3VsH@db.kfnsnwqylsdsbgnwgxva.supabase.co:5432/postgres"
./scripts/import_durham_simple.sh "/path/to/Durham_Civic_Addresses.csv"
```

### Option 2: Manual SQL
```bash
# 1. Create staging table
psql "$DATABASE_URL" -c "DROP TABLE IF EXISTS durham_staging_raw; CREATE TABLE durham_staging_raw ( full_address text, street_number text, street_name text, city text, postal_code text, latitude double precision, longitude double precision );"

# 2. Import CSV
psql "$DATABASE_URL" -c "\copy durham_staging_raw FROM '/path/to/Durham_Civic_Addresses.csv' WITH (FORMAT csv, HEADER true);"

# 3. Merge with deduplication
psql "$DATABASE_URL" -f supabase/sql/durham_import.sql
```

## Expected CSV Headers
The script expects these columns in your Durham CSV:
- `full_address`
- `street_number` 
- `street_name`
- `city`
- `postal_code`
- `latitude`
- `longitude`

## Deduplication Logic
The import will skip addresses that already exist based on:
1. **Exact full address match** (case-insensitive)
2. **Street number + street name + city match**

## Confidence Scoring
- **Durham**: 0.95 (highest confidence)
- **ODA**: 0.90 (existing data)
- **Fallback**: 0.70 (for future sources)

## After Import
Your unified address system will have:
- **Best-record view**: `addresses_best` shows highest quality record per address
- **Unified queries**: `fn_addr_nearest()` and `fn_addr_same_street()` work across all sources
- **Source tracking**: Each address shows whether it came from ODA, Durham, etc.

## Testing
```sql
-- Check data sources
SELECT source, COUNT(*) FROM addresses_master GROUP BY source;

-- Test nearest addresses
SELECT * FROM fn_addr_nearest(-78.6224, 43.9878, 5);

-- Test same street
SELECT * FROM fn_addr_same_street('Main Street', 'Orono', -78.6224, 43.9878, 3);
```







