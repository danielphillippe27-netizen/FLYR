BEGIN;
CREATE FUNCTION public.wolfy_v2_runtime() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 RETURN (SELECT jsonb_build_object('version',2,'pack_enabled',pack_enabled,'personal_enabled',personal_enabled) FROM wolfy_v2_config);
END $$;
CREATE FUNCTION public.wolfy_pack_clear_presence(p_campaign uuid,p_session uuid) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM sessions WHERE id=p_session AND user_id=auth.uid()) THEN
  RAISE EXCEPTION 'Session access required' USING ERRCODE='42501'; END IF;
 UPDATE campaign_presence SET lat=NULL,lng=NULL,location_fixed_at=NULL,location_accuracy=NULL,heading=NULL,speed=NULL,
  status='inactive',activity_state='paused',updated_at=now()
 WHERE campaign_id=p_campaign AND user_id=auth.uid() AND session_id=p_session;
END $$;
CREATE FUNCTION public.wolfy_pack_heartbeat(p_campaign uuid,p_session uuid,p_activity text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE pr campaign_presence;
BEGIN
 IF NOT coalesce(wolfy_pack_location_allowed(p_campaign,auth.uid(),p_session),false) THEN
  RAISE EXCEPTION 'Location sharing unavailable' USING ERRCODE='42501'; END IF;
 IF p_activity IS NULL OR p_activity NOT IN ('moving','idle','atDoor','conversation') THEN RETURN false; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_campaign::text||auth.uid()::text,0));
 SELECT * INTO pr FROM campaign_presence WHERE campaign_id=p_campaign AND user_id=auth.uid() FOR UPDATE;
 IF FOUND AND pr.session_id=p_session AND pr.updated_at>now()-interval '30 seconds' AND pr.activity_state=p_activity THEN RETURN false; END IF;
 INSERT INTO campaign_presence(campaign_id,user_id,session_id,updated_at,status,activity_state)
 VALUES(p_campaign,auth.uid(),p_session,now(),'active',p_activity)
 ON CONFLICT(campaign_id,user_id) DO UPDATE SET session_id=excluded.session_id,updated_at=excluded.updated_at,
  status='active',activity_state=excluded.activity_state,
  lat=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.lat END,
  lng=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.lng END,
  location_fixed_at=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.location_fixed_at END,
  location_accuracy=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.location_accuracy END,
  heading=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.heading END,
  speed=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.speed END,
  sequence=CASE WHEN campaign_presence.session_id=excluded.session_id THEN campaign_presence.sequence ELSE 0 END;
 RETURN true;
END $$;
CREATE FUNCTION public.wolfy_pack_session_privacy() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled)
  AND (NEW.end_time IS NOT NULL OR coalesce(NEW.is_paused,false) OR NEW.campaign_id IS DISTINCT FROM OLD.campaign_id OR NEW.user_id IS DISTINCT FROM OLD.user_id) THEN
  UPDATE campaign_presence SET lat=NULL,lng=NULL,location_fixed_at=NULL,location_accuracy=NULL,heading=NULL,speed=NULL,
   status='inactive',activity_state='paused',updated_at=now() WHERE session_id=NEW.id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_pack_session_privacy AFTER UPDATE OF end_time,is_paused,campaign_id,user_id ON sessions
 FOR EACH ROW EXECUTE FUNCTION wolfy_pack_session_privacy();
REVOKE ALL ON FUNCTION wolfy_pack_session_privacy() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION wolfy_v2_runtime(),wolfy_pack_clear_presence(uuid,uuid),wolfy_pack_heartbeat(uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION wolfy_v2_runtime(),wolfy_pack_clear_presence(uuid,uuid),wolfy_pack_heartbeat(uuid,uuid,text) TO authenticated;
COMMIT;
