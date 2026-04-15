-- Pre-aggregate leaderboard metrics from completed sessions.
-- Doors are now the canonical leaderboard metric; flyers are kept only as a legacy alias in the RPC output.

BEGIN;

CREATE TABLE IF NOT EXISTS public.leaderboard_rollups (
    scope_key TEXT NOT NULL,
    workspace_id UUID REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    timeframe TEXT NOT NULL CHECK (timeframe IN ('daily', 'weekly', 'monthly', 'all_time')),
    period_start TIMESTAMPTZ NOT NULL,
    doorknocks INTEGER NOT NULL DEFAULT 0,
    conversations INTEGER NOT NULL DEFAULT 0,
    leads INTEGER NOT NULL DEFAULT 0,
    distance_km DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (scope_key, user_id, timeframe, period_start)
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_rollups_scope_period
    ON public.leaderboard_rollups(scope_key, timeframe, period_start);

CREATE INDEX IF NOT EXISTS idx_leaderboard_rollups_workspace_period
    ON public.leaderboard_rollups(workspace_id, timeframe, period_start)
    WHERE workspace_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_workspace_started_user
    ON public.sessions(workspace_id, start_time DESC, user_id);

CREATE INDEX IF NOT EXISTS idx_sessions_started_user
    ON public.sessions(start_time DESC, user_id);

ALTER TABLE public.leaderboard_rollups ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.leaderboard_period_start(
    p_timeframe TEXT,
    p_reference TIMESTAMPTZ
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    CASE p_timeframe
        WHEN 'daily' THEN
            RETURN date_trunc('day', p_reference);
        WHEN 'weekly' THEN
            RETURN date_trunc('week', p_reference);
        WHEN 'monthly' THEN
            RETURN date_trunc('month', p_reference);
        WHEN 'all_time' THEN
            RETURN '1970-01-01 00:00:00+00'::TIMESTAMPTZ;
        ELSE
            RETURN date_trunc('week', p_reference);
    END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_leaderboard_rollup_rows(
    p_scope_key TEXT,
    p_workspace_id UUID,
    p_user_id UUID,
    p_reference TIMESTAMPTZ,
    p_doorknocks INTEGER,
    p_conversations INTEGER,
    p_leads INTEGER,
    p_distance_km DOUBLE PRECISION
)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    INSERT INTO public.leaderboard_rollups (
        scope_key,
        workspace_id,
        user_id,
        timeframe,
        period_start,
        doorknocks,
        conversations,
        leads,
        distance_km
    )
    SELECT
        p_scope_key,
        p_workspace_id,
        p_user_id,
        tf.timeframe,
        public.leaderboard_period_start(tf.timeframe, p_reference),
        GREATEST(COALESCE(p_doorknocks, 0), 0),
        GREATEST(COALESCE(p_conversations, 0), 0),
        GREATEST(COALESCE(p_leads, 0), 0),
        GREATEST(COALESCE(p_distance_km, 0.0), 0.0)
    FROM (
        VALUES ('daily'), ('weekly'), ('monthly'), ('all_time')
    ) AS tf(timeframe)
    ON CONFLICT (scope_key, user_id, timeframe, period_start)
    DO UPDATE SET
        doorknocks = public.leaderboard_rollups.doorknocks + EXCLUDED.doorknocks,
        conversations = public.leaderboard_rollups.conversations + EXCLUDED.conversations,
        leads = public.leaderboard_rollups.leads + EXCLUDED.leads,
        distance_km = public.leaderboard_rollups.distance_km + EXCLUDED.distance_km,
        updated_at = NOW();
$$;

CREATE OR REPLACE FUNCTION public.rebuild_leaderboard_rollups()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    TRUNCATE TABLE public.leaderboard_rollups;

    WITH completed_sessions AS (
        SELECT
            s.user_id,
            s.workspace_id,
            s.start_time,
            GREATEST(COALESCE(s.doors_hit, s.completed_count, s.flyers_delivered, 0), 0)::INTEGER AS doorknocks,
            GREATEST(COALESCE(s.conversations, 0), 0)::INTEGER AS conversations,
            GREATEST(COALESCE(s.leads_created, 0), 0)::INTEGER AS leads,
            GREATEST(COALESCE(s.distance_meters, 0), 0)::DOUBLE PRECISION / 1000.0 AS distance_km
        FROM public.sessions s
        WHERE s.end_time IS NOT NULL
    ),
    scoped_sessions AS (
        SELECT
            'global'::TEXT AS scope_key,
            NULL::UUID AS workspace_id,
            cs.user_id,
            cs.start_time,
            cs.doorknocks,
            cs.conversations,
            cs.leads,
            cs.distance_km
        FROM completed_sessions cs
        UNION ALL
        SELECT
            'workspace:' || cs.workspace_id::TEXT AS scope_key,
            cs.workspace_id,
            cs.user_id,
            cs.start_time,
            cs.doorknocks,
            cs.conversations,
            cs.leads,
            cs.distance_km
        FROM completed_sessions cs
        WHERE cs.workspace_id IS NOT NULL
    ),
    expanded AS (
        SELECT
            ss.scope_key,
            ss.workspace_id,
            ss.user_id,
            tf.timeframe,
            public.leaderboard_period_start(tf.timeframe, ss.start_time) AS period_start,
            ss.doorknocks,
            ss.conversations,
            ss.leads,
            ss.distance_km
        FROM scoped_sessions ss
        CROSS JOIN (
            VALUES ('daily'), ('weekly'), ('monthly'), ('all_time')
        ) AS tf(timeframe)
    )
    INSERT INTO public.leaderboard_rollups (
        scope_key,
        workspace_id,
        user_id,
        timeframe,
        period_start,
        doorknocks,
        conversations,
        leads,
        distance_km
    )
    SELECT
        e.scope_key,
        e.workspace_id,
        e.user_id,
        e.timeframe,
        e.period_start,
        SUM(e.doorknocks)::INTEGER,
        SUM(e.conversations)::INTEGER,
        SUM(e.leads)::INTEGER,
        SUM(e.distance_km)::DOUBLE PRECISION
    FROM expanded e
    GROUP BY
        e.scope_key,
        e.workspace_id,
        e.user_id,
        e.timeframe,
        e.period_start;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_user_stats_from_session ON public.sessions;
DROP FUNCTION IF EXISTS public.update_user_stats_from_session();

CREATE OR REPLACE FUNCTION public.update_user_stats_from_session()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_doors_knocked INTEGER := 0;
    v_flyers INTEGER := 0;
    v_conversations INTEGER := 0;
    v_leads_created INTEGER := 0;
    v_appointments INTEGER := 0;
    v_distance_walked DOUBLE PRECISION := 0.0;
    v_time_tracked INTEGER := 0;
BEGIN
    IF NEW.end_time IS NULL THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.end_time IS NOT NULL THEN
        RETURN NEW;
    END IF;

    v_doors_knocked := GREATEST(COALESCE(NEW.doors_hit, NEW.completed_count, NEW.flyers_delivered, 0), 0);
    v_flyers := GREATEST(COALESCE(NEW.flyers_delivered, NEW.completed_count, 0), 0);
    v_conversations := GREATEST(COALESCE(NEW.conversations, 0), 0);
    v_leads_created := GREATEST(COALESCE(NEW.leads_created, 0), 0);
    v_distance_walked := GREATEST(COALESCE(NEW.distance_meters, 0), 0)::DOUBLE PRECISION / 1000.0;
    v_time_tracked := GREATEST(
        COALESCE(
            FLOOR(COALESCE(NEW.active_seconds, EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))) / 60.0)::INTEGER,
            0
        ),
        0
    );

    SELECT COALESCE(COUNT(*), 0)::INTEGER
    INTO v_appointments
    FROM public.crm_events ce
    WHERE ce.user_id = NEW.user_id
      AND ce.fub_appointment_id IS NOT NULL
      AND ce.created_at >= NEW.start_time
      AND ce.created_at < NEW.end_time;

    INSERT INTO public.user_stats (
        user_id,
        doors_knocked,
        flyers,
        conversations,
        leads_created,
        appointments,
        distance_walked,
        time_tracked,
        conversation_per_door,
        conversation_lead_rate,
        qr_code_scan_rate,
        qr_code_lead_rate
    )
    VALUES (
        NEW.user_id,
        v_doors_knocked,
        v_flyers,
        v_conversations,
        v_leads_created,
        v_appointments,
        v_distance_walked,
        v_time_tracked,
        CASE
            WHEN v_doors_knocked > 0 THEN v_conversations::DOUBLE PRECISION / v_doors_knocked::DOUBLE PRECISION
            ELSE 0.0
        END,
        CASE
            WHEN v_conversations > 0 THEN v_leads_created::DOUBLE PRECISION / v_conversations::DOUBLE PRECISION
            ELSE 0.0
        END,
        0.0,
        0.0
    )
    ON CONFLICT (user_id) DO UPDATE SET
        doors_knocked = public.user_stats.doors_knocked + EXCLUDED.doors_knocked,
        flyers = public.user_stats.flyers + EXCLUDED.flyers,
        conversations = public.user_stats.conversations + EXCLUDED.conversations,
        leads_created = public.user_stats.leads_created + EXCLUDED.leads_created,
        appointments = public.user_stats.appointments + EXCLUDED.appointments,
        distance_walked = public.user_stats.distance_walked + EXCLUDED.distance_walked,
        time_tracked = public.user_stats.time_tracked + EXCLUDED.time_tracked,
        conversation_per_door = CASE
            WHEN (public.user_stats.doors_knocked + EXCLUDED.doors_knocked) > 0 THEN
                (public.user_stats.conversations + EXCLUDED.conversations)::DOUBLE PRECISION
                / (public.user_stats.doors_knocked + EXCLUDED.doors_knocked)::DOUBLE PRECISION
            ELSE 0.0
        END,
        conversation_lead_rate = CASE
            WHEN (public.user_stats.conversations + EXCLUDED.conversations) > 0 THEN
                (public.user_stats.leads_created + EXCLUDED.leads_created)::DOUBLE PRECISION
                / (public.user_stats.conversations + EXCLUDED.conversations)::DOUBLE PRECISION
            ELSE 0.0
        END,
        qr_code_scan_rate = CASE
            WHEN (public.user_stats.flyers + EXCLUDED.flyers) > 0 THEN
                public.user_stats.qr_codes_scanned::DOUBLE PRECISION
                / (public.user_stats.flyers + EXCLUDED.flyers)::DOUBLE PRECISION
            ELSE 0.0
        END,
        qr_code_lead_rate = CASE
            WHEN public.user_stats.qr_codes_scanned > 0 THEN
                (public.user_stats.leads_created + EXCLUDED.leads_created)::DOUBLE PRECISION
                / public.user_stats.qr_codes_scanned::DOUBLE PRECISION
            ELSE 0.0
        END,
        updated_at = NOW();

    PERFORM public.upsert_leaderboard_rollup_rows(
        'global',
        NULL,
        NEW.user_id,
        NEW.start_time,
        v_doors_knocked,
        v_conversations,
        v_leads_created,
        v_distance_walked
    );

    IF NEW.workspace_id IS NOT NULL THEN
        PERFORM public.upsert_leaderboard_rollup_rows(
            'workspace:' || NEW.workspace_id::TEXT,
            NEW.workspace_id,
            NEW.user_id,
            NEW.start_time,
            v_doors_knocked,
            v_conversations,
            v_leads_created,
            v_distance_walked
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_user_stats_from_session
    AFTER INSERT OR UPDATE OF end_time ON public.sessions
    FOR EACH ROW
    WHEN (NEW.end_time IS NOT NULL)
    EXECUTE FUNCTION public.update_user_stats_from_session();

DROP FUNCTION IF EXISTS public.get_leaderboard(text, text, uuid);

CREATE OR REPLACE FUNCTION public.get_leaderboard(
    p_metric TEXT DEFAULT 'doorknocks',
    p_timeframe TEXT DEFAULT 'weekly',
    p_workspace_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id TEXT,
    name TEXT,
    avatar_url TEXT,
    brokerage TEXT,
    rank INTEGER,
    doorknocks INTEGER,
    flyers INTEGER,
    leads INTEGER,
    conversations INTEGER,
    distance DOUBLE PRECISION,
    daily JSONB,
    weekly JSONB,
    monthly JSONB,
    all_time JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_scope_key TEXT;
    v_current_period TIMESTAMPTZ;
BEGIN
    IF p_timeframe NOT IN ('daily', 'weekly', 'monthly', 'all_time') THEN
        p_timeframe := 'weekly';
    END IF;

    IF p_metric NOT IN ('doorknocks', 'conversations', 'distance', 'leads', 'flyers') THEN
        p_metric := 'doorknocks';
    END IF;

    IF p_workspace_id IS NOT NULL THEN
        IF NOT public.is_workspace_member(p_workspace_id) THEN
            RAISE EXCEPTION 'Workspace access denied';
        END IF;
        v_scope_key := 'workspace:' || p_workspace_id::TEXT;
    ELSE
        v_scope_key := 'global';
    END IF;

    v_current_period := public.leaderboard_period_start(p_timeframe, NOW());

    RETURN QUERY
    WITH current_period AS (
        SELECT
            lr.user_id,
            lr.doorknocks,
            lr.conversations,
            lr.leads,
            lr.distance_km
        FROM public.leaderboard_rollups lr
        WHERE lr.scope_key = v_scope_key
          AND lr.timeframe = p_timeframe
          AND lr.period_start = v_current_period
          AND (
              lr.doorknocks > 0
              OR lr.conversations > 0
              OR lr.leads > 0
              OR lr.distance_km > 0
          )
    ),
    daily_stats AS (
        SELECT *
        FROM public.leaderboard_rollups lr
        WHERE lr.scope_key = v_scope_key
          AND lr.timeframe = 'daily'
          AND lr.period_start = public.leaderboard_period_start('daily', NOW())
    ),
    weekly_stats AS (
        SELECT *
        FROM public.leaderboard_rollups lr
        WHERE lr.scope_key = v_scope_key
          AND lr.timeframe = 'weekly'
          AND lr.period_start = public.leaderboard_period_start('weekly', NOW())
    ),
    monthly_stats AS (
        SELECT *
        FROM public.leaderboard_rollups lr
        WHERE lr.scope_key = v_scope_key
          AND lr.timeframe = 'monthly'
          AND lr.period_start = public.leaderboard_period_start('monthly', NOW())
    ),
    all_time_stats AS (
        SELECT *
        FROM public.leaderboard_rollups lr
        WHERE lr.scope_key = v_scope_key
          AND lr.timeframe = 'all_time'
          AND lr.period_start = public.leaderboard_period_start('all_time', NOW())
    ),
    ranked_users AS (
        SELECT
            cp.user_id::TEXT AS user_id,
            COALESCE(
                NULLIF(BTRIM(CONCAT_WS(
                    ' ',
                    NULLIF(BTRIM(p.first_name), ''),
                    NULLIF(BTRIM(p.last_name), '')
                )), ''),
                NULLIF(BTRIM(p.full_name), ''),
                NULLIF(BTRIM(au.raw_user_meta_data->>'full_name'), ''),
                NULLIF(BTRIM(SPLIT_PART(au.email, '@', 1)), ''),
                'Agent'
            ) AS display_name,
            COALESCE(
                NULLIF(BTRIM(p.avatar_url), ''),
                NULLIF(BTRIM(au.raw_user_meta_data->>'avatar_url'), '')
            )::TEXT AS user_avatar,
            NULLIF(BTRIM(COALESCE(au.raw_user_meta_data->>'brokerage', '')), '') AS user_brokerage,
            COALESCE(cp.doorknocks, 0) AS user_doorknocks,
            COALESCE(cp.conversations, 0) AS user_conversations,
            COALESCE(cp.leads, 0) AS user_leads,
            COALESCE(cp.distance_km, 0.0) AS user_distance,
            jsonb_build_object(
                'doorknocks', COALESCE(ds.doorknocks, 0),
                'flyers', COALESCE(ds.doorknocks, 0),
                'conversations', COALESCE(ds.conversations, 0),
                'distance', COALESCE(ds.distance_km, 0.0),
                'leads', COALESCE(ds.leads, 0)
            ) AS daily_snapshot,
            jsonb_build_object(
                'doorknocks', COALESCE(ws.doorknocks, 0),
                'flyers', COALESCE(ws.doorknocks, 0),
                'conversations', COALESCE(ws.conversations, 0),
                'distance', COALESCE(ws.distance_km, 0.0),
                'leads', COALESCE(ws.leads, 0)
            ) AS weekly_snapshot,
            jsonb_build_object(
                'doorknocks', COALESCE(ms.doorknocks, 0),
                'flyers', COALESCE(ms.doorknocks, 0),
                'conversations', COALESCE(ms.conversations, 0),
                'distance', COALESCE(ms.distance_km, 0.0),
                'leads', COALESCE(ms.leads, 0)
            ) AS monthly_snapshot,
            jsonb_build_object(
                'doorknocks', COALESCE(ats.doorknocks, 0),
                'flyers', COALESCE(ats.doorknocks, 0),
                'conversations', COALESCE(ats.conversations, 0),
                'distance', COALESCE(ats.distance_km, 0.0),
                'leads', COALESCE(ats.leads, 0)
            ) AS all_time_snapshot
        FROM current_period cp
        INNER JOIN auth.users au ON au.id = cp.user_id
        LEFT JOIN public.profiles p ON p.id = cp.user_id
        LEFT JOIN daily_stats ds ON ds.user_id = cp.user_id
        LEFT JOIN weekly_stats ws ON ws.user_id = cp.user_id
        LEFT JOIN monthly_stats ms ON ms.user_id = cp.user_id
        LEFT JOIN all_time_stats ats ON ats.user_id = cp.user_id
    )
    SELECT
        ru.user_id,
        ru.display_name,
        ru.user_avatar,
        ru.user_brokerage,
        (
            ROW_NUMBER() OVER (
                ORDER BY
                    CASE p_metric
                        WHEN 'doorknocks' THEN ru.user_doorknocks::DOUBLE PRECISION
                        WHEN 'flyers' THEN ru.user_doorknocks::DOUBLE PRECISION
                        WHEN 'conversations' THEN ru.user_conversations::DOUBLE PRECISION
                        WHEN 'distance' THEN ru.user_distance
                        WHEN 'leads' THEN ru.user_leads::DOUBLE PRECISION
                        ELSE ru.user_doorknocks::DOUBLE PRECISION
                    END DESC,
                    ru.user_doorknocks DESC,
                    ru.user_conversations DESC,
                    ru.user_distance DESC,
                    ru.user_id ASC
            )
        )::INTEGER AS user_rank,
        ru.user_doorknocks,
        ru.user_doorknocks AS legacy_flyers,
        ru.user_leads,
        ru.user_conversations,
        ru.user_distance,
        ru.daily_snapshot,
        ru.weekly_snapshot,
        ru.monthly_snapshot,
        ru.all_time_snapshot
    FROM ranked_users ru
    ORDER BY user_rank
    LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) TO authenticated;

COMMENT ON TABLE public.leaderboard_rollups IS
    'Pre-aggregated leaderboard metrics by scope and timeframe. Doors are the canonical activity metric.';

COMMENT ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) IS
    'Returns leaderboard rows from pre-aggregated rollups. doorknocks is canonical; flyers is a legacy alias.';

SELECT public.rebuild_leaderboard_rollups();

NOTIFY pgrst, 'reload schema';

COMMIT;
