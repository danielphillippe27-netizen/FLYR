-- =====================================================
-- Fix Building RPC Issues
-- 
-- This migration fixes three issues:
-- 1. Ensures is_townhome_row column exists in buildings table
-- 2. Makes UUID comparisons case-insensitive
-- 3. Adds defensive NULL handling in RPC functions
-- =====================================================

-- =====================================================
-- 1. Ensure is_townhome_row column exists
-- =====================================================

-- Add column if it doesn't exist (idempotent)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'buildings' 
        AND column_name = 'is_townhome_row'
    ) THEN
        ALTER TABLE public.buildings 
        ADD COLUMN is_townhome_row BOOLEAN DEFAULT false;
        
        RAISE NOTICE 'Added is_townhome_row column to buildings table';
    ELSE
        RAISE NOTICE 'Column is_townhome_row already exists in buildings table';
    END IF;
END $$;

-- =====================================================
-- 2. Fix rpc_get_buildings_in_bbox with defensive checks
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
            'id', b.id::text,
            'geometry', ST_AsGeoJSON(b.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', b.id::text,
                'building_id', b.id::text,
                'gers_id', COALESCE(b.gers_id::text, NULL),
                'height', COALESCE(b.height_m, b.height, 10),
                'height_m', COALESCE(b.height_m, b.height, 10),
                'min_height', 0,
                'is_townhome', COALESCE(b.is_townhome_row, false),
                'units_count', COALESCE(b.units_count, 1),
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
        LEFT JOIN public.building_stats s ON LOWER(b.gers_id::text) = LOWER(s.gers_id::text)
        WHERE b.geom && bbox
          AND ST_Intersects(b.geom, bbox)
          AND (p_campaign_id IS NULL OR b.campaign_id = p_campaign_id)
        LIMIT 2000
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_buildings_in_bbox(float, float, float, float, uuid) TO authenticated, service_role, anon;

-- =====================================================
-- 3. Fix rpc_get_campaign_full_features with defensive checks
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_full_features(
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
            'id', b.id::text,
            'geometry', ST_AsGeoJSON(b.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', b.id::text,
                'building_id', b.id::text,
                'address_id', COALESCE(ca.id::text, NULL),
                'gers_id', COALESCE(b.gers_id::text, NULL),
                'height', COALESCE(b.height_m, b.height, 10),
                'height_m', COALESCE(b.height_m, b.height, 10),
                'min_height', 0,
                'is_townhome', COALESCE(b.is_townhome_row, false),
                'units_count', COALESCE(b.units_count, 1),
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
        LEFT JOIN public.building_stats s ON LOWER(b.gers_id::text) = LOWER(s.gers_id::text)
        WHERE b.campaign_id = p_campaign_id
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_full_features(uuid) TO authenticated, service_role, anon;

-- =====================================================
-- 4. Create helper function for case-insensitive UUID comparison
-- =====================================================

CREATE OR REPLACE FUNCTION public.uuid_lower(input_uuid uuid)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT LOWER(input_uuid::text)::uuid;
$$;

COMMENT ON FUNCTION public.uuid_lower IS 'Returns lowercase UUID for case-insensitive comparisons';

-- =====================================================
-- 5. Update building_stats indexes for case-insensitive lookups
-- =====================================================

-- Drop existing index if it exists
DROP INDEX IF EXISTS public.idx_building_stats_gers_id;

-- Create case-insensitive index
CREATE INDEX IF NOT EXISTS idx_building_stats_gers_id_lower 
ON public.building_stats(LOWER(gers_id::text)) 
WHERE gers_id IS NOT NULL;

-- =====================================================
-- 6. Add diagnostic function to check building data
-- =====================================================

CREATE OR REPLACE FUNCTION public.debug_building_data(
    p_campaign_id uuid
) RETURNS TABLE (
    total_buildings bigint,
    buildings_with_gers_id bigint,
    buildings_with_links bigint,
    buildings_with_stats bigint,
    sample_gers_ids text[]
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::bigint as total_buildings,
        COUNT(b.gers_id)::bigint as buildings_with_gers_id,
        COUNT(l.id)::bigint as buildings_with_links,
        COUNT(s.building_id)::bigint as buildings_with_stats,
        ARRAY_AGG(DISTINCT b.gers_id::text) FILTER (WHERE b.gers_id IS NOT NULL) as sample_gers_ids
    FROM public.buildings b
    LEFT JOIN public.building_address_links l ON b.id = l.building_id
    LEFT JOIN public.building_stats s ON LOWER(b.gers_id::text) = LOWER(s.gers_id::text)
    WHERE b.campaign_id = p_campaign_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_building_data(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.debug_building_data IS 'Diagnostic function to check building data integrity for a campaign';

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
