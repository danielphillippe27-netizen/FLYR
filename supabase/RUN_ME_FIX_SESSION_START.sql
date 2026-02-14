-- =============================================================================
-- RUN THIS IN SUPABASE SQL EDITOR to fix "Could not start session" errors
-- (operator does not exist: text = uuid / null time_tracked)
-- Copy the entire file and paste into SQL Editor, then Run.
-- =============================================================================

-- 1) Stop trigger from running on new session insert (end_time = NULL)
DROP TRIGGER IF EXISTS trigger_update_user_stats_from_session ON public.sessions;
DROP FUNCTION IF EXISTS public.update_user_stats_from_session();

CREATE OR REPLACE FUNCTION public.update_user_stats_from_session()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.end_time IS NULL THEN
        RETURN NEW;
    END IF;
    INSERT INTO public.user_stats (
        user_id, flyers, conversations, distance_walked, time_tracked
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

-- 2) Sessions RLS: compare as text so no text = uuid
DROP POLICY IF EXISTS "Users can read their own sessions" ON public.sessions;
CREATE POLICY "Users can read their own sessions" ON public.sessions FOR SELECT
    USING ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can insert their own sessions" ON public.sessions;
CREATE POLICY "Users can insert their own sessions" ON public.sessions FOR INSERT
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can update their own sessions" ON public.sessions;
CREATE POLICY "Users can update their own sessions" ON public.sessions FOR UPDATE
    USING ((user_id::text) = (auth.uid()::text))
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can delete their own sessions" ON public.sessions;
CREATE POLICY "Users can delete their own sessions" ON public.sessions FOR DELETE
    USING ((user_id::text) = (auth.uid()::text));

-- 3) user_stats RLS: compare as text (trigger inserts here when session ends)
DROP POLICY IF EXISTS "user_stats_select_own" ON public.user_stats;
CREATE POLICY "user_stats_select_own" ON public.user_stats FOR SELECT TO authenticated
    USING ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "user_stats_insert_own" ON public.user_stats;
CREATE POLICY "user_stats_insert_own" ON public.user_stats FOR INSERT TO authenticated
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "user_stats_update_own" ON public.user_stats;
CREATE POLICY "user_stats_update_own" ON public.user_stats FOR UPDATE TO authenticated
    USING ((user_id::text) = (auth.uid()::text))
    WITH CHECK ((user_id::text) = (auth.uid()::text));
