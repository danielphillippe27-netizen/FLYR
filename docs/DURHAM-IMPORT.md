# Durham Import

## Prereqs
```bash
export DATABASE_URL="postgresql://postgres:<PW>@db.<ref>.supabase.co:5432/postgres"
```

## Import
```bash
./scripts/import_durham.sh "/absolute/path/Durham_Civic_Addresses.csv"
```

- Imports into `stage_durham`
- Seeds `addresses_master` from `oda_addresses` once (if empty)
- UPSERTs Durham rows with confidence=0.95
- Dedupes via `norm_key` (street_no|street_name|city|province|postal_code)

## Query
```bash
psql "$DATABASE_URL" -f supabase/sql/addresses_best.sql
psql "$DATABASE_URL" -f supabase/sql/addresses_functions.sql
```

### Examples:
```sql
select * from public.fn_addr_nearest(-78.6224, 43.9878, 25);
select * from public.fn_addr_same_street('MAIN','ORONO',-78.6224,43.9878,200);
```







