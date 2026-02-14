-- =====================================================
-- iOS Map Features RPC Functions
-- 
-- These functions support the FLYR iOS app for querying
-- buildings, addresses, and roads from Supabase.
-- Mirrors the FLYR-PRO web app functionality.
--
-- RPC return shape: All campaign RPCs return a single jsonb object
--   { "type": "FeatureCollection", "features": [...] }
-- iOS client expects this object shape and supports a top-level array
-- fallback (empty [] or array of features) for robustness.
-- Geometry: Use ST_AsGeoJSON(geom, 6)::jsonb for GeoJSON (iOS decodes
-- Point, LineString, Polygon, MultiPolygon, MultiLineString).
-- =====================================================

-- =====================================================
-- 1. BUILDINGS RPC - Fetch buildings in bounding box
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_buildings_in_bbox(
    min_lon float,
    min_lat float,
    max_lon float,
    max_lat float,
    p_campaign_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    bbox geometry;
    result jsonb;
BEGIN
    bbox := ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326);

    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', b.id,
            'geometry', ST_AsGeoJSON(b.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', b.id,
                'building_id', b.id,
                'gers_id', b.gers_id,
                'height', COALESCE(b.height_m, b.height, 10),
                'height_m', COALESCE(b.height_m, b.height, 10),
                'min_height', 0,
                'is_townhome', COALESCE(b.is_townhome_row, false),
                'units_count', COALESCE(b.units_count, 0),
                'address_text', ca.formatted,
                'match_method', l.method,
                'feature_status', CASE WHEN l.id IS NOT NULL THEN 'matched' ELSE 'orphan_building' END,
                'status', COALESCE(
                    s.status,
                    CASE b.latest_status
                        WHEN 'interested' THEN 'visited'
                        WHEN 'default' THEN 'not_visited'
                        ELSE 'not_visited'
                    END
                ),
                'scans_today', COALESCE(s.scans_today, 0),
                'scans_total', COALESCE(s.scans_total, 0),
                'last_scan_seconds_ago', CASE
                    WHEN s.last_scan_at IS NOT NULL THEN extract(epoch from (now() - s.last_scan_at))
                    ELSE NULL
                END
            )
        ) AS feature
        FROM public.buildings b
        LEFT JOIN public.building_address_links l ON b.id = l.building_id AND l.campaign_id = b.campaign_id
        LEFT JOIN public.campaign_addresses ca ON l.address_id = ca.id
        LEFT JOIN public.building_stats s ON b.gers_id = s.gers_id
        WHERE b.geom && bbox
          AND ST_Intersects(b.geom, bbox)
          AND (p_campaign_id IS NULL OR b.campaign_id = p_campaign_id)
        LIMIT 2000
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_buildings_in_bbox(float, float, float, float, uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_buildings_in_bbox IS
'Returns GeoJSON FeatureCollection of buildings within a bounding box. Used by iOS app for viewport-based building queries.';

-- =====================================================
-- 2. ADDRESSES RPC - Fetch addresses in bounding box
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_addresses_in_bbox(
    min_lon float,
    min_lat float,
    max_lon float,
    max_lat float,
    p_campaign_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    bbox geometry;
    result jsonb;
BEGIN
    bbox := ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326);

    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', a.id,
            'geometry', ST_AsGeoJSON(a.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', a.id,
                'gers_id', a.gers_id,
                'house_number', a.house_number,
                'street_name', a.street_name,
                'postal_code', a.postal_code,
                'locality', a.locality,
                'formatted', a.formatted
            )
        ) AS feature
        FROM public.campaign_addresses a
        WHERE a.geom && bbox
          AND ST_Intersects(a.geom, bbox)
          AND (p_campaign_id IS NULL OR a.campaign_id = p_campaign_id)
        LIMIT 2000
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_addresses_in_bbox(float, float, float, float, uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_addresses_in_bbox IS
'Returns GeoJSON FeatureCollection of addresses within a bounding box. Used by iOS app for viewport-based address queries.';

-- =====================================================
-- 3. ROADS RPC - Fetch roads in bounding box
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_roads_in_bbox(
    min_lon float,
    min_lat float,
    max_lon float,
    max_lat float,
    p_campaign_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    bbox geometry;
    result jsonb;
BEGIN
    bbox := ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326);

    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', r.id,
            'geometry', ST_AsGeoJSON(r.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', r.id,
                'gers_id', r.gers_id,
                'class', r.road_class,
                'name', r.name
            )
        ) AS feature
        FROM public.roads r
        WHERE r.geom && bbox
          AND ST_Intersects(r.geom, bbox)
          AND (p_campaign_id IS NULL OR r.campaign_id = p_campaign_id)
        LIMIT 2000
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_roads_in_bbox(float, float, float, float, uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_roads_in_bbox IS
'Returns GeoJSON FeatureCollection of roads within a bounding box. Used by iOS app for viewport-based road queries.';

-- =====================================================
-- 4. CAMPAIGN FULL FEATURES - Fetch all campaign data
-- =====================================================

-- Note: This function may already exist from FLYR-PRO
-- Run this only if rpc_get_campaign_full_features doesn't exist

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'rpc_get_campaign_full_features'
    ) THEN
        EXECUTE $func$
            CREATE OR REPLACE FUNCTION public.rpc_get_campaign_full_features(
                p_campaign_id uuid
            ) RETURNS jsonb LANGUAGE plpgsql AS $inner$
            DECLARE
                result jsonb;
            BEGIN
                SELECT jsonb_build_object(
                    'type', 'FeatureCollection',
                    'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
                ) INTO result
                FROM (
                    SELECT jsonb_build_object(
                        'type', 'Feature',
                        'id', b.id,
                        'geometry', ST_AsGeoJSON(b.geom)::jsonb,
                        'properties', jsonb_build_object(
                            'id', b.id,
                            'building_id', b.id,
                            'address_id', ca.id,
                            'gers_id', b.gers_id,
                            'height', COALESCE(b.height_m, b.height, 10),
                            'height_m', COALESCE(b.height_m, b.height, 10),
                            'min_height', 0,
                            'is_townhome', COALESCE(b.is_townhome_row, false),
                            'units_count', COALESCE(b.units_count, 0),
                            'address_text', ca.formatted,
                            'match_method', l.method,
                            'feature_status', CASE WHEN l.id IS NOT NULL THEN 'matched' ELSE 'orphan_building' END,
                            'feature_type', CASE
                                WHEN l.id IS NOT NULL THEN 'matched_house'
                                ELSE 'orphan'
                            END,
                            'status', COALESCE(
                                s.status,
                                CASE b.latest_status
                                    WHEN 'interested' THEN 'visited'
                                    WHEN 'default' THEN 'not_visited'
                                    ELSE 'not_visited'
                                END
                            ),
                            'scans_today', COALESCE(s.scans_today, 0),
                            'scans_total', COALESCE(s.scans_total, 0),
                            'last_scan_seconds_ago', CASE
                                WHEN s.last_scan_at IS NOT NULL THEN extract(epoch from (now() - s.last_scan_at))
                                ELSE NULL
                            END
                        )
                    ) AS feature
                    FROM public.buildings b
                    LEFT JOIN public.building_address_links l ON b.id = l.building_id AND l.campaign_id = b.campaign_id
                    LEFT JOIN public.campaign_addresses ca ON l.address_id = ca.id
                    LEFT JOIN public.building_stats s ON b.gers_id = s.gers_id
                    WHERE b.campaign_id = p_campaign_id
                ) features;

                RETURN result;
            END;
            $inner$;
        $func$;
        
        GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_full_features(uuid) TO authenticated, service_role, anon;
    END IF;
END $$;

-- =====================================================
-- 5. CAMPAIGN ADDRESSES - Fetch all addresses for campaign
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_addresses(
    p_campaign_id uuid
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', a.id,
            'geometry', ST_AsGeoJSON(a.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', a.id,
                'gers_id', a.gers_id,
                'house_number', a.house_number,
                'street_name', a.street_name,
                'postal_code', a.postal_code,
                'locality', a.locality,
                'formatted', a.formatted
            )
        ) AS feature
        FROM public.campaign_addresses a
        WHERE a.campaign_id = p_campaign_id
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_addresses(uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_campaign_addresses IS
'Returns GeoJSON FeatureCollection of all addresses for a campaign. Used by iOS app. Expects object shape; iOS supports array fallback.';

-- =====================================================
-- 6. CAMPAIGN ROADS - Fetch all roads for campaign
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_roads(
    p_campaign_id uuid
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', r.id,
            'geometry', ST_AsGeoJSON(r.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', r.id,
                'gers_id', r.gers_id,
                'class', r.road_class,
                'name', r.name
            )
        ) AS feature
        FROM public.roads r
        WHERE r.campaign_id = p_campaign_id
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_roads(uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_campaign_roads IS
'Returns GeoJSON FeatureCollection of all roads for a campaign. Used by iOS app. Expects object shape; iOS supports array fallback.';

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
