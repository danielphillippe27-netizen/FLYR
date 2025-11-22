#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/import_oda_on.sh ~/Desktop/FLYR/ODA_ON_v1.csv
#
# Env:
#   DATABASE_URL must be set, e.g.:
#   export DATABASE_URL="postgresql://postgres:PW@db.xx.supabase.co:5432/postgres"
#
# Notes:
# - Disables statement timeout for the session
# - Splits large CSVs into ~200k-row parts to avoid timeouts
# - Loads into staging, then inserts into main table with geom
# - Builds indexes and ANALYZE

CSV_PATH="${1:-}"
DB_URL="${DATABASE_URL:-}"

if [[ -z "${CSV_PATH}" || -z "${DB_URL}" ]]; then
  echo "Usage: $0 /absolute/path/to/ODA_ON_v1.csv"
  echo "And set DATABASE_URL in your environment."
  exit 1
fi
if [[ ! -f "${CSV_PATH}" ]]; then
  echo "ERROR: CSV not found: ${CSV_PATH}"
  exit 1
fi

echo "🔗 DB: ${DB_URL}"
echo "📄 CSV: ${CSV_PATH}"
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

echo "🧩 Ensure PostGIS + tables…"
${PSQL} <<'SQL'
set statement_timeout = 0;
create extension if not exists postgis;

-- Main table for Ontario ODA
create table if not exists public.oda_addresses (
  id            bigserial primary key,
  full_address  text not null,
  street_number text,
  street_name   text not null,
  city          text,
  province      text not null,
  postal_code   text,
  geom          geometry(Point,4326),
  created_at    timestamptz default now()
);

-- Staging table matching ODA header for ON
drop table if exists public.oda_staging_raw;
create table public.oda_staging_raw (
  latitude      double precision,
  longitude     double precision,
  source_id     text,
  id            text,
  group_id      text,
  street_no     text,
  street        text,
  str_name      text,
  str_type      text,
  str_dir       text,
  unit          text,
  city          text,
  postal_code   text,
  full_addr     text,
  city_pcs      text,
  str_name_pcs  text,
  str_type_pcs  text,
  str_dir_pcs   text,
  csduid        text,
  csdname       text,
  pruid         text,
  provider      text
);
SQL

# Optionally split big CSVs
BYTES=$(stat -f%z "${CSV_PATH}" 2>/dev/null || stat -c%s "${CSV_PATH}")
PARTS_DIR="$(dirname "${CSV_PATH}")/ODA_ON_parts"
CSV_LIST=( "${CSV_PATH}" )

if [[ "${BYTES}" -gt 150000000 ]]; then
  echo "🪓 CSV >150MB — splitting into ~200k-row parts…"
  mkdir -p "${PARTS_DIR}"
  python3 - "${CSV_PATH}" "${PARTS_DIR}" <<'PY'
import csv, sys, os
src, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
rows_per = 200_000

with open(src, newline='') as f:
    reader = csv.reader(f)
    header = next(reader)
    
    part = 1
    current_file = None
    current_writer = None
    row_count = 0
    
    for row in reader:
        if row_count == 0 or row_count >= rows_per:
            if current_file:
                current_file.close()
            current_file = open(os.path.join(outdir, f'oda_on_{part:03d}.csv'), 'w', newline='')
            current_writer = csv.writer(current_file)
            current_writer.writerow(header)
            part += 1
            row_count = 0
        
        current_writer.writerow(row)
        row_count += 1
    
    if current_file:
        current_file.close()

print("OK")
PY
  CSV_LIST=( "${PARTS_DIR}/"*.csv )
fi

echo "⬆️  COPY CSV → staging…"
for PART in "${CSV_LIST[@]}"; do
  echo "   • ${PART}"
  ${PSQL} -c "\copy public.oda_staging_raw from '${PART}' with (format csv, header true);"
done

echo "🔀 Insert staging → main (province=ON) and build geom…"
${PSQL} <<'SQL'
set statement_timeout = 0;
insert into public.oda_addresses
  (full_address, street_number, street_name, city, province, postal_code, geom)
select
  full_addr,
  street_no,
  coalesce(street, concat_ws(' ', str_name, str_type, str_dir)),
  city,
  'ON',
  postal_code,
  case
    when latitude is not null and longitude is not null
    then ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
    else null
  end
from public.oda_staging_raw;

-- Indexes (safe to re-run)
create index if not exists idx_oda_geom         on public.oda_addresses using gist (geom);
create index if not exists idx_oda_province     on public.oda_addresses (province);
create index if not exists idx_oda_city_upper   on public.oda_addresses (upper(city));
create index if not exists idx_oda_street_upper on public.oda_addresses (upper(street_name));

analyze public.oda_addresses;

-- Quick sanity:
select 'rows_total' as k, count(*) from public.oda_addresses
union all
select 'rows_geom', count(*) from public.oda_addresses where geom is not null
union all
select 'rows_no_geom', count(*) from public.oda_addresses where geom is null;
SQL

echo "✅ Ontario ODA import complete."
