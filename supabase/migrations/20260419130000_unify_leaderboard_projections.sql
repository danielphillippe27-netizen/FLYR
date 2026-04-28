BEGIN;

CREATE OR REPLACE FUNCTION public.refresh_leaderboard_rollups_for_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.leaderboard_rollups
    WHERE user_id = p_user_id;

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
        WHERE s.user_id = p_user_id
          AND s.end_time IS NOT NULL
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
        COALESCE(SUM(e.doorknocks), 0)::INTEGER,
        COALESCE(SUM(e.conversations), 0)::INTEGER,
        COALESCE(SUM(e.leads), 0)::INTEGER,
        COALESCE(SUM(e.distance_km), 0.0)::DOUBLE PRECISION
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

CREATE OR REPLACE FUNCTION public.refresh_user_projections_from_session()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.refresh_user_stats_from_sessions(OLD.user_id);
        PERFORM public.refresh_leaderboard_rollups_for_user(OLD.user_id);
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM NEW.user_id THEN
        PERFORM public.refresh_user_stats_from_sessions(OLD.user_id);
        PERFORM public.refresh_leaderboard_rollups_for_user(OLD.user_id);
    END IF;

    PERFORM public.refresh_user_stats_from_sessions(NEW.user_id);
    PERFORM public.refresh_leaderboard_rollups_for_user(NEW.user_id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_user_stats_from_session
    AFTER INSERT OR UPDATE OR DELETE ON public.sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.refresh_user_projections_from_session();

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

    IF p_metric NOT IN ('doorknocks', 'conversations', 'distance', 'leads') THEN
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
                'conversations', COALESCE(ds.conversations, 0),
                'distance', COALESCE(ds.distance_km, 0.0),
                'leads', COALESCE(ds.leads, 0)
            ) AS daily_snapshot,
            jsonb_build_object(
                'doorknocks', COALESCE(ws.doorknocks, 0),
                'conversations', COALESCE(ws.conversations, 0),
                'distance', COALESCE(ws.distance_km, 0.0),
                'leads', COALESCE(ws.leads, 0)
            ) AS weekly_snapshot,
            jsonb_build_object(
                'doorknocks', COALESCE(ms.doorknocks, 0),
                'conversations', COALESCE(ms.conversations, 0),
                'distance', COALESCE(ms.distance_km, 0.0),
                'leads', COALESCE(ms.leads, 0)
            ) AS monthly_snapshot,
            jsonb_build_object(
                'doorknocks', COALESCE(ats.doorknocks, 0),
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

GRANT EXECUTE ON FUNCTION public.refresh_leaderboard_rollups_for_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) TO authenticated;

DO $$
DECLARE
    v_user_id UUID;
BEGIN
    FOR v_user_id IN
        SELECT DISTINCT s.user_id
        FROM public.sessions s
        WHERE s.user_id IS NOT NULL
    LOOP
        PERFORM public.refresh_user_stats_from_sessions(v_user_id);
        PERFORM public.refresh_leaderboard_rollups_for_user(v_user_id);
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
