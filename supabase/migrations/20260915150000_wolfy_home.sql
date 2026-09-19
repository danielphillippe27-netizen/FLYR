-- Personal Home targets. Existing workspace/team targets are intentionally independent.
BEGIN;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS daily_door_goal integer;
ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_daily_door_goal_positive
  CHECK (daily_door_goal IS NULL OR daily_door_goal > 0);

CREATE OR REPLACE FUNCTION public.wolfy_protect_personal_goals()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF (NEW.daily_door_goal IS DISTINCT FROM OLD.daily_door_goal
      OR NEW.weekly_door_goal IS DISTINCT FROM OLD.weekly_door_goal)
     AND auth.role() = 'authenticated' AND NEW.user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Only the owner can change personal goals' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER wolfy_personal_goal_owner BEFORE UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.wolfy_protect_personal_goals();

CREATE OR REPLACE FUNCTION public.wolfy_save_personal_goals(p_user uuid, p_daily integer, p_weekly integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF p_user IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Goal owner mismatch' USING ERRCODE = '42501'; END IF;
  IF p_daily <= 0 OR p_weekly <= 0 THEN RAISE EXCEPTION 'Targets must be positive'; END IF;
  INSERT INTO public.user_profiles(user_id, daily_door_goal, weekly_door_goal)
  VALUES(auth.uid(), p_daily, p_weekly)
  ON CONFLICT(user_id) DO UPDATE SET daily_door_goal = excluded.daily_door_goal,
    weekly_door_goal = excluded.weekly_door_goal;
  SELECT jsonb_build_object('daily_door_goal', daily_door_goal, 'weekly_door_goal', weekly_door_goal)
  INTO result FROM public.user_profiles WHERE user_id = auth.uid();
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_save_personal_goals(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wolfy_save_personal_goals(uuid, integer, integer) TO authenticated;

-- SECURITY INVOKER preserves table RLS in addition to the explicit actor/workspace filters.
CREATE OR REPLACE FUNCTION public.wolfy_home_metrics(
  p_workspace uuid, p_day timestamptz, p_week timestamptz, p_until timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF p_workspace IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.workspace_members WHERE workspace_id = p_workspace AND user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'Workspace access required' USING ERRCODE = '42501'; END IF;
  IF p_week > p_day OR p_day > p_until OR p_until - p_week > interval '8 days' THEN
    RAISE EXCEPTION 'Invalid reporting interval';
  END IF;
  WITH ranked AS (
    SELECT e.*, row_number() OVER (
      PARTITION BY e.session_id, coalesce(e.building_id::text, e.address_id::text, e.id::text)
      ORDER BY e.created_at DESC, e.id DESC
    ) AS ordinal
    FROM public.session_events e JOIN public.sessions s ON s.id = e.session_id
    WHERE s.user_id = auth.uid() AND s.workspace_id = p_workspace
      AND e.created_at >= p_week AND e.created_at <= p_until
      AND e.event_type IN ('flyer_left', 'conversation', 'completed_manual', 'completed_auto', 'completion_undone')
  ), visits AS (
    SELECT * FROM ranked WHERE ordinal = 1 AND event_type <> 'completion_undone'
  ) SELECT jsonb_build_object(
    'doors', (SELECT count(*) FROM visits WHERE created_at >= p_day),
    'weekly_doors', (SELECT count(*) FROM visits),
    'conversations', (SELECT count(*) FROM visits WHERE created_at >= p_day AND event_type = 'conversation'
      AND coalesce(metadata->>'address_status', outcome, '') NOT IN ('no_answer', 'noAnswer', 'do_not_knock', 'doNotKnock')),
    'leads', (SELECT count(*) FROM public.contacts WHERE user_id = auth.uid() AND workspace_id = p_workspace
      AND lead_kind = 'field' AND created_at >= p_day AND created_at <= p_until),
    'appointments', (SELECT count(*) FROM public.contact_activities a JOIN public.contacts c ON c.id = a.contact_id
      WHERE c.user_id = auth.uid() AND c.workspace_id = p_workspace AND a.type = 'meeting'
        AND a.created_at >= p_day AND a.created_at <= p_until)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_home_metrics(uuid, timestamptz, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wolfy_home_metrics(uuid, timestamptz, timestamptz, timestamptz) TO authenticated;
COMMIT;
