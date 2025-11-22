#!/usr/bin/env bash
set -euo pipefail

# Colors
ok()    { echo -e "\033[32m$*\033[0m"; }
warn()  { echo -e "\033[33m$*\033[0m"; }
err()   { echo -e "\033[31m$*\033[0m"; }

# Require supabase CLI + psql
command -v supabase >/dev/null || { err "supabase CLI not found. Install via: brew install supabase/tap/supabase"; exit 1; }
command -v psql >/dev/null || { err "psql not found. Install via: brew install libpq && brew link --force libpq"; exit 1; }

DBURL="$(supabase db show-connection-string)"
[ -z "$DBURL" ] && { err "Could not get DB connection string. Run: supabase login"; exit 1; }

ok "Using DB: $DBURL"

# Ensure schema objects
ok "Ensuring PostGIS + unified table…"
psql "$DBURL" <<'SQL'
create extension if not exists postgis;

create table if not exists public.oda_addresses (
  id            bigserial primary key,
  province      text not null,
  full_address  text not null,
  street_number text,
  street_name   text not null,
  city          text,
  postal_code   text,
  latitude      double precision,
  longitude     double precision,
  geom          geography(Point,4326),
  created_at    timestamptz default now()
);

create index if not exists idx_oda_geom         on public.oda_addresses using gist (geom);
create index if not exists idx_oda_province     on public.oda_addresses (province);
create index if not exists idx_oda_city_upper   on public.oda_addresses (upper(city));
create index if not exists idx_oda_street_upper on public.oda_addresses (upper(street_name));

drop table if exists public.oda_staging_raw;
create table public.oda_staging_raw(
  full_address  text,
  street_number text,
  street_name   text,
  city          text,
  postal_code   text,
  latitude      double precision,
  longitude     double precision
);
SQL

ok "Ready. Starting CSV imports…"

shopt -s nullglob
for csv in ODA_*_v1.csv; do
  base="$(basename "$csv")"
  # province code is the middle token: ODA_[XX]_v1.csv
  prov="$(echo "$base" | sed -E 's/^ODA_([A-Z]{2})_v1\.csv$/\1/')"

  if [[ ! "$prov" =~ ^[A-Z]{2}$ ]]; then
    warn "Skipping $base (cannot infer province code)"
    continue
  fi

  done_marker=".${base}.done"
  if [[ -f "$done_marker" ]]; then
    warn "Skipping $base (already imported)"
    continue
  fi

  ok "Importing $base (province=$prov)…"

  # Clear staging and load
  psql "$DBURL" -c "truncate table public.oda_staging_raw;"
  # Adjust columns here if your CSV headers differ
  psql "$DBURL" -c "\copy public.oda_staging_raw FROM '$csv' CSV HEADER"

  # Move into unified table and build geom
  psql "$DBURL" <<SQL
insert into public.oda_addresses
  (province, full_address, street_number, street_name, city, postal_code, latitude, longitude, geom)
select
  '$prov',
  full_address, street_number, street_name, city, postal_code, latitude, longitude,
  case
    when latitude is not null and longitude is not null
    then ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
    else null
  end
from public.oda_staging_raw;

analyze public.oda_addresses;
SQL

  touch "$done_marker"
  ok "Completed $base"
done

ok "All CSVs processed."







