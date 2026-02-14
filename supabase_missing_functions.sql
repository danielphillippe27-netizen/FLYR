-- =====================================================
-- Missing SQL for iOS Map Features
-- Run this in Supabase SQL Editor if you see errors about
-- rpc_get_campaign_addresses, rpc_get_campaign_roads, or
-- need the address_statuses view.
-- =====================================================

-- =====================================================
-- 1. rpc_get_campaign_full_features (if missing)
-- Returns GeoJSON FeatureCollection of buildings with status.
-- =====================================================

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
-- 2. rpc_get_campaign_addresses
-- Returns addresses for campaign (GeoJSON FeatureCollection).
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

-- =====================================================
-- 3. rpc_get_campaign_roads – PLACEHOLDER (returns empty)
-- Use this if public.roads does not exist or you want no roads.
-- Replace with the full version from 20250203_ios_map_features_rpc.sql
-- when you have a roads table.
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_roads(
    p_campaign_id uuid
) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
    RETURN jsonb_build_object(
        'type', 'FeatureCollection',
        'features', '[]'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_roads(uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_campaign_roads IS
'Placeholder: returns empty GeoJSON FeatureCollection. Replace with roads query when public.roads exists.';

-- =====================================================
-- 4. address_statuses view (optional)
-- The table address_statuses is created in migration
-- 20250205000000_create_address_statuses.sql.
-- This view exposes it; create only if you want a view.
-- =====================================================

-- Optional: create a view over address_statuses (table from migration 20250205000000_create_address_statuses.sql)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'address_statuses') THEN
        EXECUTE 'CREATE OR REPLACE VIEW public.address_statuses_view AS SELECT * FROM public.address_statuses';
    END IF;
END $$;

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
