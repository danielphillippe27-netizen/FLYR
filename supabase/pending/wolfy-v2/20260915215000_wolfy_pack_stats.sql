BEGIN;
CREATE TABLE public.wolfy_pack_goals (
 campaign_id uuid PRIMARY KEY REFERENCES public.campaigns(id) ON DELETE CASCADE,
 timezone text NOT NULL DEFAULT 'UTC',
 doors integer CHECK(doors>0),conversations integer CHECK(conversations>0),
 appointments integer CHECK(appointments>0),verified_sales integer CHECK(verified_sales>0),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE wolfy_pack_goals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON wolfy_pack_goals FROM PUBLIC,anon,authenticated;
-- Initialize from an already configured workspace reporting timezone when possible.
INSERT INTO wolfy_pack_goals(campaign_id,timezone)
 SELECT c.id,coalesce((SELECT name FROM pg_timezone_names WHERE name=fs.timezone),'UTC')
 FROM campaigns c LEFT JOIN field_sales_settings fs ON fs.workspace_id=c.workspace_id;

-- Internal event projection contains property keys solely to count unique doors.
-- It is never granted to clients or included verbatim in a response.
CREATE FUNCTION public.wolfy_pack_activity(p_campaign uuid)
 RETURNS TABLE(actor uuid,kind text,source text,occurred_at timestamptz,session_id uuid)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 WITH events AS (
  SELECT e.*,coalesce(nullif(e.building_id,''),e.address_id::text) property,
   (e.created_at AT TIME ZONE coalesce(g.timezone,'UTC'))::date AS reporting_day
  FROM session_events e JOIN sessions s ON s.id=e.session_id LEFT JOIN wolfy_pack_goals g ON g.campaign_id=s.campaign_id
  WHERE s.campaign_id=p_campaign AND e.event_type IN ('completed_manual','completed_auto','flyer_left','conversation','completion_undone')
   AND (e.user_id=s.user_id OR EXISTS(SELECT 1 FROM session_participants sp WHERE sp.session_id=s.id AND sp.user_id=e.user_id
       AND e.created_at>=sp.joined_at AND (sp.left_at IS NULL OR e.created_at<sp.left_at)))
 ), undo AS (
  SELECT DISTINCT ON (session_id,user_id,property) session_id,user_id,property,created_at,id
  FROM events WHERE event_type='completion_undone' ORDER BY session_id,user_id,property,created_at DESC,id DESC
 ), valid AS (
  SELECT e.* FROM events e LEFT JOIN undo u ON u.session_id=e.session_id AND u.user_id=e.user_id AND u.property=e.property
  WHERE e.property IS NOT NULL AND e.event_type<>'completion_undone' AND (u.id IS NULL OR (e.created_at,e.id)>(u.created_at,u.id))
 ), doors AS (
  SELECT session_id,user_id,property,min(created_at) at_time FROM valid GROUP BY session_id,user_id,property,reporting_day
 ), conversations AS (
  SELECT session_id,user_id,property,min(created_at) at_time FROM valid WHERE event_type='conversation'
   AND coalesce(metadata->>'address_status','') IN ('talked','appointment','hot_lead','future_seller') GROUP BY session_id,user_id,property,reporting_day
 )
 SELECT user_id,'doors',property,at_time,session_id FROM doors
 UNION ALL SELECT user_id,'conversations',property,at_time,session_id FROM conversations
 UNION ALL SELECT c.user_id,'leads',c.id::text,c.created_at,NULL::uuid FROM contacts c WHERE c.campaign_id=p_campaign AND c.lead_kind='field'
 UNION ALL SELECT c.user_id,'appointments',a.id::text,a.created_at,NULL::uuid FROM contact_activities a JOIN contacts c ON c.id=a.contact_id
  WHERE c.campaign_id=p_campaign AND a.type='meeting' AND coalesce(to_jsonb(a)->>'status','') NOT IN ('cancelled','canceled')
 UNION ALL SELECT s.rep_id,'verified_sales',s.id::text,s.verified_at,NULL::uuid FROM field_sales s
  WHERE s.campaign_id=p_campaign AND s.status='verified' AND s.verified_by IS NOT NULL AND s.verified_at IS NOT NULL;
$$;
CREATE FUNCTION public.wolfy_pack_stats(p_campaign uuid,p_period text DEFAULT 'today') RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE cfg wolfy_pack_goals;w uuid;start_at timestamptz;end_at timestamptz:=clock_timestamp();result jsonb;show_money boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT is_campaign_member(p_campaign,auth.uid()) THEN RAISE EXCEPTION 'Campaign access required' USING ERRCODE='42501'; END IF;
 IF p_period IS NULL OR p_period NOT IN ('today','week','month','campaign') THEN RAISE EXCEPTION 'Invalid period'; END IF;
 IF NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled) THEN RETURN jsonb_build_object('version',2,'enabled',false); END IF;
 SELECT workspace_id INTO w FROM campaigns WHERE id=p_campaign;
 INSERT INTO wolfy_pack_goals(campaign_id,timezone) VALUES(p_campaign,coalesce(
  (SELECT z.name FROM field_sales_settings fs JOIN pg_timezone_names z ON z.name=fs.timezone WHERE fs.workspace_id=w),'UTC')) ON CONFLICT DO NOTHING;
 SELECT * INTO cfg FROM wolfy_pack_goals WHERE campaign_id=p_campaign;
 start_at=CASE p_period WHEN 'today' THEN date_trunc('day',end_at AT TIME ZONE cfg.timezone) AT TIME ZONE cfg.timezone
 WHEN 'week' THEN date_trunc('week',end_at AT TIME ZONE cfg.timezone) AT TIME ZONE cfg.timezone
 WHEN 'month' THEN date_trunc('month',end_at AT TIME ZONE cfg.timezone) AT TIME ZONE cfg.timezone ELSE '-infinity'::timestamptz END;
 -- Match the existing field-sales revenue boundary; manager alone is not an override.
 show_money=EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id=w AND user_id=auth.uid() AND role IN ('owner','admin'))
  OR EXISTS(SELECT 1 FROM field_sales_settings WHERE workspace_id=w AND team_revenue_visible);
 WITH full_activity AS MATERIALIZED (SELECT * FROM wolfy_pack_activity(p_campaign)), activity AS MATERIALIZED (
  SELECT DISTINCT actor,kind,source,(occurred_at AT TIME ZONE cfg.timezone)::date AS reporting_day
  FROM full_activity WHERE occurred_at>=start_at AND occurred_at<=end_at
 ), actors AS (
  SELECT actor FROM activity UNION SELECT user_id FROM sessions WHERE campaign_id=p_campaign
 ), rows AS (
  SELECT a.actor user_id,coalesce(nullif(p.first_name,''),nullif(split_part(p.full_name,' ',1),''),'Rep') first_name,
   wolfy_v2_stage(a.actor) stage,
   (SELECT count(*) FROM activity WHERE actor=a.actor AND kind='doors') doors,
   (SELECT count(*) FROM activity WHERE actor=a.actor AND kind='conversations') conversations,
   (SELECT count(*) FROM activity WHERE actor=a.actor AND kind='leads') leads,
   (SELECT count(*) FROM activity WHERE actor=a.actor AND kind='appointments') appointments,
   (SELECT count(*) FROM activity WHERE actor=a.actor AND kind='verified_sales') verified_sales,
   coalesce((SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=a.actor AND campaign_id=p_campaign AND occurred_at>=start_at AND occurred_at<=end_at),0) earned_xp,
   (SELECT count(DISTINCT ev.source) FROM full_activity ev WHERE ev.actor=a.actor AND ev.kind='doors'
     AND ev.session_id=(SELECT s.id FROM sessions s WHERE s.campaign_id=p_campaign AND s.end_time IS NULL
      AND (s.user_id=a.actor OR EXISTS(SELECT 1 FROM session_participants sp WHERE sp.session_id=s.id AND sp.user_id=a.actor AND sp.left_at IS NULL))
      ORDER BY s.start_time DESC,s.id LIMIT 1)) current_session_streak,
   CASE WHEN show_money OR a.actor=auth.uid() THEN (SELECT coalesce(sum(value_minor),0)::text FROM field_sales
     WHERE campaign_id=p_campaign AND rep_id=a.actor AND status='verified' AND verified_at>=start_at AND verified_at<=end_at) END revenue_minor
  FROM actors a LEFT JOIN profiles p ON p.id=a.actor WHERE is_campaign_member(p_campaign,a.actor)
 ), totals AS (
  SELECT kind,count(*) value FROM (SELECT DISTINCT kind,source,reporting_day FROM activity) unique_events GROUP BY kind
 )
 SELECT jsonb_build_object('version',2,'enabled',true,'campaign_id',p_campaign,'period',p_period,'timezone',cfg.timezone,'server_time',end_at,
  'manager',wolfy_pack_manager(p_campaign,auth.uid()),'goals',jsonb_strip_nulls(to_jsonb(cfg)-'campaign_id'-'timezone'-'updated_at'),
  'totals',coalesce((SELECT jsonb_object_agg(kind,value) FROM totals),'{}'),
  'currency',(SELECT currency FROM field_sales_settings WHERE workspace_id=w),
  'members',coalesce((SELECT jsonb_agg(to_jsonb(r)||jsonb_build_object('conversion',CASE WHEN r.doors>0 THEN round(r.conversations::numeric/r.doors,4) ELSE NULL END)
    ORDER BY r.doors DESC,r.user_id) FROM rows r),'[]')) INTO result;
 RETURN result;
END $$;
CREATE FUNCTION public.wolfy_pack_set_goals(p_campaign uuid,p_doors integer,p_conversations integer,p_appointments integer,p_verified_sales integer,p_timezone text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE cfg wolfy_pack_goals;
BEGIN
 IF auth.uid() IS NULL OR NOT is_campaign_member(p_campaign,auth.uid()) OR NOT wolfy_pack_manager(p_campaign,auth.uid()) THEN
  RAISE EXCEPTION 'Manager access required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'Invalid timezone'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-pack:'||p_campaign::text,0));
 SELECT * INTO cfg FROM wolfy_pack_goals WHERE campaign_id=p_campaign FOR UPDATE;
 IF cfg.timezone IS NOT NULL AND cfg.timezone<>p_timezone AND EXISTS(SELECT 1 FROM wolfy_pack_activity(p_campaign)) THEN
  RAISE EXCEPTION 'Campaign reporting timezone is fixed after activity begins'; END IF;
 INSERT INTO wolfy_pack_goals(campaign_id,timezone,doors,conversations,appointments,verified_sales)
 VALUES(p_campaign,p_timezone,p_doors,p_conversations,p_appointments,p_verified_sales)
 ON CONFLICT(campaign_id) DO UPDATE SET timezone=excluded.timezone,doors=excluded.doors,conversations=excluded.conversations,
  appointments=excluded.appointments,verified_sales=excluded.verified_sales,updated_at=now();
 RETURN wolfy_pack_stats(p_campaign,'today');
END $$;
REVOKE ALL ON FUNCTION wolfy_pack_activity(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION wolfy_pack_stats(uuid,text),wolfy_pack_set_goals(uuid,integer,integer,integer,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION wolfy_pack_stats(uuid,text),wolfy_pack_set_goals(uuid,integer,integer,integer,integer,text) TO authenticated;
COMMIT;
