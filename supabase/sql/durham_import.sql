-- Durham Civic Address Import — Overlap-Safe Merge
-- Run this when you have Durham_Civic_Addresses.csv

-- 1️⃣ Create a staging table
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

-- 2️⃣ Import CSV (adjust path as needed)
-- \copy durham_staging_raw FROM '~/Desktop/FLYR/Durham_Civic_Addresses.csv' WITH (FORMAT csv, HEADER true);

-- 3️⃣ Insert into master table with deduplication
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

-- 4️⃣ Analyze for performance
ANALYZE addresses_master;

-- 5️⃣ Check results
SELECT 
  source,
  COUNT(*) as count,
  COUNT(geom) as with_geometry
FROM addresses_master 
GROUP BY source;







