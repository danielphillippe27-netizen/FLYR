#!/usr/bin/env bash
set -euo pipefail

# Durham Civic Address Import — Overlap-Safe Merge
# Usage: ./scripts/import_durham_simple.sh "/path/to/Durham_Civic_Addresses.csv"

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

echo "🧩 Creating staging table…"
psql "$DATABASE_URL" <<'SQL'
DROP TABLE IF EXISTS durham_staging_raw;
CREATE TABLE durham_staging_raw (
  full_address  text,
  street_number text,
  street_name   text,
  city          text,
  postal_code   text,
  latitude      double precision,
  longitude     double precision
);
SQL

echo "⬆️  Importing Durham CSV…"
psql "$DATABASE_URL" -c "\copy durham_staging_raw FROM '${CSV_PATH}' WITH (FORMAT csv, HEADER true);"

echo "🔀 Merging into addresses_master with deduplication…"
psql "$DATABASE_URL" <<'SQL'
set statement_timeout = 0;

INSERT INTO addresses_master (
  source,
  full_address,
  street_number,
  street_name,
  city,
  province,
  postal_code,
  geom,
  confidence
)
SELECT
  'durham_open' AS source,
  d.full_address,
  d.street_number,
  d.street_name,
  d.city,
  'ON' AS province,
  d.postal_code,
  ST_SetSRID(ST_MakePoint(d.longitude, d.latitude), 4326),
  0.95 AS confidence
FROM durham_staging_raw d
WHERE NOT EXISTS (
  SELECT 1
  FROM addresses_master m
  WHERE lower(trim(m.full_address)) = lower(trim(d.full_address))
    OR (m.street_number = d.street_number 
        AND m.street_name = d.street_name 
        AND m.city = d.city)
);

ANALYZE addresses_master;
SQL

echo "📊 Checking results…"
psql "$DATABASE_URL" -c "
SELECT 
  source,
  COUNT(*) as count,
  COUNT(geom) as with_geometry
FROM addresses_master 
GROUP BY source
ORDER BY source;
"

echo "✅ Durham import complete!"







