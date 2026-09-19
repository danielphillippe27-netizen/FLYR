BEGIN;
-- Read-only, caller-RLS-scoped facts. No names, notes or reward reconciliation.
CREATE FUNCTION public.wolfy_coach_context(p_workspace uuid, p_timezone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE t timestamptz := now(); local_now timestamp; day_start timestamptz; week_start timestamptz; facts jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id=p_workspace AND user_id=auth.uid()) THEN
  RAISE EXCEPTION 'Workspace access required' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'Invalid timezone'; END IF;
 local_now := t AT TIME ZONE p_timezone;
 day_start := date_trunc('day',local_now) AT TIME ZONE p_timezone;
 week_start := date_trunc('week',local_now) AT TIME ZONE p_timezone;
 facts := wolfy_home_metrics(p_workspace,day_start,week_start,t);
 RETURN jsonb_build_object('metrics',facts,
  'goals',(SELECT jsonb_build_object('daily',daily_door_goal,'weekly',weekly_door_goal) FROM user_profiles WHERE user_id=auth.uid()),
  'days_remaining',8-extract(isodow FROM local_now)::integer,
  'overdue',(SELECT count(*) FROM contacts WHERE user_id=auth.uid() AND workspace_id=p_workspace
    AND (reminder_date IS NOT NULL OR lower(status) IN ('follow_up','not_home','no_answer','warm'))
    AND coalesce(reminder_date,updated_at,created_at)<t),
  'upcoming',(SELECT count(*) FROM (SELECT DISTINCT a.contact_id,a.timestamp,coalesce(trim(a.note),'') FROM contact_activities a
    JOIN contacts c ON c.id=a.contact_id WHERE c.user_id=auth.uid() AND c.workspace_id=p_workspace
    AND a.type='meeting' AND a.timestamp>=t) appointments),
  'as_of',t,'local_day',local_now::date);
END $$;
REVOKE ALL ON FUNCTION public.wolfy_coach_context(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_coach_context(uuid,text) TO authenticated;

-- One cache row per scope; no chat transcript persistence. Backend-only access.
CREATE TABLE public.wolfy_coach_cache (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
 fingerprint text NOT NULL, message text NOT NULL, generated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,workspace_id)
);
ALTER TABLE public.wolfy_coach_cache ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wolfy_coach_cache FROM anon,authenticated;
GRANT ALL ON public.wolfy_coach_cache TO service_role;
CREATE TABLE public.wolfy_coach_budget (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 day date NOT NULL, calls integer NOT NULL, last_call timestamptz NOT NULL
);
ALTER TABLE public.wolfy_coach_budget ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wolfy_coach_budget FROM anon,authenticated;
GRANT ALL ON public.wolfy_coach_budget TO service_role;
-- Atomic across servers AND workspaces. A maximum of 30 paid attempts/user/UTC day.
CREATE FUNCTION public.wolfy_coach_reserve(p_user uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE n integer;
BEGIN
 INSERT INTO wolfy_coach_budget(user_id,day,calls,last_call) VALUES(p_user,(now() AT TIME ZONE 'UTC')::date,1,now())
 ON CONFLICT(user_id) DO UPDATE SET
  day=excluded.day,calls=CASE WHEN wolfy_coach_budget.day=excluded.day THEN wolfy_coach_budget.calls+1 ELSE 1 END,last_call=now()
 WHERE (wolfy_coach_budget.day<>excluded.day OR wolfy_coach_budget.calls<30)
  AND wolfy_coach_budget.last_call<=now()-interval '5 seconds'
 RETURNING calls INTO n;
 RETURN n IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_coach_reserve(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wolfy_coach_reserve(uuid) TO service_role;
COMMIT;
