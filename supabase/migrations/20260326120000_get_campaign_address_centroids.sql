-- Map tab: one round-trip for pin placement (centroid of all address points per campaign).
-- SECURITY INVOKER + RLS on campaign_addresses scope rows to the caller.

CREATE OR REPLACE FUNCTION public.get_campaign_address_centroids()
RETURNS TABLE (campaign_id uuid, lat double precision, lon double precision)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT ca.campaign_id,
         ST_Y(ST_Centroid(ST_Collect(ca.geom::geometry)))::double precision AS lat,
         ST_X(ST_Centroid(ST_Collect(ca.geom::geometry)))::double precision AS lon
  FROM public.campaign_addresses ca
  GROUP BY ca.campaign_id;
$$;

COMMENT ON FUNCTION public.get_campaign_address_centroids() IS
  'Returns geographic centroid (lat/lon) per campaign for map markers without loading full address lists.';

GRANT EXECUTE ON FUNCTION public.get_campaign_address_centroids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_campaign_address_centroids() TO service_role;
