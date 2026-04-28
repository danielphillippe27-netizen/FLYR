BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_get_public_session_beacon(p_share_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_share public.session_shares%ROWTYPE;
    v_result JSONB;
BEGIN
    SELECT ss.*
    INTO v_share
    FROM public.session_shares ss
    INNER JOIN public.sessions s ON s.id = ss.session_id
    WHERE ss.share_token_hash = md5(COALESCE(p_share_token, ''))
      AND ss.revoked_at IS NULL
      AND (ss.expires_at IS NULL OR ss.expires_at > now())
      AND s.end_time IS NULL
    ORDER BY ss.created_at DESC
    LIMIT 1;

    IF v_share.id IS NULL THEN
        RETURN jsonb_build_object(
            'active', false,
            'reason', 'expired'
        );
    END IF;

    UPDATE public.session_shares
    SET last_viewed_at = now()
    WHERE id = v_share.id;

    WITH session_row AS (
        SELECT
            s.id,
            s.start_time,
            s.end_time,
            s.goal_type,
            s.goal_amount,
            s.completed_count,
            s.flyers_delivered,
            s.conversations,
            s.distance_meters,
            s.is_paused,
            s.campaign_id
        FROM public.sessions s
        WHERE s.id = v_share.session_id
    ),
    latest_heartbeat AS (
        SELECT
            h.lat,
            h.lon,
            h.battery_level,
            h.movement_state,
            h.device_status,
            h.recorded_at
        FROM public.session_heartbeats h
        WHERE h.session_id = v_share.session_id
        ORDER BY h.recorded_at DESC
        LIMIT 1
    ),
    fallback_location AS (
        SELECT
            se.lat,
            se.lon,
            se.created_at AS recorded_at,
            se.event_type
        FROM public.session_events se
        WHERE se.session_id = v_share.session_id
          AND se.event_type IN ('session_started', 'session_resumed', 'session_paused')
          AND se.lat IS NOT NULL
          AND se.lon IS NOT NULL
          AND se.lat BETWEEN -90 AND 90
          AND se.lon BETWEEN -180 AND 180
          AND NOT (ABS(se.lat) < 0.000001 AND ABS(se.lon) < 0.000001)
        ORDER BY se.created_at DESC, se.id DESC
        LIMIT 1
    ),
    breadcrumb_rows AS (
        SELECT jsonb_build_object(
            'lat', h.lat,
            'lon', h.lon,
            'battery_level', h.battery_level,
            'movement_state', h.movement_state,
            'recorded_at', h.recorded_at
        ) AS item
        FROM public.session_heartbeats h
        WHERE h.session_id = v_share.session_id
          AND h.recorded_at >= GREATEST(
              now() - INTERVAL '12 hours',
              v_share.created_at - INTERVAL '15 minutes'
          )
        ORDER BY h.recorded_at ASC
        LIMIT 500
    ),
    session_door_events AS (
        SELECT DISTINCT ON (se.address_id)
            se.address_id,
            se.event_type,
            COALESCE(se.metadata ->> 'address_status', 'none') AS address_status,
            se.created_at
        FROM public.session_events se
        WHERE se.session_id = v_share.session_id
          AND se.address_id IS NOT NULL
          AND se.event_type IN ('completed_manual', 'completed_auto', 'completion_undone')
        ORDER BY se.address_id, se.created_at DESC, se.id DESC
    ),
    session_doors AS (
        SELECT
            sde.created_at,
            jsonb_build_object(
                'address_id', ca.id,
                'formatted', ca.formatted,
                'house_number', ca.house_number,
                'street_name', ca.street_name,
                'lat', ST_Y(ca.geom::geometry),
                'lon', ST_X(ca.geom::geometry),
                'status', sde.address_status,
                'map_status', CASE
                    WHEN sde.address_status IN ('talked', 'appointment', 'hot_lead') THEN 'hot'
                    WHEN sde.address_status = 'do_not_knock' THEN 'do_not_knock'
                    WHEN sde.address_status = 'no_answer' THEN 'no_answer'
                    WHEN sde.address_status IN ('delivered', 'future_seller') THEN 'visited'
                    ELSE 'not_visited'
                END,
                'event_type', sde.event_type,
                'created_at', sde.created_at
            ) AS item
        FROM session_door_events sde
        JOIN public.campaign_addresses ca ON ca.id = sde.address_id
        WHERE sde.event_type <> 'completion_undone'
          AND ca.geom IS NOT NULL
        ORDER BY sde.created_at DESC
        LIMIT 300
    ),
    active_events AS (
        SELECT jsonb_build_object(
            'id', se.id,
            'event_type', se.event_type,
            'message', se.message,
            'lat', se.lat,
            'lon', se.lon,
            'created_at', se.created_at
        ) AS item
        FROM public.safety_events se
        WHERE se.session_id = v_share.session_id
          AND se.acknowledged_at IS NULL
          AND se.created_at >= now() - INTERVAL '24 hours'
        ORDER BY se.created_at DESC
        LIMIT 20
    )
    SELECT jsonb_build_object(
        'active', true,
        'share', jsonb_build_object(
            'id', v_share.id,
            'viewer_label', v_share.viewer_label,
            'created_at', v_share.created_at,
            'check_in_interval_minutes', v_share.check_in_interval_minutes,
            'last_viewed_at', now()
        ),
        'session', COALESCE((SELECT to_jsonb(sr) FROM session_row sr), '{}'::jsonb),
        'latest_heartbeat', COALESCE((SELECT to_jsonb(lh) FROM latest_heartbeat lh), 'null'::jsonb),
        'fallback_location', COALESCE(
            (
                SELECT jsonb_build_object(
                    'lat', fl.lat,
                    'lon', fl.lon,
                    'recorded_at', fl.recorded_at,
                    'event_type', fl.event_type
                )
                FROM fallback_location fl
            ),
            'null'::jsonb
        ),
        'breadcrumbs', COALESCE((SELECT jsonb_agg(br.item) FROM breadcrumb_rows br), '[]'::jsonb),
        'session_doors', COALESCE((SELECT jsonb_agg(sd.item ORDER BY sd.created_at DESC) FROM session_doors sd), '[]'::jsonb),
        'safety_events', COALESCE((SELECT jsonb_agg(ae.item) FROM active_events ae), '[]'::jsonb)
    )
    INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_public_session_beacon(TEXT) TO anon, authenticated;

COMMENT ON FUNCTION public.rpc_get_public_session_beacon(TEXT) IS
'Returns the public Beacon payload for an active session, including live breadcrumbs, fallback lifecycle coordinates, safety alerts, and the latest door outcomes recorded during that session.';

COMMIT;
