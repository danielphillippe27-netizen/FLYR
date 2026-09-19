-- Permission-filtered nonspatial roster and short-lived event projection.
BEGIN;
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
  JOIN LATERAL (SELECT * FROM sessions x WHERE x.user_id=r.user_id AND x.campaign_id=p_campaign AND x.end_time IS NULL
    ORDER BY x.start_time DESC,x.id LIMIT 1) s ON true
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
REVOKE ALL ON FUNCTION public.wolfy_pack_snapshot(uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_pack_snapshot(uuid,timestamptz) TO authenticated;
COMMIT;
