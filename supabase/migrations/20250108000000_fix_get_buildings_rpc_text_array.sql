-- Fix get_buildings_by_address_ids to accept text[] instead of UUID[]
-- This allows Supabase Swift client to pass string arrays without encoding issues

-- Drop and recreate function with text[] parameter
DROP FUNCTION IF EXISTS public.get_buildings_by_address_ids(UUID[]);

CREATE OR REPLACE FUNCTION public.get_buildings_by_address_ids(p_address_ids text[])
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(
      jsonb_agg(bp.geom) FILTER (WHERE bp.geom IS NOT NULL),
      '[]'::jsonb
    )
  )
  FROM public.building_polygons bp
  WHERE bp.address_id = ANY (SELECT unnest(p_address_ids)::uuid)
    AND bp.geom IS NOT NULL;
$$;

-- Grant execute on updated function
GRANT EXECUTE ON FUNCTION public.get_buildings_by_address_ids(text[]) TO authenticated;

-- Update comment
COMMENT ON FUNCTION public.get_buildings_by_address_ids(text[]) IS 'Returns GeoJSON FeatureCollection of building polygons for given address IDs (as text[]) from building_polygons table';

