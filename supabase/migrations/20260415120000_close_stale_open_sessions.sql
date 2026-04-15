-- Close abandoned open sessions so leaderboard rollups and stats can finalize.
-- Open sessions (end_time IS NULL) are excluded from leaderboard_rollups rebuild and from get_leaderboard.
--
-- Call from a scheduled job (e.g. Supabase pg_cron + service_role) or manually in SQL Editor:
--   SELECT public.close_stale_open_sessions(8, 48);

BEGIN;

CREATE OR REPLACE FUNCTION public.close_stale_open_sessions(
    p_idle_hours integer DEFAULT 8,
    p_max_open_hours integer DEFAULT 48
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count integer;
    v_idle integer;
    v_max_open integer;
BEGIN
    v_idle := GREATEST(COALESCE(p_idle_hours, 8), 1);
    v_max_open := GREATEST(COALESCE(p_max_open_hours, 48), 1);

    UPDATE public.sessions s
    SET
        end_time = now(),
        doors_hit = GREATEST(COALESCE(s.doors_hit, s.completed_count, s.flyers_delivered, 0), 0)::integer,
        flyers_delivered = GREATEST(COALESCE(s.flyers_delivered, s.completed_count, 0), 0)::integer
    WHERE s.end_time IS NULL
      AND (
          s.updated_at < now() - make_interval(hours => v_idle)
          OR s.start_time < now() - make_interval(hours => v_max_open)
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.close_stale_open_sessions(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_stale_open_sessions(integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.close_stale_open_sessions(integer, integer) TO postgres;

COMMENT ON FUNCTION public.close_stale_open_sessions(integer, integer) IS
    'Sets end_time on stale open sessions (no update for p_idle_hours or older than p_max_open_hours from start). Triggers user_stats + leaderboard_rollups via existing session trigger.';

NOTIFY pgrst, 'reload schema';

COMMIT;
