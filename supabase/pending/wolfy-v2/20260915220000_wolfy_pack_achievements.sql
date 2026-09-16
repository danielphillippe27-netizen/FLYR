BEGIN;
ALTER TABLE wolfy_pack_events ADD COLUMN details jsonb NOT NULL DEFAULT '{}';
CREATE FUNCTION public.wolfy_pack_claim_day(p_campaign uuid,p_day date) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE cfg wolfy_pack_goals;start_at timestamptz;end_at timestamptz;counts jsonb;metric text;goal integer;milestone integer;
 current_day date;event_start timestamptz;event_expiry timestamptz;
BEGIN
 IF p_campaign IS NULL OR p_day IS NULL OR NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled) THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-pack:'||p_campaign::text,0));
 SELECT * INTO cfg FROM wolfy_pack_goals WHERE campaign_id=p_campaign;
 IF NOT FOUND THEN RETURN; END IF;
 current_day=(clock_timestamp() AT TIME ZONE cfg.timezone)::date;
 IF p_day>current_day THEN RETURN; END IF;
 start_at=p_day::timestamp AT TIME ZONE cfg.timezone;
 end_at=(p_day+1)::timestamp AT TIME ZONE cfg.timezone;
 SELECT coalesce(jsonb_object_agg(kind,n),'{}') INTO counts FROM (
  SELECT kind,count(DISTINCT source) n FROM wolfy_pack_activity(p_campaign)
  WHERE occurred_at>=start_at AND occurred_at<end_at AND occurred_at<=clock_timestamp() GROUP BY kind
 ) totals;
 event_start=CASE WHEN p_day=current_day THEN clock_timestamp()+interval '2 seconds' ELSE end_at-interval '32 seconds' END;
 event_expiry=event_start+interval '30 seconds';
 FOREACH milestone IN ARRAY ARRAY[100,250,500,1000] LOOP
  IF coalesce((counts->>'doors')::bigint,0)>=milestone THEN
   INSERT INTO wolfy_pack_events(campaign_id,kind,source_key,starts_at,expires_at,details)
   VALUES(p_campaign,'pack_milestone','doors:'||p_day::text||':'||milestone,event_start,event_expiry,
    jsonb_build_object('metric','doors','target',milestone,'reporting_day',p_day)) ON CONFLICT(campaign_id,source_key) DO NOTHING;
  END IF;
 END LOOP;
 FOREACH metric IN ARRAY ARRAY['doors','conversations','appointments','verified_sales'] LOOP
  goal=(to_jsonb(cfg)->>metric)::integer;
  IF goal IS NOT NULL AND coalesce((counts->>metric)::bigint,0)>=goal THEN
   INSERT INTO wolfy_pack_events(campaign_id,kind,source_key,starts_at,expires_at,details)
   VALUES(p_campaign,'pack_goal','goal:'||p_day::text||':'||metric,event_start,event_expiry,
    jsonb_build_object('metric',metric,'target',goal,'reporting_day',p_day)) ON CONFLICT(campaign_id,source_key) DO NOTHING;
  END IF;
 END LOOP;
END $$;
CREATE FUNCTION public.wolfy_pack_reconcile_activity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE rowdata jsonb;c uuid;tz text;at_time timestamptz;campaigns uuid[]:='{}';days date[]:='{}';i integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled) THEN RETURN NULL; END IF;
 -- Reconcile both the old and current context when a result is corrected or moved.
 FOREACH rowdata IN ARRAY ARRAY[CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END] LOOP
  IF rowdata IS NULL THEN CONTINUE; END IF;
  IF TG_TABLE_NAME='session_events' THEN
   SELECT campaign_id INTO c FROM sessions WHERE id=(rowdata->>'session_id')::uuid;
  ELSIF TG_TABLE_NAME='contact_activities' THEN
   SELECT campaign_id INTO c FROM contacts WHERE id=(rowdata->>'contact_id')::uuid;
  ELSE c=(rowdata->>'campaign_id')::uuid;
  END IF;
  SELECT timezone INTO tz FROM wolfy_pack_goals WHERE campaign_id=c;
  IF tz IS NULL THEN CONTINUE; END IF;
  at_time=coalesce((rowdata->>'verified_at')::timestamptz,(rowdata->>'created_at')::timestamptz,clock_timestamp());
  campaigns=array_append(campaigns,c);days=array_append(days,(at_time AT TIME ZONE tz)::date);
 END LOOP;
 -- Cross-campaign corrections acquire every campaign lock in the same order.
 FOR c IN SELECT DISTINCT id FROM unnest(campaigns) AS t(id) ORDER BY id LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-pack:'||c::text,0));
 END LOOP;
 FOR i IN 1..coalesce(array_length(campaigns,1),0) LOOP
  PERFORM wolfy_pack_claim_day(campaigns[i],days[i]);
 END LOOP;
 RETURN NULL;
END $$;
CREATE FUNCTION public.wolfy_pack_reconcile_goals() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM wolfy_pack_claim_day(NEW.campaign_id,(clock_timestamp() AT TIME ZONE NEW.timezone)::date);
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_pack_session_achievements AFTER INSERT ON session_events FOR EACH ROW EXECUTE FUNCTION wolfy_pack_reconcile_activity();
CREATE TRIGGER wolfy_pack_lead_achievements AFTER INSERT OR UPDATE OR DELETE ON contacts FOR EACH ROW EXECUTE FUNCTION wolfy_pack_reconcile_activity();
CREATE TRIGGER wolfy_pack_appointment_achievements AFTER INSERT OR UPDATE OR DELETE ON contact_activities FOR EACH ROW EXECUTE FUNCTION wolfy_pack_reconcile_activity();
CREATE TRIGGER wolfy_pack_sale_achievements AFTER INSERT OR UPDATE OR DELETE ON field_sales FOR EACH ROW EXECUTE FUNCTION wolfy_pack_reconcile_activity();
CREATE TRIGGER wolfy_pack_goal_achievements AFTER INSERT OR UPDATE ON wolfy_pack_goals FOR EACH ROW EXECUTE FUNCTION wolfy_pack_reconcile_goals();
REVOKE ALL ON FUNCTION wolfy_pack_claim_day(uuid,date),wolfy_pack_reconcile_activity(),wolfy_pack_reconcile_goals() FROM PUBLIC,anon,authenticated;
COMMIT;
