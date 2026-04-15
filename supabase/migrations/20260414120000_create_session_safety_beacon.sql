BEGIN;

CREATE TABLE IF NOT EXISTS public.session_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    share_token_hash TEXT NOT NULL UNIQUE,
    viewer_label TEXT,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    last_viewed_at TIMESTAMPTZ,
    check_in_interval_minutes INTEGER CHECK (
        check_in_interval_minutes IS NULL
        OR check_in_interval_minutes IN (15, 30, 60)
    ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_session_shares_one_active_per_session
    ON public.session_shares(session_id)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_session_shares_created_by
    ON public.session_shares(created_by);

CREATE INDEX IF NOT EXISTS idx_session_shares_session_id
    ON public.session_shares(session_id);

CREATE TABLE IF NOT EXISTS public.session_heartbeats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    share_id UUID REFERENCES public.session_shares(id) ON DELETE SET NULL,
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    battery_level DOUBLE PRECISION,
    movement_state TEXT NOT NULL DEFAULT 'unknown' CHECK (
        movement_state IN ('moving', 'stationary', 'paused', 'unknown')
    ),
    device_status JSONB NOT NULL DEFAULT '{}'::jsonb,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_session_heartbeats_session_recorded
    ON public.session_heartbeats(session_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_session_heartbeats_share_id
    ON public.session_heartbeats(share_id);

CREATE TABLE IF NOT EXISTS public.session_checkins (
    session_id UUID PRIMARY KEY REFERENCES public.sessions(id) ON DELETE CASCADE,
    share_id UUID REFERENCES public.session_shares(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    interval_minutes INTEGER NOT NULL CHECK (interval_minutes IN (15, 30, 60)),
    grace_period_minutes INTEGER NOT NULL DEFAULT 5 CHECK (grace_period_minutes BETWEEN 1 AND 30),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'disabled')),
    next_prompt_at TIMESTAMPTZ,
    last_prompted_at TIMESTAMPTZ,
    last_confirmed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_session_checkins_share_id
    ON public.session_checkins(share_id);

CREATE TABLE IF NOT EXISTS public.safety_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    share_id UUID REFERENCES public.session_shares(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (
        event_type IN (
            'share_started',
            'share_stopped',
            'check_in_confirmed',
            'missed_check_in',
            'sos'
        )
    ),
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    message TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    acknowledged_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_safety_events_session_created
    ON public.safety_events(session_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_safety_events_share_id
    ON public.safety_events(share_id);

ALTER TABLE public.session_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_heartbeats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safety_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "session_shares_owner_all" ON public.session_shares;
CREATE POLICY "session_shares_owner_all"
    ON public.session_shares
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_shares.session_id
              AND s.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_shares.session_id
              AND s.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "session_heartbeats_owner_all" ON public.session_heartbeats;
CREATE POLICY "session_heartbeats_owner_all"
    ON public.session_heartbeats
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_heartbeats.session_id
              AND s.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_heartbeats.session_id
              AND s.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "session_checkins_owner_all" ON public.session_checkins;
CREATE POLICY "session_checkins_owner_all"
    ON public.session_checkins
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_checkins.session_id
              AND s.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_checkins.session_id
              AND s.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "safety_events_owner_all" ON public.safety_events;
CREATE POLICY "safety_events_owner_all"
    ON public.safety_events
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = safety_events.session_id
              AND s.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = safety_events.session_id
              AND s.user_id = auth.uid()
        )
    );

DROP TRIGGER IF EXISTS update_session_shares_updated_at ON public.session_shares;
CREATE TRIGGER update_session_shares_updated_at
    BEFORE UPDATE ON public.session_shares
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_session_checkins_updated_at ON public.session_checkins;
CREATE TRIGGER update_session_checkins_updated_at
    BEFORE UPDATE ON public.session_checkins
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_shares TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_heartbeats TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_checkins TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.safety_events TO authenticated;

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
            s.is_paused
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
        'breadcrumbs', COALESCE((SELECT jsonb_agg(br.item) FROM breadcrumb_rows br), '[]'::jsonb),
        'safety_events', COALESCE((SELECT jsonb_agg(ae.item) FROM active_events ae), '[]'::jsonb)
    )
    INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_public_session_beacon(TEXT) TO anon, authenticated;

COMMENT ON TABLE public.session_shares IS 'Revocable Beacon links for active session location sharing.';
COMMENT ON TABLE public.session_heartbeats IS 'Live location breadcrumbs and device health for active Beacon sessions.';
COMMENT ON TABLE public.session_checkins IS 'Optional safety check-in schedule for active sessions.';
COMMENT ON TABLE public.safety_events IS 'Safety-related events such as missed check-ins or SOS actions.';

COMMIT;
