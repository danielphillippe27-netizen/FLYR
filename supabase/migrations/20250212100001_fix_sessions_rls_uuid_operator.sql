-- Fix: "operator does not exist: text = uuid" on sessions insert
-- Compare both sides as TEXT so the operator always exists (avoids type mismatch from PostgREST/insert).

DROP POLICY IF EXISTS "Users can read their own sessions" ON public.sessions;
CREATE POLICY "Users can read their own sessions"
    ON public.sessions
    FOR SELECT
    USING ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can insert their own sessions" ON public.sessions;
CREATE POLICY "Users can insert their own sessions"
    ON public.sessions
    FOR INSERT
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can update their own sessions" ON public.sessions;
CREATE POLICY "Users can update their own sessions"
    ON public.sessions
    FOR UPDATE
    USING ((user_id::text) = (auth.uid()::text))
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "Users can delete their own sessions" ON public.sessions;
CREATE POLICY "Users can delete their own sessions"
    ON public.sessions
    FOR DELETE
    USING ((user_id::text) = (auth.uid()::text));
