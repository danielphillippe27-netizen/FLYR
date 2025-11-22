-- Backfill geom_geom column from existing geom JSONB
-- This populates the PostGIS geometry column from stored GeoJSON Features

UPDATE building_polygons
SET geom_geom = ST_Force2D(
  ST_Multi(
    ST_SetSRID(
      ST_GeomFromGeoJSON((geom->>'geometry')::text),
      4326
    )
  )
)
WHERE geom_geom IS NULL
  AND geom IS NOT NULL
  AND geom ? 'geometry'
  AND geom->>'geometry' IS NOT NULL;

-- Sanity check
SELECT
  COUNT(*) AS total,
  COUNT(geom_geom) AS with_geom,
  COUNT(*) - COUNT(geom_geom) AS missing_geom
FROM building_polygons;






