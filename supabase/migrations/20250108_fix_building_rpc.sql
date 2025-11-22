-- Fix get_buildings_by_address_ids RPC function
-- Drop text[] overload and recreate uuid[] version returning explicit table columns
-- This allows iOS client to decode rows directly instead of expecting JSONB FeatureCollection

-- 1) Drop the text[] overload if present
DROP FUNCTION IF EXISTS public.get_buildings_by_address_ids(p_address_ids text[]);

-- 2) Recreate the uuid[] version (idempotent) with explicit return columns
CREATE OR REPLACE FUNCTION public.get_buildings_by_address_ids(p_address_ids uuid[])
RETURNS TABLE (
  address_id uuid,
  geom_geom geometry(MultiPolygon, 4326),
  geom jsonb
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    bp.address_id,
    bp.geom_geom,
    bp.geom
  FROM building_polygons bp
  WHERE bp.address_id = ANY(p_address_ids)
$$;

-- 3) Execution grants
GRANT EXECUTE ON FUNCTION public.get_buildings_by_address_ids(uuid[]) TO anon, authenticated;

-- 4) Diagnostic view (optional but helpful)
CREATE OR REPLACE VIEW public.v_campaign_polygon_counts AS
SELECT
  ca.campaign_id,
  COUNT(bp.address_id) AS polys
FROM campaign_addresses ca
LEFT JOIN building_polygons bp ON bp.address_id = ca.id
GROUP BY ca.campaign_id;

-- Grant select on diagnostic view
GRANT SELECT ON public.v_campaign_polygon_counts TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.get_buildings_by_address_ids(uuid[]) IS 
  'Returns table with address_id, geom_geom (PostGIS MultiPolygon), and geom (JSONB) for given address IDs';






