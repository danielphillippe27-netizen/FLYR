-- Historical participation is checked at the persisted business event time.
BEGIN;
CREATE FUNCTION public.wolfy_v2_session_actor_at(p_session uuid,p_actor uuid,p_at timestamptz) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM sessions s WHERE s.id=p_session
  AND (s.user_id=p_actor OR EXISTS(SELECT 1 FROM session_participants sp
   WHERE sp.session_id=s.id AND sp.campaign_id=s.campaign_id AND sp.user_id=p_actor
   AND sp.joined_at<=p_at AND (sp.left_at IS NULL OR p_at<sp.left_at))))
$$;
REVOKE ALL ON FUNCTION public.wolfy_v2_session_actor_at(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.wolfy_v2_session_activity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s sessions;d uuid;key text;property text;f wolfy_v2_facts;latest session_events;
 undone session_events;first_completion session_events;conversation_exists boolean;
BEGIN
 IF NEW.event_type NOT IN ('completion_undone','flyer_left','conversation','completed_manual','completed_auto') THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE personal_enabled)
  AND NOT EXISTS(SELECT 1 FROM wolfy_v2_facts WHERE session_id=NEW.session_id) THEN RETURN NEW; END IF;
 SELECT * INTO s FROM sessions WHERE id=NEW.session_id;
 IF s.workspace_id IS NULL OR NEW.user_id IS NULL THEN RETURN NEW; END IF;
 IF NOT wolfy_v2_session_actor_at(s.id,NEW.user_id,NEW.created_at)
  AND NOT (NEW.event_type='completion_undone' AND EXISTS(SELECT 1 FROM wolfy_v2_facts
   WHERE user_id=NEW.user_id AND session_id=s.id AND kind='door'
    AND source_key=coalesce(nullif(NEW.building_id,''),NEW.address_id::text)||':'||s.id::text))
 THEN RETURN NEW; END IF;
 property=coalesce(nullif(NEW.building_id,''),NEW.address_id::text);
 IF property IS NULL THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-user:'||NEW.user_id::text,0));
 key=property||':'||s.id::text;
 -- Rebuild this property's state from durable event order, not upload arrival order.
 SELECT * INTO latest FROM session_events e WHERE e.session_id=s.id AND e.user_id=NEW.user_id
  AND (wolfy_v2_session_actor_at(s.id,e.user_id,e.created_at) OR e.event_type='completion_undone')
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property
  AND e.event_type IN ('completion_undone','flyer_left','conversation','completed_manual','completed_auto')
  ORDER BY e.created_at DESC,e.id DESC LIMIT 1;
 IF latest.event_type='completion_undone' THEN
  FOR f IN SELECT * FROM wolfy_v2_facts WHERE user_id=NEW.user_id AND session_id=s.id
   AND kind IN ('door','conversation') AND source_key=key AND active LOOP
   PERFORM wolfy_v2_fact(NEW.user_id,s.workspace_id,s.campaign_id,s.id,f.day_id,f.kind,f.source_key,false,latest.created_at);
   PERFORM wolfy_v2_reconcile_milestones(NEW.user_id,f.day_id,s.id,s.workspace_id,s.campaign_id,latest.created_at);
  END LOOP;
  RETURN NEW;
 END IF;
 SELECT * INTO undone FROM session_events e WHERE e.session_id=s.id AND e.user_id=NEW.user_id
  AND (wolfy_v2_session_actor_at(s.id,e.user_id,e.created_at) OR e.event_type='completion_undone')
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property AND e.event_type='completion_undone'
  ORDER BY e.created_at DESC,e.id DESC LIMIT 1;
 SELECT * INTO first_completion FROM session_events e WHERE e.session_id=s.id AND e.user_id=NEW.user_id
  AND (wolfy_v2_session_actor_at(s.id,e.user_id,e.created_at) OR e.event_type='completion_undone')
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property
  AND e.event_type IN ('flyer_left','conversation','completed_manual','completed_auto')
  AND (undone.id IS NULL OR (e.created_at,e.id)>(undone.created_at,undone.id))
  ORDER BY e.created_at,e.id LIMIT 1;
 IF first_completion.id IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO f FROM wolfy_v2_facts WHERE user_id=NEW.user_id AND kind='door' AND source_key=key;
 d=coalesce(f.day_id,wolfy_v2_day(NEW.user_id,first_completion.created_at));
 PERFORM wolfy_v2_fact(NEW.user_id,s.workspace_id,s.campaign_id,s.id,d,'door',key,true,latest.created_at);
 SELECT EXISTS(SELECT 1 FROM session_events e WHERE e.session_id=s.id AND e.user_id=NEW.user_id
  AND (wolfy_v2_session_actor_at(s.id,e.user_id,e.created_at) OR e.event_type='completion_undone')
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property AND e.event_type='conversation'
  AND coalesce(e.metadata->>'address_status','') IN ('talked','appointment','hot_lead','future_seller')
  AND (undone.id IS NULL OR (e.created_at,e.id)>(undone.created_at,undone.id))) INTO conversation_exists;
 PERFORM wolfy_v2_fact(NEW.user_id,s.workspace_id,s.campaign_id,s.id,d,'conversation',key,conversation_exists,latest.created_at);
 PERFORM wolfy_v2_reconcile_milestones(NEW.user_id,d,s.id,s.workspace_id,s.campaign_id,latest.created_at);
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.wolfy_v2_snapshot() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u uuid:=auth.uid();result jsonb;d wolfy_v2_days;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 INSERT INTO wolfy_v2_profiles(user_id) VALUES(u) ON CONFLICT DO NOTHING;
 SELECT * INTO d FROM wolfy_v2_days WHERE user_id=u AND now()>=starts_at AND now()<ends_at;
 SELECT jsonb_build_object('version',2,'profile',to_jsonb(p),
 'xp',greatest(0,p.imported_xp+coalesce((SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u),0)),
 'stage',wolfy_v2_stage(u),'config',(SELECT to_jsonb(c)-'id' FROM wolfy_v2_config c),
 'today',jsonb_build_object('door_goal',coalesce(d.door_goal,(SELECT daily_door_goal FROM user_profiles WHERE user_id=u),60),
 'doors',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='door' AND active),
 'conversations',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='conversation' AND active),
 'leads',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='lead' AND active),
 'appointments',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='appointment' AND active),
 'follow_ups',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='follow_up' AND active),
 'verified_sales',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='verified_sale' AND active)),
 'current_session_streak',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND kind='door' AND active
  AND session_id=(SELECT s.id FROM sessions s WHERE s.end_time IS NULL
   AND (s.user_id=u OR EXISTS(SELECT 1 FROM session_participants sp WHERE sp.session_id=s.id
    AND sp.campaign_id=s.campaign_id AND sp.user_id=u AND sp.left_at IS NULL AND sp.joined_at<=now()))
   ORDER BY (EXISTS(SELECT 1 FROM campaign_presence cp WHERE cp.user_id=u
    AND cp.session_id=s.id AND cp.status='active')) DESC,s.start_time DESC,s.id LIMIT 1)),
 'recent_rewards',coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM (SELECT id,event_type,xp,created_at FROM wolfy_v2_ledger WHERE user_id=u ORDER BY created_at DESC,id LIMIT 20) r),'[]'::jsonb))
 INTO result FROM wolfy_v2_profiles p WHERE user_id=u;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.wolfy_pack_activity(p_campaign uuid)
 RETURNS TABLE(actor uuid,kind text,source text,occurred_at timestamptz,session_id uuid)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 WITH events AS (
  SELECT e.*,coalesce(nullif(e.building_id,''),e.address_id::text) property,
   (e.created_at AT TIME ZONE coalesce(g.timezone,'UTC'))::date AS reporting_day
  FROM session_events e JOIN sessions s ON s.id=e.session_id LEFT JOIN wolfy_pack_goals g ON g.campaign_id=s.campaign_id
  WHERE s.campaign_id=p_campaign AND e.event_type IN ('completed_manual','completed_auto','flyer_left','conversation','completion_undone')
   AND (wolfy_v2_session_actor_at(s.id,e.user_id,e.created_at)
    OR (e.event_type='completion_undone' AND EXISTS(SELECT 1 FROM session_events prior
     WHERE prior.session_id=s.id AND prior.user_id=e.user_id
      AND coalesce(nullif(prior.building_id,''),prior.address_id::text)=coalesce(nullif(e.building_id,''),e.address_id::text)
      AND prior.event_type IN ('completed_manual','completed_auto','flyer_left','conversation')
      AND (prior.created_at,prior.id)<(e.created_at,e.id)
      AND wolfy_v2_session_actor_at(s.id,prior.user_id,prior.created_at))))
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
COMMIT;
