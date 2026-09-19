-- Shared-session presence uses existing participant membership. No new GPS collector.
BEGIN;
CREATE FUNCTION public.wolfy_pack_session_member(p_campaign uuid,p_subject uuid,p_session uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM sessions s WHERE s.id=p_session AND s.campaign_id=p_campaign
  AND s.end_time IS NULL AND NOT coalesce(s.is_paused,false)
  AND public.is_campaign_member(p_campaign,p_subject)
  AND (s.user_id=p_subject OR EXISTS(SELECT 1 FROM session_participants sp
   WHERE sp.session_id=s.id AND sp.campaign_id=s.campaign_id AND sp.user_id=p_subject
   AND sp.joined_at<=now() AND sp.left_at IS NULL)))
$$;
REVOKE ALL ON FUNCTION public.wolfy_pack_session_member(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.wolfy_pack_location_allowed(p_campaign uuid,p_subject uuid,p_session uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT auth.uid() IS NOT NULL
 AND EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled)
 AND public.is_campaign_member(p_campaign,auth.uid())
 AND public.is_campaign_member(p_campaign,p_subject)
 AND EXISTS(SELECT 1 FROM wolfy_v2_profiles WHERE user_id=p_subject AND sharing_enabled)
 AND wolfy_pack_session_member(p_campaign,p_subject,p_session)
 AND EXISTS(SELECT 1 FROM campaigns c LEFT JOIN wolfy_pack_policy p ON p.workspace_id=c.workspace_id
 WHERE c.id=p_campaign AND (p_subject=auth.uid()
 OR CASE WHEN wolfy_pack_manager(p_campaign,auth.uid()) THEN coalesce(p.managers_visible,true)
 ELSE coalesce(p.teammates_visible,true) END))
$$;

CREATE OR REPLACE FUNCTION public.wolfy_pack_clear_presence(p_campaign uuid,p_session uuid) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL THEN
  RAISE EXCEPTION 'Session access required' USING ERRCODE='42501'; END IF;
 UPDATE campaign_presence SET lat=NULL,lng=NULL,location_fixed_at=NULL,location_accuracy=NULL,heading=NULL,speed=NULL,
  status='inactive',activity_state='paused',updated_at=now()
 WHERE campaign_id=p_campaign AND user_id=auth.uid() AND session_id=p_session;
END $$;

CREATE OR REPLACE FUNCTION public.wolfy_pack_send_howl(p_campaign uuid,p_recipient uuid,p_request uuid) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u uuid:=auth.uid(); result uuid;
BEGIN
 IF u IS NULL OR p_recipient=u OR NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled)
 OR NOT public.is_campaign_member(p_campaign,u) OR NOT public.is_campaign_member(p_campaign,p_recipient)
 OR NOT EXISTS(SELECT 1 FROM sessions s WHERE wolfy_pack_session_member(p_campaign,u,s.id))
 OR NOT EXISTS(SELECT 1 FROM sessions s WHERE wolfy_pack_session_member(p_campaign,p_recipient,s.id))
 THEN RAISE EXCEPTION 'Active shared campaign required' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-howl:'||u::text,0));
 SELECT id INTO result FROM wolfy_pack_events WHERE campaign_id=p_campaign AND source_key='howl:'||u::text||':'||p_request::text;
 IF result IS NOT NULL THEN RETURN result; END IF;
 IF (SELECT count(*) FROM wolfy_pack_events WHERE actor_id=u AND kind='howl' AND created_at>now()-interval '1 minute')>=3
 OR EXISTS(SELECT 1 FROM wolfy_pack_events WHERE actor_id=u AND recipient_id=p_recipient AND kind='howl' AND created_at>now()-interval '5 minutes')
 THEN RAISE EXCEPTION 'Howl cooldown active' USING ERRCODE='P0001'; END IF;
 INSERT INTO wolfy_pack_events(campaign_id,actor_id,recipient_id,kind,source_key,expires_at)
 VALUES(p_campaign,u,p_recipient,'howl','howl:'||u::text||':'||p_request::text,now()+interval '60 seconds') RETURNING id INTO result;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.wolfy_pack_snapshot(p_campaign uuid,p_after timestamptz DEFAULT NULL) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result jsonb; enabled boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_campaign_member(p_campaign,auth.uid()) THEN
  RAISE EXCEPTION 'Campaign access required' USING ERRCODE='42501';
 END IF;
 SELECT pack_enabled INTO enabled FROM wolfy_v2_config;
 IF NOT enabled THEN RETURN jsonb_build_object('version',2,'enabled',false,'members','[]'::jsonb,'events','[]'::jsonb,'server_time',now()); END IF;
 WITH scoped_activity AS MATERIALIZED (SELECT actor,occurred_at FROM wolfy_pack_activity(p_campaign)), roster AS (
  SELECT DISTINCT s.user_id FROM sessions s WHERE s.campaign_id=p_campaign AND s.end_time IS NULL
  AND public.is_campaign_member(p_campaign,s.user_id)
  UNION
  SELECT sp.user_id FROM session_participants sp JOIN sessions s ON s.id=sp.session_id
  WHERE s.campaign_id=p_campaign AND sp.campaign_id=p_campaign AND s.end_time IS NULL
   AND sp.left_at IS NULL AND sp.joined_at<=now() AND public.is_campaign_member(p_campaign,sp.user_id)
 ), members AS (
  SELECT r.user_id,coalesce(nullif(p.first_name,''),nullif(split_part(p.full_name,' ',1),''),'Rep') AS first_name,
   wolfy_v2_stage(r.user_id) AS stage,s.id AS session_id,s.is_paused,
   s.start_time,s.active_seconds,pr.updated_at AS heartbeat_at,
   CASE WHEN wolfy_pack_location_allowed(p_campaign,r.user_id,s.id)
      AND pr.session_id=s.id AND pr.status='active' AND pr.location_fixed_at>now()-interval '180 seconds'
      AND pr.location_fixed_at<=now()+interval '5 seconds' THEN
    jsonb_build_object('latitude',pr.lat,'longitude',pr.lng,'accuracy',pr.location_accuracy,
     'heading',pr.heading,'speed',pr.speed,'fixedAt',pr.location_fixed_at,'sequence',pr.sequence)
   ELSE NULL END AS fix,
   CASE WHEN s.is_paused THEN 'paused' WHEN pr.updated_at<now()-interval '60 seconds' OR pr.updated_at IS NULL THEN 'unknown'
        ELSE pr.activity_state END AS activity,
   (SELECT max(occurred_at) FROM scoped_activity WHERE actor=r.user_id) AS last_activity_at
  FROM roster r LEFT JOIN profiles p ON p.id=r.user_id
  JOIN LATERAL (SELECT * FROM sessions x WHERE x.campaign_id=p_campaign AND x.end_time IS NULL
    AND (x.user_id=r.user_id OR EXISTS(SELECT 1 FROM session_participants sp
     WHERE sp.session_id=x.id AND sp.campaign_id=p_campaign AND sp.user_id=r.user_id
      AND sp.left_at IS NULL AND sp.joined_at<=now()))
    ORDER BY (EXISTS(SELECT 1 FROM campaign_presence cp WHERE cp.campaign_id=p_campaign
     AND cp.user_id=r.user_id AND cp.session_id=x.id AND cp.status='active')) DESC,x.start_time DESC,x.id LIMIT 1) s ON true
  LEFT JOIN campaign_presence pr ON pr.campaign_id=p_campaign AND pr.user_id=r.user_id
 )
 SELECT jsonb_build_object('version',2,'enabled',true,'campaign_id',p_campaign,'server_time',now(),
  'manager',wolfy_pack_manager(p_campaign,auth.uid()),
  'summary',CASE WHEN p_after IS NULL THEN (SELECT jsonb_build_object(
    'goals',count(*) FILTER(WHERE kind='pack_goal'),'milestones',count(*) FILTER(WHERE kind='pack_milestone'))
    FROM wolfy_pack_events WHERE campaign_id=p_campaign AND kind IN ('pack_goal','pack_milestone')
    AND created_at>now()-interval '24 hours') END,
  'members',coalesce((SELECT jsonb_agg(to_jsonb(m)) FROM members m),'[]'::jsonb),
  'events',coalesce((SELECT jsonb_agg(to_jsonb(e)) FROM (
    SELECT id,campaign_id,actor_id,recipient_id,kind,created_at,starts_at,expires_at,animation_seed,details
    FROM wolfy_pack_events WHERE campaign_id=p_campaign
      AND (recipient_id IS NULL OR recipient_id=auth.uid() OR actor_id=auth.uid())
      AND created_at>greatest(coalesce(p_after,now()),now()-interval '1 minute')
      AND expires_at>now() ORDER BY CASE kind WHEN 'pack_goal' THEN 0 WHEN 'pack_milestone' THEN 1 ELSE 2 END,created_at DESC,id LIMIT 50
   ) e),'[]'::jsonb)) INTO result;
 RETURN result;
END $$;


CREATE FUNCTION public.wolfy_pack_participant_privacy() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 -- Clear even with the feature disabled, so re-enabling cannot resurrect an old fix.
 IF TG_OP='DELETE' THEN
  UPDATE campaign_presence SET lat=NULL,lng=NULL,location_fixed_at=NULL,location_accuracy=NULL,
   heading=NULL,speed=NULL,status='inactive',activity_state='paused',updated_at=now()
   WHERE user_id=OLD.user_id AND session_id=OLD.session_id;
  RETURN OLD;
 END IF;
 IF NEW.left_at IS NOT NULL OR NEW.joined_at>now() OR NEW.user_id IS DISTINCT FROM OLD.user_id
  OR NEW.session_id IS DISTINCT FROM OLD.session_id OR NEW.campaign_id IS DISTINCT FROM OLD.campaign_id THEN
  UPDATE campaign_presence SET lat=NULL,lng=NULL,location_fixed_at=NULL,location_accuracy=NULL,
   heading=NULL,speed=NULL,status='inactive',activity_state='paused',updated_at=now()
   WHERE user_id=OLD.user_id AND session_id=OLD.session_id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_pack_participant_privacy AFTER UPDATE OR DELETE ON public.session_participants
 FOR EACH ROW EXECUTE FUNCTION public.wolfy_pack_participant_privacy();
REVOKE ALL ON FUNCTION public.wolfy_pack_participant_privacy() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.wolfy_pack_stats(p_campaign uuid,p_period text DEFAULT 'today') RETURNS jsonb
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
  UNION SELECT sp.user_id FROM session_participants sp JOIN sessions s ON s.id=sp.session_id
   WHERE s.campaign_id=p_campaign AND sp.campaign_id=p_campaign AND s.end_time IS NULL
    AND sp.left_at IS NULL AND sp.joined_at<=now()
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
      AND (s.user_id=a.actor OR EXISTS(SELECT 1 FROM session_participants sp WHERE sp.session_id=s.id AND sp.user_id=a.actor AND sp.campaign_id=p_campaign AND sp.left_at IS NULL AND sp.joined_at<=now()))
      ORDER BY (EXISTS(SELECT 1 FROM campaign_presence cp WHERE cp.user_id=a.actor
       AND cp.campaign_id=p_campaign AND cp.session_id=s.id AND cp.status='active')) DESC,s.start_time DESC,s.id LIMIT 1)) current_session_streak,
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
COMMIT;
