-- Make leaderboard names follow onboarding/profile edits by preferring public.profiles.
-- Avatar remains sourced from existing public/profile auth URLs; private storage images are not exposed here.

BEGIN;

DROP FUNCTION IF EXISTS public.get_leaderboard(text, text, uuid);

CREATE OR REPLACE FUNCTION public.get_leaderboard(
    p_metric TEXT DEFAULT 'flyers',
    p_timeframe TEXT DEFAULT 'weekly',
    p_workspace_id uuid DEFAULT NULL
)
RETURNS TABLE (
    id TEXT,
    name TEXT,
    avatar_url TEXT,
    brokerage TEXT,
    rank INTEGER,
    flyers INTEGER,
    leads INTEGER,
    conversations INTEGER,
    distance DOUBLE PRECISION,
    daily JSONB,
    weekly JSONB,
    all_time JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
BEGIN
    CASE p_timeframe
        WHEN 'daily' THEN v_start_date := date_trunc('day', NOW());
        WHEN 'weekly' THEN v_start_date := date_trunc('week', NOW());
        WHEN 'monthly' THEN v_start_date := date_trunc('month', NOW());
        WHEN 'all_time' THEN v_start_date := '1970-01-01'::TIMESTAMPTZ;
        ELSE v_start_date := date_trunc('week', NOW());
    END CASE;

    IF p_workspace_id IS NOT NULL THEN
        RETURN QUERY
        WITH workspace_user_ids AS (
            SELECT wm.user_id
            FROM public.workspace_members wm
            WHERE wm.workspace_id = p_workspace_id
            UNION
            SELECT w.owner_id FROM public.workspaces w WHERE w.id = p_workspace_id
        ),
        session_stats AS (
            SELECT
                s.user_id,
                COALESCE(SUM(s.flyers_delivered), 0)::INTEGER AS session_flyers,
                COALESCE(SUM(s.conversations), 0)::INTEGER AS session_conversations,
                COALESCE(SUM(s.distance_meters), 0)::DOUBLE PRECISION / 1000.0 AS session_distance_km
            FROM public.sessions s
            WHERE s.start_time >= v_start_date
              AND (s.workspace_id = p_workspace_id OR (s.workspace_id IS NULL AND s.user_id IN (SELECT user_id FROM workspace_user_ids)))
            GROUP BY s.user_id
        ),
        ranked_users AS (
            SELECT
                au.id::TEXT AS user_id,
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
                COALESCE(ss.session_flyers, 0) AS user_flyers,
                COALESCE(ss.session_conversations, 0) AS user_conversations,
                COALESCE(ss.session_distance_km, 0.0) AS user_distance,
                jsonb_build_object(
                    'flyers', COALESCE(ss.session_flyers, 0),
                    'conversations', COALESCE(ss.session_conversations, 0),
                    'distance', COALESCE(ss.session_distance_km, 0.0),
                    'leads', 0
                ) AS snapshot
            FROM auth.users au
            INNER JOIN workspace_user_ids wu ON au.id = wu.user_id
            LEFT JOIN public.profiles p ON p.id = au.id
            LEFT JOIN session_stats ss ON au.id = ss.user_id
            WHERE COALESCE(ss.session_flyers, 0) > 0 OR COALESCE(ss.session_conversations, 0) > 0
        )
        SELECT
            ru.user_id,
            ru.display_name,
            ru.user_avatar,
            ru.user_brokerage,
            (ROW_NUMBER() OVER (
                ORDER BY
                    CASE p_metric
                        WHEN 'flyers' THEN ru.user_flyers
                        WHEN 'conversations' THEN ru.user_conversations
                        WHEN 'distance' THEN ru.user_distance::INTEGER
                        ELSE ru.user_flyers
                    END DESC
            ))::INTEGER,
            ru.user_flyers,
            0::INTEGER,
            ru.user_conversations,
            ru.user_distance,
            ru.snapshot,
            ru.snapshot,
            ru.snapshot
        FROM ranked_users ru
        ORDER BY 5
        LIMIT 100;
    ELSE
        RETURN QUERY
        WITH session_stats AS (
            SELECT
                s.user_id,
                COALESCE(SUM(s.flyers_delivered), 0)::INTEGER AS session_flyers,
                COALESCE(SUM(s.conversations), 0)::INTEGER AS session_conversations,
                COALESCE(SUM(s.distance_meters), 0)::DOUBLE PRECISION / 1000.0 AS session_distance_km
            FROM public.sessions s
            WHERE s.start_time >= v_start_date
            GROUP BY s.user_id
        ),
        ranked_users AS (
            SELECT
                au.id::TEXT AS user_id,
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
                COALESCE(ss.session_flyers, 0) AS user_flyers,
                COALESCE(ss.session_conversations, 0) AS user_conversations,
                COALESCE(ss.session_distance_km, 0.0) AS user_distance,
                jsonb_build_object(
                    'flyers', COALESCE(ss.session_flyers, 0),
                    'conversations', COALESCE(ss.session_conversations, 0),
                    'distance', COALESCE(ss.session_distance_km, 0.0),
                    'leads', 0
                ) AS snapshot
            FROM auth.users au
            LEFT JOIN public.profiles p ON p.id = au.id
            LEFT JOIN session_stats ss ON au.id = ss.user_id
            WHERE COALESCE(ss.session_flyers, 0) > 0 OR COALESCE(ss.session_conversations, 0) > 0
        )
        SELECT
            ru.user_id,
            ru.display_name,
            ru.user_avatar,
            ru.user_brokerage,
            (ROW_NUMBER() OVER (
                ORDER BY
                    CASE p_metric
                        WHEN 'flyers' THEN ru.user_flyers
                        WHEN 'conversations' THEN ru.user_conversations
                        WHEN 'distance' THEN ru.user_distance::INTEGER
                        ELSE ru.user_flyers
                    END DESC
            ))::INTEGER,
            ru.user_flyers,
            0::INTEGER,
            ru.user_conversations,
            ru.user_distance,
            ru.snapshot,
            ru.snapshot,
            ru.snapshot
        FROM ranked_users ru
        ORDER BY 5
        LIMIT 100;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) TO authenticated;

COMMENT ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) IS 'Leaderboard with optional workspace scope; prefers profile first/last name over auth metadata.';

COMMIT;
