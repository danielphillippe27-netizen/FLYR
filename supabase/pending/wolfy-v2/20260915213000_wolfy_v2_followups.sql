-- Completion is explicit; a reminder reaching its scheduled time never earns XP.
BEGIN;
ALTER TABLE public.calendar_events ADD COLUMN IF NOT EXISTS completed_at timestamptz;
CREATE FUNCTION public.wolfy_v2_followup_activity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r jsonb;f wolfy_v2_facts;d uuid;valid boolean;u uuid;w uuid;c uuid;
BEGIN
 r=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 u=(r->>'user_id')::uuid;w=(r->>'workspace_id')::uuid;c=(r->>'campaign_id')::uuid;
 valid=TG_OP<>'DELETE' AND r->>'event_type'='follow_up' AND r->>'completed_at' IS NOT NULL AND r->>'deleted_at' IS NULL;
 SELECT * INTO f FROM wolfy_v2_facts WHERE kind='follow_up' AND source_key=(r->>'id');
 IF FOUND THEN
  PERFORM wolfy_v2_fact(f.user_id,f.workspace_id,f.campaign_id,NULL,f.day_id,f.kind,f.source_key,
   valid AND u IS NOT DISTINCT FROM f.user_id,now());
 ELSIF valid AND u IS NOT NULL AND w IS NOT NULL AND EXISTS(SELECT 1 FROM wolfy_v2_config WHERE personal_enabled) THEN
  d=wolfy_v2_day(u,now());
  PERFORM wolfy_v2_fact(u,w,c,NULL,d,'follow_up',r->>'id',true,now());
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER wolfy_v2_followup_activity AFTER INSERT OR UPDATE OR DELETE ON calendar_events
 FOR EACH ROW EXECUTE FUNCTION wolfy_v2_followup_activity();
CREATE FUNCTION public.wolfy_v2_complete_followup(p_event uuid,p_completed boolean) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r calendar_events;
BEGIN
 IF auth.uid() IS NULL OR p_completed IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 SELECT * INTO r FROM calendar_events WHERE id=p_event AND user_id=auth.uid() AND event_type='follow_up' AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Follow-up unavailable' USING ERRCODE='42501'; END IF;
 UPDATE calendar_events SET completed_at=CASE WHEN p_completed THEN coalesce(completed_at,now()) ELSE NULL END,updated_at=now() WHERE id=r.id;
 RETURN wolfy_v2_snapshot();
END $$;
REVOKE ALL ON FUNCTION wolfy_v2_followup_activity() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION wolfy_v2_complete_followup(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION wolfy_v2_complete_followup(uuid,boolean) TO authenticated;
COMMIT;
