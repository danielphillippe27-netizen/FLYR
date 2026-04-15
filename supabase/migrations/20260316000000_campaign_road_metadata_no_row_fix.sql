-- Fix rpc_get_campaign_road_metadata to return default object when no row exists.
-- Swift decodes a single JSON object; without this, NULL fields break decoding.

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_road_metadata(
    p_campaign_id UUID
) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    v_metadata RECORD;
    v_age_days NUMERIC;
BEGIN
    SELECT * INTO v_metadata
    FROM public.campaign_road_metadata
    WHERE campaign_id = p_campaign_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'campaign_id', p_campaign_id,
            'roads_status', 'pending',
            'road_count', 0,
            'cache_version', 0,
            'corridor_build_version', 1,
            'fetched_at', NULL,
            'expires_at', NULL,
            'last_refresh_at', NULL,
            'age_days', NULL,
            'is_stale', false,
            'last_error_message', NULL,
            'source', 'mapbox'
        );
    END IF;
    
    v_age_days := NULL;
    IF v_metadata.fetched_at IS NOT NULL THEN
        v_age_days := EXTRACT(EPOCH FROM (NOW() - v_metadata.fetched_at)) / 86400;
    END IF;
    
    RETURN jsonb_build_object(
        'campaign_id', p_campaign_id,
        'roads_status', COALESCE(v_metadata.roads_status, 'pending'),
        'road_count', COALESCE(v_metadata.road_count, 0),
        'cache_version', COALESCE(v_metadata.cache_version, 0),
        'corridor_build_version', COALESCE(v_metadata.corridor_build_version, 1),
        'fetched_at', v_metadata.fetched_at,
        'expires_at', v_metadata.expires_at,
        'last_refresh_at', v_metadata.last_refresh_at,
        'age_days', v_age_days,
        'is_stale', v_age_days IS NOT NULL AND v_age_days >= 30,
        'last_error_message', v_metadata.last_error_message,
        'source', COALESCE(v_metadata.source, 'mapbox')
    );
END;
$$;

COMMENT ON FUNCTION public.rpc_get_campaign_road_metadata(UUID) IS 'Get campaign road metadata; returns defaults when no row exists.';
