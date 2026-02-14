-- Fix: user_stats trigger must not run on session INSERT when end_time is NULL
-- (New sessions have end_time = NULL; (NULL - start_time) made time_tracked NULL and violated NOT NULL.)
-- Only update user_stats when the session has ended (end_time IS NOT NULL).

DROP TRIGGER IF EXISTS trigger_update_user_stats_from_session ON public.sessions;
DROP FUNCTION IF EXISTS public.update_user_stats_from_session();

CREATE OR REPLACE FUNCTION public.update_user_stats_from_session()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update user_stats when the session has an end_time (completed session).
    -- New/active sessions have end_time = NULL; skip them to avoid NULL time_tracked.
    IF NEW.end_time IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.user_stats (
        user_id,
        flyers,
        conversations,
        distance_walked,
        time_tracked
    )
    VALUES (
        NEW.user_id,
        COALESCE(NEW.flyers_delivered, 0),
        COALESCE(NEW.conversations, 0),
        COALESCE(NEW.distance_meters, 0) / 1000.0,
        EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60.0
    )
    ON CONFLICT (user_id) DO UPDATE SET
        flyers = user_stats.flyers + EXCLUDED.flyers,
        conversations = user_stats.conversations + EXCLUDED.conversations,
        distance_walked = user_stats.distance_walked + EXCLUDED.distance_walked,
        time_tracked = user_stats.time_tracked + EXCLUDED.time_tracked,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_stats_from_session
    AFTER INSERT OR UPDATE OF end_time ON public.sessions
    FOR EACH ROW
    WHEN (NEW.end_time IS NOT NULL)
    EXECUTE FUNCTION update_user_stats_from_session();

COMMENT ON FUNCTION public.update_user_stats_from_session IS 'Update user_stats when a session is completed (end_time set). Skipped for active sessions.';
