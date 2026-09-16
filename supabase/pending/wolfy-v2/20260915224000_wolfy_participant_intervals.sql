-- Preserve completed participation windows across a leave/rejoin or row deletion.
BEGIN;
CREATE TABLE public.wolfy_v2_participant_intervals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),session_id uuid NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
 campaign_id uuid NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,user_id uuid NOT NULL REFERENCES auth.users(id),
 joined_at timestamptz NOT NULL,left_at timestamptz,
 CHECK(left_at IS NULL OR left_at>=joined_at)
);
CREATE UNIQUE INDEX wolfy_v2_participant_open ON wolfy_v2_participant_intervals(session_id,user_id) WHERE left_at IS NULL;
CREATE INDEX wolfy_v2_participant_history ON wolfy_v2_participant_intervals(session_id,user_id,joined_at,left_at);
ALTER TABLE wolfy_v2_participant_intervals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON wolfy_v2_participant_intervals FROM PUBLIC,anon,authenticated;
INSERT INTO wolfy_v2_participant_intervals(session_id,campaign_id,user_id,joined_at,left_at)
 SELECT sp.session_id,sp.campaign_id,sp.user_id,sp.joined_at,greatest(sp.joined_at,sp.left_at)
 FROM session_participants sp JOIN sessions s ON s.id=sp.session_id AND s.campaign_id=sp.campaign_id
 WHERE sp.left_at IS NOT NULL;
INSERT INTO wolfy_v2_participant_intervals(session_id,campaign_id,user_id,joined_at)
 SELECT sp.session_id,sp.campaign_id,sp.user_id,sp.joined_at
 FROM session_participants sp JOIN sessions s ON s.id=sp.session_id AND s.campaign_id=sp.campaign_id
 WHERE sp.left_at IS NULL;
CREATE FUNCTION public.wolfy_v2_capture_participation() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE boundary timestamptz:=clock_timestamp(); changed boolean;
BEGIN
 IF TG_OP='UPDATE' THEN
  changed=NEW.session_id IS DISTINCT FROM OLD.session_id OR NEW.campaign_id IS DISTINCT FROM OLD.campaign_id
   OR NEW.user_id IS DISTINCT FROM OLD.user_id;
  -- Heartbeats cannot rewrite historical boundaries, nor can reopening widen a past interval.
  IF NOT changed AND NEW.left_at IS NOT DISTINCT FROM OLD.left_at THEN RETURN NEW; END IF;
  UPDATE wolfy_v2_participant_intervals SET left_at=greatest(joined_at,least(coalesce(NEW.left_at,boundary),boundary))
   WHERE session_id=OLD.session_id AND user_id=OLD.user_id AND left_at IS NULL;
 ELSIF TG_OP='DELETE' THEN
  UPDATE wolfy_v2_participant_intervals SET left_at=greatest(joined_at,boundary)
   WHERE session_id=OLD.session_id AND user_id=OLD.user_id AND left_at IS NULL;
  RETURN OLD;
 END IF;
 IF NEW.left_at IS NULL AND EXISTS(SELECT 1 FROM sessions WHERE id=NEW.session_id AND campaign_id=NEW.campaign_id) THEN
  INSERT INTO wolfy_v2_participant_intervals(session_id,campaign_id,user_id,joined_at)
   VALUES(NEW.session_id,NEW.campaign_id,NEW.user_id,
    CASE WHEN TG_OP='UPDATE' OR EXISTS(SELECT 1 FROM wolfy_v2_participant_intervals
      WHERE session_id=NEW.session_id AND user_id=NEW.user_id) THEN boundary ELSE NEW.joined_at END);
 ELSIF TG_OP='INSERT' AND NEW.left_at IS NOT NULL
  AND EXISTS(SELECT 1 FROM sessions WHERE id=NEW.session_id AND campaign_id=NEW.campaign_id) THEN
  INSERT INTO wolfy_v2_participant_intervals(session_id,campaign_id,user_id,joined_at,left_at)
   VALUES(NEW.session_id,NEW.campaign_id,NEW.user_id,NEW.joined_at,greatest(NEW.joined_at,NEW.left_at));
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_v2_capture_participation AFTER INSERT OR UPDATE OR DELETE ON session_participants
 FOR EACH ROW EXECUTE FUNCTION wolfy_v2_capture_participation();
REVOKE ALL ON FUNCTION public.wolfy_v2_capture_participation() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.wolfy_v2_session_actor_at(p_session uuid,p_actor uuid,p_at timestamptz) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM sessions s WHERE s.id=p_session
  AND (s.user_id=p_actor OR EXISTS(SELECT 1 FROM wolfy_v2_participant_intervals sp
   WHERE sp.session_id=s.id AND sp.campaign_id=s.campaign_id AND sp.user_id=p_actor
   AND sp.joined_at<=p_at AND (sp.left_at IS NULL OR p_at<sp.left_at))))
$$;
COMMIT;
