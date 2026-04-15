-- Rolling "First 30 Days" style leaderboard: scores only finalized (ended) sessions in the last 30 days.
-- Aligns with leaderboard_rollups semantics (sessions must have end_time set).
-- Replaces prior RPC definitions if they existed (same parameter names as iOS: p_challenge_slug, p_window, p_limit).

BEGIN;

DROP FUNCTION IF EXISTS public.get_challenge_rolling_leaderboard(text, text, integer);
DROP FUNCTION IF EXISTS public.count_challenge_rolling_participants(text);

CREATE OR REPLACE FUNCTION public.get_challenge_rolling_leaderboard(
    p_challenge_slug text,
    p_window text,
    p_limit integer DEFAULT 50
)
RETURNS TABLE (
    user_id uuid,
    display_name text,
    score bigint,
    "rank" bigint,
    active_badges jsonb,
    current_streak integer,
    accountability_posted boolean,
    latest_session_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH door_rows AS (
        SELECT
            s.user_id AS uid,
            s.id AS session_id,
            s.end_time AS ended_at,
            GREATEST(COALESCE(s.doors_hit, s.completed_count, s.flyers_delivered, 0), 0)::bigint AS doors
        FROM public.sessions s
        WHERE s.end_time IS NOT NULL
          AND s.start_time >= now() - interval '30 days'
    ),
    agg AS (
        SELECT
            dr.uid AS agg_uid,
            SUM(dr.doors)::bigint AS agg_score
        FROM door_rows dr
        GROUP BY dr.uid
        HAVING SUM(dr.doors) > 0
    ),
    with_latest AS (
        SELECT
            a.agg_uid,
            a.agg_score,
            (
                SELECT s2.id
                FROM public.sessions s2
                WHERE s2.user_id = a.agg_uid
                  AND s2.end_time IS NOT NULL
                  AND s2.start_time >= now() - interval '30 days'
                ORDER BY s2.end_time DESC NULLS LAST
                LIMIT 1
            ) AS latest_sid
        FROM agg a
    ),
    ranked AS (
        SELECT
            wl.agg_uid,
            wl.agg_score,
            wl.latest_sid,
            ROW_NUMBER() OVER (ORDER BY wl.agg_score DESC, wl.agg_uid ASC)::bigint AS user_rank
        FROM with_latest wl
    )
    SELECT
        r.agg_uid AS user_id,
        COALESCE(
            NULLIF(
                BTRIM(CONCAT_WS(
                    ' ',
                    NULLIF(BTRIM(p.first_name), ''),
                    NULLIF(BTRIM(p.last_name), '')
                )),
                ''
            ),
            NULLIF(BTRIM(p.full_name), ''),
            NULLIF(BTRIM(au.raw_user_meta_data->>'full_name'), ''),
            NULLIF(BTRIM(SPLIT_PART(au.email, '@', 1)), ''),
            'Member'
        ) AS display_name,
        r.agg_score AS score,
        r.user_rank AS "rank",
        '[]'::jsonb AS active_badges,
        0::integer AS current_streak,
        false AS accountability_posted,
        r.latest_sid AS latest_session_id
    FROM ranked r
    INNER JOIN auth.users au ON au.id = r.agg_uid
    LEFT JOIN public.profiles p ON p.id = r.agg_uid
    ORDER BY r.user_rank ASC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
$$;

CREATE OR REPLACE FUNCTION public.count_challenge_rolling_participants(p_challenge_slug text)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*)::integer
    FROM (
        SELECT s.user_id
        FROM public.sessions s
        WHERE s.end_time IS NOT NULL
          AND s.start_time >= now() - interval '30 days'
        GROUP BY s.user_id
        HAVING SUM(GREATEST(COALESCE(s.doors_hit, s.completed_count, s.flyers_delivered, 0), 0)) > 0
    ) t;
$$;

REVOKE ALL ON FUNCTION public.get_challenge_rolling_leaderboard(text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.count_challenge_rolling_participants(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_challenge_rolling_leaderboard(text, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_challenge_rolling_participants(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_challenge_rolling_leaderboard(text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.count_challenge_rolling_participants(text) TO service_role;

COMMENT ON FUNCTION public.get_challenge_rolling_leaderboard(text, text, integer) IS
    'Rolling leaderboard: sums doors from ended sessions only (last 30 days). p_challenge_slug / p_window reserved for template-specific rules.';
COMMENT ON FUNCTION public.count_challenge_rolling_participants(text) IS
    'Count of users with positive door totals from ended sessions in the last 30 days.';

NOTIFY pgrst, 'reload schema';

COMMIT;
