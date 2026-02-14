-- Fix: "operator does not exist: text = uuid" when trigger or app touches user_stats
-- Compare both sides as TEXT so RLS works regardless of auth.uid() / column type.

DROP POLICY IF EXISTS "user_stats_select_own" ON public.user_stats;
CREATE POLICY "user_stats_select_own"
    ON public.user_stats FOR SELECT TO authenticated
    USING ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "user_stats_insert_own" ON public.user_stats;
CREATE POLICY "user_stats_insert_own"
    ON public.user_stats FOR INSERT TO authenticated
    WITH CHECK ((user_id::text) = (auth.uid()::text));

DROP POLICY IF EXISTS "user_stats_update_own" ON public.user_stats;
CREATE POLICY "user_stats_update_own"
    ON public.user_stats FOR UPDATE TO authenticated
    USING ((user_id::text) = (auth.uid()::text))
    WITH CHECK ((user_id::text) = (auth.uid()::text));
