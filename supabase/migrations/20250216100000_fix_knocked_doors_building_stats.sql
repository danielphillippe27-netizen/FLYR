-- =====================================================
-- Fix: Web not picking up knocked doors
-- 
-- rpc_complete_building_in_session was INSERTing into building_stats
-- without building_id. building_stats.building_id is the PRIMARY KEY and
-- NOT NULL, so the INSERT always failed. Knocked doors (completed in session)
-- never got a building_stats row, so the web map never showed them as green.
--
-- This migration fixes the RPC to:
-- 1. Include building_id in the INSERT (using v_building_id already resolved).
-- 2. Only run the INSERT when v_building_id IS NOT NULL.
-- 3. Cast gers_id correctly (building_stats.gers_id is UUID).
-- 4. Set campaign_addresses.visited = true when we have v_address_id so
--    address-level map views also show knocked doors.
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_complete_building_in_session(
    p_session_id UUID,
    p_building_id TEXT,
    p_event_type TEXT,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lon DOUBLE PRECISION DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_address_id UUID;
    v_campaign_id UUID;
    v_user_id UUID;
    v_event_id UUID;
    v_building_id UUID;
BEGIN
    -- Must be session owner
    SELECT campaign_id, user_id INTO v_campaign_id, v_user_id
    FROM public.sessions WHERE id = p_session_id;
    IF v_user_id IS NULL OR v_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Session not found or access denied';
    END IF;

    -- Resolve building by gers_id (p_building_id is gers_id as text)
    SELECT b.id INTO v_building_id
    FROM public.buildings b
    WHERE LOWER(b.gers_id::text) = LOWER(p_building_id)
    LIMIT 1;

    -- Find address_id for this building in this campaign
    IF v_campaign_id IS NOT NULL THEN
        SELECT bal.address_id INTO v_address_id
        FROM public.building_address_links bal
        WHERE bal.building_id = v_building_id
          AND bal.campaign_id = v_campaign_id
        LIMIT 1;
    END IF;

    -- Insert event (building_id stored as text = gers_id for replay; null for lifecycle events)
    INSERT INTO public.session_events (
        session_id, building_id, address_id, event_type,
        lat, lon, event_location, metadata, user_id
    ) VALUES (
        p_session_id,
        NULLIF(TRIM(p_building_id), ''),
        v_address_id,
        p_event_type,
        p_lat,
        p_lon,
        CASE WHEN p_lon IS NOT NULL AND p_lat IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
             ELSE NULL END,
        p_metadata,
        v_user_id
    )
    RETURNING id INTO v_event_id;

    -- Update session completed_count
    IF p_event_type IN ('completed_manual', 'completed_auto') THEN
        UPDATE public.sessions
        SET completed_count = completed_count + 1, updated_at = now()
        WHERE id = p_session_id;
    ELSIF p_event_type = 'completion_undone' THEN
        UPDATE public.sessions
        SET completed_count = GREATEST(0, completed_count - 1), updated_at = now()
        WHERE id = p_session_id;
    END IF;

    -- Update building_stats to visited when completing (not on undo).
    -- building_stats has building_id as PRIMARY KEY; we must include it on INSERT.
    IF p_event_type IN ('completed_manual', 'completed_auto') AND v_campaign_id IS NOT NULL AND NULLIF(TRIM(p_building_id), '') IS NOT NULL THEN
        UPDATE public.building_stats
        SET status = 'visited', last_scan_at = now(), updated_at = now()
        WHERE LOWER(TRIM(gers_id::text)) = LOWER(TRIM(p_building_id)) AND campaign_id = v_campaign_id;

        IF NOT FOUND AND v_building_id IS NOT NULL THEN
            INSERT INTO public.building_stats (building_id, gers_id, campaign_id, status, scans_total, scans_today, last_scan_at)
            SELECT
                v_building_id,
                b.gers_id,
                v_campaign_id,
                'visited',
                0,
                0,
                now()
            FROM public.buildings b
            WHERE b.id = v_building_id;
        END IF;

        -- So address-level map views (e.g. campaign addresses GeoJSON) show knocked doors
        IF v_address_id IS NOT NULL THEN
            UPDATE public.campaign_addresses
            SET visited = true
            WHERE id = v_address_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('event_id', v_event_id, 'address_id', v_address_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_complete_building_in_session(UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB) TO authenticated;

COMMENT ON FUNCTION public.rpc_complete_building_in_session IS 'Records session completion/undo and updates building_stats (and campaign_addresses.visited) so map shows knocked doors (green).';
