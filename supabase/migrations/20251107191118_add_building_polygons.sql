-- Building Polygons Migration for Pro Mode Tilequery
-- Creates building_polygons table for caching Mapbox Tilequery results
-- References campaign_addresses.id directly (FK)

-- Enable PostGIS if not already enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create building_polygons table
CREATE TABLE IF NOT EXISTS public.building_polygons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id UUID UNIQUE NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'mapbox_tilequery',
  geom JSONB NOT NULL, -- GeoJSON Feature with Polygon/MultiPolygon
  area_m2 DOUBLE PRECISION NOT NULL,
  centroid_lnglat GEOGRAPHY(Point,4326),
  bbox JSONB, -- {minLng, minLat, maxLng, maxLat}
  properties JSONB, -- raw Mapbox properties
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS uq_building_polygons_address_id 
  ON public.building_polygons(address_id);

CREATE INDEX IF NOT EXISTS idx_building_polygons_geom 
  ON public.building_polygons USING GIN(geom);

CREATE INDEX IF NOT EXISTS idx_building_polygons_area_m2 
  ON public.building_polygons(area_m2);

-- Enable RLS
ALTER TABLE public.building_polygons ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Allow SELECT for authenticated users
DROP POLICY IF EXISTS "building_polygons_select_authenticated" ON public.building_polygons;
CREATE POLICY "building_polygons_select_authenticated"
  ON public.building_polygons
  FOR SELECT
  TO authenticated
  USING (true);

-- INSERT/UPDATE only via service role (Edge Function will use service role)
-- No policy for INSERT/UPDATE by authenticated - only service role can write
-- This ensures only Edge Function can upsert polygons

-- Grant permissions
GRANT SELECT ON public.building_polygons TO authenticated;
-- INSERT/UPDATE only via service role (no grant to authenticated)

-- Update get_buildings_by_address_ids to query building_polygons table
CREATE OR REPLACE FUNCTION public.get_buildings_by_address_ids(p_address_ids UUID[])
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'type', 'Feature',
          'geometry', bp.geom->'geometry',
          'properties', jsonb_build_object(
            'address_id', bp.address_id::text,
            'source', bp.source,
            'area_m2', bp.area_m2,
            'selection', COALESCE(bp.properties->>'selection', 'unknown')
          ) || COALESCE(bp.properties, '{}'::jsonb)
        )
      ) FILTER (WHERE bp.geom IS NOT NULL),
      '[]'::jsonb
    )
  )
  FROM public.building_polygons bp
  WHERE bp.address_id = ANY(p_address_ids)
    AND bp.geom IS NOT NULL;
$$;

-- Grant execute on updated function
GRANT EXECUTE ON FUNCTION public.get_buildings_by_address_ids(UUID[]) TO authenticated;

-- Add comment
COMMENT ON TABLE public.building_polygons IS 'Cached building polygons from Mapbox Tilequery API, keyed by campaign_addresses.id';
COMMENT ON FUNCTION public.get_buildings_by_address_ids(UUID[]) IS 'Returns GeoJSON FeatureCollection of building polygons for given address IDs from building_polygons table';

