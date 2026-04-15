-- Production repair bundle for drifted environments.
-- Safe to run multiple times (idempotent).
--
-- Fixes:
-- 1) sessions.path_geojson_normalized missing (PGRST204)
-- 2) get_campaign_address_centroids() missing (PGRST202)
-- 3) text = uuid policy mismatches on sessions/user_stats (42883)

-- 1) Ensure normalized path column exists on sessions
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS path_geojson_normalized TEXT;

COMMENT ON COLUMN public.sessions.path_geojson_normalized IS
  'Optional GeoJSON LineString of normalized breadcrumb trail (Pro GPS Normalization). When set, used for summary/share display; path_geojson remains raw.';

-- 2) Ensure centroid RPC exists for map markers
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

-- 3) Ensure sessions RLS compares user IDs as text to avoid uuid/text operator mismatch
DROP POLICY IF EXISTS "Users can read their own sessions" ON public.sessions;
CREATE POLICY "Users can read their own sessions"
    ON public.sessions
    FOR SELECT
    USING ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can insert their own sessions" ON public.sessions;
CREATE POLICY "Users can insert their own sessions"
    ON public.sessions
    FOR INSERT
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can update their own sessions" ON public.sessions;
CREATE POLICY "Users can update their own sessions"
    ON public.sessions
    FOR UPDATE
    USING ((user_id::text) = (auth.uid()::text))
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can delete their own sessions" ON public.sessions;
CREATE POLICY "Users can delete their own sessions"
    ON public.sessions
    FOR DELETE
    USING ((user_id::text) = (auth.uid()::text));

-- 4) Ensure user_stats RLS uses same cast logic
DROP POLICY IF EXISTS "user_stats_select_own" ON public.user_stats;
CREATE POLICY "user_stats_select_own"
    ON public.user_stats FOR SELECT TO authenticated
    USING ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "user_stats_insert_own" ON public.user_stats;
CREATE POLICY "user_stats_insert_own"
    ON public.user_stats FOR INSERT TO authenticated
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "user_stats_update_own" ON public.user_stats;
CREATE POLICY "user_stats_update_own"
    ON public.user_stats FOR UPDATE TO authenticated
    USING ((user_id::text) = (auth.uid()::text))
    WITH CHECK ((user_id::text) = (auth.uid()::text));
