BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_full_features_for_farm_phase(
    p_campaign_id UUID,
    p_farm_phase_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    WITH latest_address_status AS (
        SELECT DISTINCT ON (se.address_id)
            se.address_id AS campaign_address_id,
            COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), 'none') AS status
        FROM public.session_events se
        INNER JOIN public.sessions s ON s.id = se.session_id
        WHERE s.campaign_id = p_campaign_id
          AND s.farm_phase_id = p_farm_phase_id
          AND se.address_id IS NOT NULL
          AND COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), '') <> ''
        ORDER BY se.address_id, se.created_at DESC, se.id DESC
    ),
    gold_features AS (
        SELECT jsonb_build_object(
            'type',       'Feature',
            'id',         b.id::text,
            'geometry',   ST_AsGeoJSON(b.geom, 6)::jsonb,
            'properties', jsonb_build_object(
                'id',            b.id::text,
                'building_id',   b.id::text,
                'gers_id',       b.id::text,
                'source',        'gold',
                'address_count', COUNT(ca.id),
                'address_id',    CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.id)::text ELSE NULL END,
                'address_text',  CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.formatted) ELSE NULL END,
                'house_number',  CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.house_number) ELSE NULL END,
                'street_name',   CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.street_name) ELSE NULL END,
                'height',        COALESCE(b.height_m, 10),
                'height_m',      COALESCE(b.height_m, 10),
                'min_height',    0,
                'area_sqm',      b.area_sqm,
                'building_type', b.building_type,
                'feature_type',  'matched_house',
                'feature_status','matched',
                'status',        CASE
                                    WHEN BOOL_OR(las.status IN ('talked', 'appointment', 'hot_lead')) THEN 'hot'
                                    WHEN BOOL_OR(las.status IN ('delivered', 'do_not_knock', 'future_seller')) THEN 'visited'
                                    ELSE 'not_visited'
                                 END,
                'scans_today',   0,
                'scans_total',   0
            )
        ) AS feature
        FROM public.campaign_addresses ca
        JOIN public.ref_buildings_gold b ON b.id = ca.building_id
        LEFT JOIN latest_address_status las ON las.campaign_address_id = ca.id
        WHERE ca.campaign_id = p_campaign_id
          AND ca.building_id IS NOT NULL
        GROUP BY b.id, b.geom, b.height_m, b.area_sqm, b.building_type
    ),
    campaign_building_rows AS (
        SELECT
            COALESCE(b.gers_id::text, b.id::text) AS public_building_id,
            b.id AS row_building_id,
            b.geom,
            b.source,
            b.height_m,
            b.height,
            b.levels,
            b.is_townhome_row,
            b.units_count,
            COUNT(ca.id) FILTER (WHERE ca.id IS NOT NULL) AS address_count,
            CASE
                WHEN COUNT(ca.id) FILTER (WHERE ca.id IS NOT NULL) = 1
                    THEN MIN(ca.id)::text
                ELSE NULL
            END AS address_id,
            CASE
                WHEN COUNT(ca.id) FILTER (WHERE ca.id IS NOT NULL) = 1
                    THEN MIN(ca.formatted)
                ELSE NULL
            END AS address_text,
            CASE
                WHEN COUNT(ca.id) FILTER (WHERE ca.id IS NOT NULL) = 1
                    THEN MIN(ca.house_number)
                ELSE NULL
            END AS house_number,
            CASE
                WHEN COUNT(ca.id) FILTER (WHERE ca.id IS NOT NULL) = 1
                    THEN MIN(ca.street_name)
                ELSE NULL
            END AS street_name,
            0 AS scans_total,
            BOOL_OR(las.status IN ('talked', 'appointment', 'hot_lead')) AS has_hot_address,
            BOOL_OR(las.status IN ('delivered', 'do_not_knock', 'future_seller')) AS has_visited_address
        FROM public.buildings b
        LEFT JOIN public.building_address_links l
            ON l.campaign_id = p_campaign_id
           AND (
                l.building_id::text = b.id::text
                OR (b.gers_id IS NOT NULL AND l.building_id::text = b.gers_id::text)
           )
        LEFT JOIN public.campaign_addresses ca
            ON ca.id = l.address_id
           AND ca.campaign_id = p_campaign_id
        LEFT JOIN latest_address_status las
            ON las.campaign_address_id = ca.id
        WHERE b.campaign_id = p_campaign_id
          AND b.geom IS NOT NULL
        GROUP BY
            b.id,
            b.gers_id,
            b.geom,
            b.source,
            b.height_m,
            b.height,
            b.levels,
            b.is_townhome_row,
            b.units_count
    ),
    campaign_building_features AS (
        SELECT jsonb_build_object(
            'type',       'Feature',
            'id',         public_building_id,
            'geometry',   ST_AsGeoJSON(geom, 6)::jsonb,
            'properties', jsonb_build_object(
                'id',            public_building_id,
                'building_id',   public_building_id,
                'gers_id',       public_building_id,
                'source',        CASE
                                    WHEN LOWER(COALESCE(source, '')) = 'manual' THEN 'manual'
                                    ELSE 'silver'
                                 END,
                'address_count', address_count,
                'address_id',    address_id,
                'address_text',  address_text,
                'house_number',  house_number,
                'street_name',   street_name,
                'height',        COALESCE(height_m, height, GREATEST(COALESCE(levels, 1), 1) * 3, 10),
                'height_m',      COALESCE(height_m, height, GREATEST(COALESCE(levels, 1), 1) * 3, 10),
                'min_height',    0,
                'is_townhome',   COALESCE(is_townhome_row, false),
                'units_count',   GREATEST(COALESCE(units_count, address_count, 1), 1),
                'feature_type',  CASE
                                    WHEN LOWER(COALESCE(source, '')) = 'manual' THEN 'manual_building'
                                    ELSE 'matched_house'
                                 END,
                'feature_status',CASE
                                    WHEN address_count > 0 THEN 'matched'
                                    WHEN LOWER(COALESCE(source, '')) = 'manual' THEN 'manual'
                                    ELSE 'unlinked'
                                 END,
                'status',        CASE
                                    WHEN COALESCE(has_hot_address, false) THEN 'hot'
                                    WHEN COALESCE(has_visited_address, false) THEN 'visited'
                                    ELSE 'not_visited'
                                 END,
                'scans_today',   0,
                'scans_total',   scans_total
            )
        ) AS feature
        FROM campaign_building_rows
    ),
    address_point_features AS (
        SELECT jsonb_build_object(
            'type',       'Feature',
            'id',         ca.id::text,
            'geometry',   ST_AsGeoJSON(ca.geom, 6)::jsonb,
            'properties', jsonb_build_object(
                'id',            ca.id::text,
                'address_id',    ca.id::text,
                'source',        CASE
                                    WHEN LOWER(COALESCE(ca.source, '')) = 'manual' THEN 'manual'
                                    ELSE 'address_point'
                                 END,
                'feature_type',  CASE
                                    WHEN LOWER(COALESCE(ca.source, '')) = 'manual' THEN 'manual_address'
                                    ELSE 'address_point'
                                 END,
                'feature_status','address_point',
                'address_text',  ca.formatted,
                'house_number',  ca.house_number,
                'street_name',   ca.street_name,
                'height',        5,
                'height_m',      5,
                'min_height',    0,
                'status',        CASE
                                    WHEN las.status IN ('talked', 'appointment', 'hot_lead') THEN 'hot'
                                    WHEN las.status IN ('delivered', 'do_not_knock', 'future_seller') THEN 'visited'
                                    ELSE 'not_visited'
                                 END,
                'scans_today',   0,
                'scans_total',   0
            )
        ) AS feature
        FROM public.campaign_addresses ca
        LEFT JOIN latest_address_status las ON las.campaign_address_id = ca.id
        WHERE ca.campaign_id = p_campaign_id
          AND ca.geom IS NOT NULL
          AND ca.building_id IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM public.building_address_links l
              WHERE l.campaign_id = p_campaign_id
                AND l.address_id = ca.id
          )
    )
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(all_features.feature), '[]'::jsonb)
    )
    INTO v_result
    FROM (
        SELECT feature FROM gold_features
        UNION ALL
        SELECT feature FROM campaign_building_features
        UNION ALL
        SELECT feature FROM address_point_features
    ) AS all_features;

    IF v_result IS NULL THEN
        v_result := '{"type":"FeatureCollection","features":[]}'::jsonb;
    END IF;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_address_status_rows_for_farm_phase(
    p_campaign_id UUID,
    p_farm_phase_id UUID
)
RETURNS TABLE (
    id UUID,
    campaign_address_id UUID,
    address_id UUID,
    campaign_id UUID,
    status TEXT,
    last_visited_at TIMESTAMPTZ,
    notes TEXT,
    visit_count INTEGER,
    last_action_by UUID,
    last_session_id UUID,
    last_home_event_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor_user_id UUID := auth.uid();
BEGIN
    IF v_actor_user_id IS NULL OR NOT public.is_campaign_member(p_campaign_id, v_actor_user_id) THEN
        RAISE EXCEPTION 'Campaign not found or access denied';
    END IF;

    RETURN QUERY
    WITH phase_events AS (
        SELECT
            se.address_id AS campaign_address_id,
            COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), 'none') AS address_status,
            NULLIF(TRIM(se.metadata ->> 'notes'), '') AS notes,
            se.created_at,
            se.user_id,
            se.session_id,
            ROW_NUMBER() OVER (
                PARTITION BY se.address_id
                ORDER BY se.created_at DESC, se.id DESC
            ) AS row_number,
            COUNT(*) FILTER (
                WHERE COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), 'none') <> 'none'
            ) OVER (PARTITION BY se.address_id) AS visit_count
        FROM public.session_events se
        INNER JOIN public.sessions s ON s.id = se.session_id
        WHERE s.campaign_id = p_campaign_id
          AND s.farm_phase_id = p_farm_phase_id
          AND se.address_id IS NOT NULL
          AND COALESCE(NULLIF(TRIM(se.metadata ->> 'address_status'), ''), '') <> ''
    )
    SELECT
        pe.campaign_address_id AS id,
        pe.campaign_address_id,
        pe.campaign_address_id AS address_id,
        p_campaign_id AS campaign_id,
        pe.address_status AS status,
        CASE
            WHEN pe.address_status = 'none' THEN NULL
            ELSE pe.created_at
        END AS last_visited_at,
        pe.notes,
        COALESCE(pe.visit_count, 0)::INTEGER AS visit_count,
        pe.user_id AS last_action_by,
        pe.session_id AS last_session_id,
        NULL::UUID AS last_home_event_id,
        pe.created_at,
        pe.created_at AS updated_at
    FROM phase_events pe
    WHERE pe.row_number = 1
    ORDER BY pe.created_at DESC;
END;
$$;

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
            s.campaign_id,
            s.farm_phase_id
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

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_full_features_for_farm_phase(UUID, UUID) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_address_status_rows_for_farm_phase(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_public_session_beacon(TEXT) TO anon, authenticated;

COMMENT ON FUNCTION public.rpc_get_campaign_full_features_for_farm_phase(UUID, UUID) IS
'Returns a GeoJSON FeatureCollection for a campaign, scoped to visit outcomes recorded during sessions linked to a specific farm phase/cycle. Scans are suppressed so prior-cycle QR activity does not bleed into the phase map.';

COMMENT ON FUNCTION public.rpc_get_campaign_address_status_rows_for_farm_phase(UUID, UUID) IS
'Returns the latest per-address status rows for a campaign, scoped to sessions linked to a specific farm phase/cycle.';

COMMENT ON FUNCTION public.rpc_get_public_session_beacon(TEXT) IS
'Returns the public Beacon payload for an active session, including live breadcrumbs, fallback lifecycle coordinates, safety alerts, and the latest door outcomes recorded during that session. Session payload now includes farm_phase_id when present.';

NOTIFY pgrst, 'reload schema';

COMMIT;
