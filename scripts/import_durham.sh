#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   export DATABASE_URL="postgresql://postgres:<PW>@db.<ref>.supabase.co:5432/postgres"
#   ./scripts/import_durham.sh "/absolute/path/to/Durham_Civic_Addresses.csv"
#
# Notes:
# - Disables statement_timeout for this session.
# - Imports Durham CSV into staging, then UPSERTs into addresses_master.
# - If addresses_master is empty, seeds it from oda_addresses once.

CSV_PATH="${1:-}"
DB_URL="${DATABASE_URL:-}"

if [[ -z "${CSV_PATH}" || -z "${DB_URL}" ]]; then
  echo "Usage: $0 \"/path/to/Durham_Civic_Addresses.csv\" (and set DATABASE_URL)"
  exit 1
fi
if [[ ! -f "${CSV_PATH}" ]]; then
  echo "ERROR: CSV not found: ${CSV_PATH}"
  exit 1
fi

echo "🔗 DB: ${DB_URL}"
echo "📄 CSV: ${CSV_PATH}"
PSQL="psql \"${DB_URL}?options=-c%20statement_timeout%3D0\" -v ON_ERROR_STOP=1"

echo "🧩 Ensure PostGIS + master schema…"
${PSQL} <<'SQL'
create extension if not exists postgis;
create extension if not exists citext;

-- Unified master table (source-agnostic)
create table if not exists public.addresses_master (
  id            bigserial primary key,
  source        text not null,                    -- 'oda','durham_open','osm','user','fallback'
  source_id     text,
  full_address  text not null,
  street_number citext,
  street_name   citext not null,
  city          citext,
  province      text not null,
  postal_code     citext,
  geom          geometry(Point,4326),
  confidence    real default 0.90,                -- ODA ~0.90, Durham ~0.95, fallback ~0.70
  updated_at    timestamptz default now(),
  norm_key      citext generated always as
    (trim(both from upper(
      coalesce(street_number,'') || '|' ||
      coalesce(street_name,'')   || '|' ||
      coalesce(city,'')          || '|' ||
      coalesce(province,'')      || '|' ||
      coalesce(postal_code,'')
    ))) stored
);

create index if not exists idx_addr_geom      on public.addresses_master using gist (geom);
create index if not exists idx_addr_norm_key  on public.addresses_master (norm_key);
create index if not exists idx_addr_source    on public.addresses_master (source);

-- Durham staging (adjust columns here if needed)
drop table if exists public.stage_durham;
create table public.stage_durham (
  full_address text,
  street_no    text,
  street_name  text,
  city         text,
  postal_code  text,
  lon          double precision,
  lat          double precision,
  source_id    text
);
SQL

echo "⬆️  COPY Durham CSV -> staging"
${PSQL} -c "\copy public.stage_durham from '${CSV_PATH}' with (format csv, header true)";

echo "🌱 Seed master from ODA (one-time) if empty…"
${PSQL} <<'SQL'
do $$
begin
  if (select count(*) from public.addresses_master) = 0 then
    if exists (select 1 from information_schema.tables where table_name='oda_addresses') then
      insert into public.addresses_master
        (source, source_id, full_address, street_number, street_name, city, province, postal_code, geom, confidence)
      select
        'oda' as source,
        null as source_id,
        oa.full_address,
        oa.street_number,
        oa.street_name,
        oa.city,
        coalesce(oa.province,'ON'),
        oa.postal_code,
        oa.geom,
        0.90
      from public.oda_addresses oa;
    end if;
  end if;
end $$;
SQL

echo "🔀 Upsert Durham -> master with confidence precedence…"
${PSQL} <<'SQL'
insert into public.addresses_master
  (source, source_id, full_address, street_number, street_name, city, province, postal_code, geom, confidence)
select
  'durham_open' as source,
  sd.source_id,
  sd.full_address,
  sd.street_no,
  sd.street_name,
  sd.city,
  'ON' as province,
  sd.postal_code,
  case when sd.lat is not null and sd.lon is not null
       then ST_SetSRID(ST_MakePoint(sd.lon, sd.lat), 4326)
       else null end,
  0.95 as confidence
from public.stage_durham sd
on conflict (norm_key) do update
  set geom        = case when excluded.geom is not null and addresses_master.geom is null
                         then excluded.geom else addresses_master.geom end,
      full_address = coalesce(addresses_master.full_address, excluded.full_address),
      postal_code  = coalesce(addresses_master.postal_code,  excluded.postal_code),
      confidence   = greatest(addresses_master.confidence, excluded.confidence),
      updated_at   = now();

analyze public.addresses_master;
SQL

echo "✅ Durham import complete."







