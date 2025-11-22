-- Add geom_geom column for PostGIS geometry (MULTIPOLYGON, 4326)
-- This allows spatial queries and indexing on building polygons

-- Add geom_geom column
ALTER TABLE public.building_polygons
  ADD COLUMN IF NOT EXISTS geom_geom GEOMETRY(MultiPolygon, 4326);

-- Create index on geometry column for spatial queries
CREATE INDEX IF NOT EXISTS idx_building_polygons_geom_geom 
  ON public.building_polygons USING GIST(geom_geom);

-- RPC function to upsert with geometry conversion
-- Converts GeoJSON geometry to PostGIS MultiPolygon and stores both JSONB and geometry
CREATE OR REPLACE FUNCTION public.fn_upsert_building_polygon(
  p_address_id uuid,
  p_geom_json jsonb
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO building_polygons (address_id, geom, geom_geom, area_m2, source)
  VALUES (
    p_address_id,
    p_geom_json,
    ST_Force2D(ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(p_geom_json->>'geometry'), 4326))),
    COALESCE(
      (p_geom_json->'properties'->>'area_m2')::double precision,
      (SELECT ST_Area(ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON(p_geom_json->>'geometry'), 4326), 3857)))
    ),
    COALESCE((p_geom_json->'properties'->>'source')::text, 'mapbox_mvt')
  )
  ON CONFLICT (address_id) DO UPDATE
  SET 
    geom = excluded.geom,
    geom_geom = excluded.geom_geom,
    area_m2 = excluded.area_m2,
    source = excluded.source,
    updated_at = now();
$$;

-- Grant execute permission to service_role (Edge Function uses service role)
GRANT EXECUTE ON FUNCTION public.fn_upsert_building_polygon(uuid, jsonb) TO service_role;

-- Add comment
COMMENT ON FUNCTION public.fn_upsert_building_polygon(uuid, jsonb) IS 
  'Upserts building polygon with both JSONB geom and PostGIS geom_geom columns. Converts GeoJSON geometry to MultiPolygon SRID 4326.';






