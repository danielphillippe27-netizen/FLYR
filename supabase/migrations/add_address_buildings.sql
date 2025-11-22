-- Pro Mode Building Polygons Migration
-- Adds building polygon caching for campaign addresses

-- A) Helper function for deterministic address key
CREATE OR REPLACE FUNCTION public.addr_key(p_formatted TEXT, p_postal TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE RETURNS NULL ON NULL INPUT AS $$
  SELECT md5(
    regexp_replace(lower(coalesce(p_formatted,'')), '\s+', ' ', 'g') || '|' ||
    regexp_replace(upper(coalesce(p_postal,'')), '\s+', '', 'g')
  );
$$;

-- B) Ensure PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- C) Create address buildings cache table
CREATE TABLE IF NOT EXISTS public.address_buildings (
  address_id UUID,                             -- optional for future FK
  address_key TEXT UNIQUE NOT NULL,            -- deterministic key for caching
  building_id TEXT,
  building_source TEXT DEFAULT 'mapbox.buildings',
  building_geom GEOMETRY(Polygon, 4326),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add columns if upgrading existing table
ALTER TABLE public.address_buildings
  ADD COLUMN IF NOT EXISTS address_key TEXT,
  ADD COLUMN IF NOT EXISTS building_id TEXT,
  ADD COLUMN IF NOT EXISTS building_source TEXT DEFAULT 'mapbox.buildings',
  ADD COLUMN IF NOT EXISTS building_geom GEOMETRY(Polygon, 4326),
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS uq_address_buildings_key 
  ON public.address_buildings(address_key);
CREATE INDEX IF NOT EXISTS idx_address_buildings_geom 
  ON public.address_buildings USING GIST(building_geom);

-- D) RPC: Upsert building by formatted address + postal
CREATE OR REPLACE FUNCTION public.upsert_address_building_by_formatted(
  p_formatted TEXT,
  p_postal TEXT,
  p_building_id TEXT,
  p_building_source TEXT,
  p_geojson JSONB
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  k TEXT := public.addr_key(p_formatted, p_postal);
BEGIN
  INSERT INTO public.address_buildings(address_key, building_id, building_source, building_geom)
  VALUES (
    k, 
    p_building_id, 
    COALESCE(p_building_source, 'mapbox.buildings'),
    ST_SetSRID(ST_GeomFromGeoJSON(p_geojson->>'geometry'), 4326)
  )
  ON CONFLICT(address_key) DO UPDATE
    SET building_id = EXCLUDED.building_id,
        building_source = EXCLUDED.building_source,
        building_geom = EXCLUDED.building_geom,
        updated_at = now();
END $$;

-- E) RPC: Get buildings GeoJSON FeatureCollection for campaign
CREATE OR REPLACE FUNCTION public.get_campaign_buildings_geojson(p_campaign_id UUID)
RETURNS JSONB LANGUAGE sql STABLE AS $$
WITH ca AS (
  SELECT id AS campaign_address_id, formatted, postal_code
  FROM public.campaign_addresses
  WHERE campaign_id = p_campaign_id
),
joined AS (
  SELECT ca.campaign_address_id, ab.building_geom
  FROM ca
  JOIN public.address_buildings ab
    ON ab.address_key = public.addr_key(ca.formatted, ca.postal_code)
  WHERE ab.building_geom IS NOT NULL
)
SELECT jsonb_build_object(
  'type', 'FeatureCollection',
  'features', COALESCE(jsonb_agg(
    jsonb_build_object(
      'type', 'Feature',
      'geometry', ST_AsGeoJSON(building_geom)::jsonb,
      'properties', jsonb_build_object('campaign_address_id', campaign_address_id::text)
    )
  ), '[]'::jsonb)
) FROM joined;
$$;

-- F) RPC: Get buildings GeoJSON FeatureCollection by address IDs
CREATE OR REPLACE FUNCTION public.get_buildings_by_address_ids(p_address_ids UUID[])
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ca AS (
    SELECT id AS campaign_address_id, formatted, postal_code
    FROM public.campaign_addresses
    WHERE id = ANY(p_address_ids)
  ),
  joined AS (
    SELECT ca.campaign_address_id, ab.building_geom
    FROM ca
    JOIN public.address_buildings ab
      ON ab.address_key = public.addr_key(ca.formatted, ca.postal_code)
    WHERE ab.building_geom IS NOT NULL
  )
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'geometry', ST_AsGeoJSON(ST_Multi(joined.building_geom))::jsonb,
          'properties', jsonb_build_object(
            'campaign_address_id', joined.campaign_address_id::text
          )
        )
      ) FILTER (WHERE joined.building_geom IS NOT NULL),
      '[]'::jsonb
    )
  )
  FROM joined;
$$;

-- G) Wrapper: API-style name for get_buildings_by_address_ids
CREATE OR REPLACE FUNCTION public.api_get_buildings_by_address_ids(p_address_ids UUID[])
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_buildings_by_address_ids(p_address_ids);
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.addr_key(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_address_building_by_formatted(TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_campaign_buildings_geojson(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_buildings_by_address_ids(UUID[]) TO authenticated;

-- Lock down wrapper permissions (Supabase style)
REVOKE ALL ON FUNCTION public.api_get_buildings_by_address_ids(UUID[]) FROM public;
GRANT EXECUTE ON FUNCTION public.api_get_buildings_by_address_ids(UUID[]) TO authenticated;

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE ON public.address_buildings TO authenticated;
