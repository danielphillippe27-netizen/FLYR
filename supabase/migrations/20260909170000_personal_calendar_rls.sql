BEGIN;
ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;
-- Support direct native calendar access; no permissive workspace policy may
-- widen this personal boundary on deployments with older calendar policies.
CREATE POLICY personal_calendar_access ON public.calendar_events FOR ALL TO authenticated
USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());
CREATE POLICY personal_calendar_boundary ON public.calendar_events AS RESTRICTIVE FOR ALL TO authenticated
USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());
COMMIT;
