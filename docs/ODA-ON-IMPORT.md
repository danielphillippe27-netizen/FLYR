# Ontario ODA Import

## Prereqs
- Postgres (Supabase) URL
- `psql` and `python3` available

```bash
export DATABASE_URL="postgresql://postgres:<PASSWORD>@db.<PROJECT>.supabase.co:5432/postgres"
```

## Run
```bash
chmod +x scripts/import_oda_on.sh
./scripts/import_oda_on.sh ~/Desktop/FLYR/ODA_ON_v1.csv
```

The script:
- Disables statement timeouts
- Splits large CSVs into ~200k-row parts if needed
- Loads to `oda_staging_raw`
- Inserts into `oda_addresses` with geom (SRID 4326)
- Creates indexes + ANALYZE
- Prints quick sanity counts

## Query helpers

```bash
psql "$DATABASE_URL" -f supabase/sql/oda_queries.sql
```

### Examples:
```sql
select * from public.fn_oda_on_nearest(-78.6224, 43.9878, 25);
select * from public.fn_oda_on_same_street('MAIN', 'ORONO', -78.6224, 43.9878, 100);
```







