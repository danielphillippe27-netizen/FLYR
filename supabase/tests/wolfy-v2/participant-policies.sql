BEGIN;
UPDATE wolfy_v2_config SET pack_enabled=true;
INSERT INTO wolfy_v2_profiles(user_id,sharing_enabled,sharing_configured)
 SELECT id,true,true FROM auth.users ON CONFLICT(user_id) DO UPDATE SET sharing_enabled=true,sharing_configured=true;
-- Gabe joins Daniel's session; he has no separate active session.
UPDATE sessions SET end_time=now() WHERE user_id='00000000-0000-0000-0000-000000000002';
INSERT INTO session_participants(session_id,campaign_id,user_id,joined_at)
 VALUES('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',now()-interval '10 minutes');
DELETE FROM campaign_presence;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
SET LOCAL ROLE authenticated;
SELECT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,0,1,'idle');
DO $$
DECLARE snapshot jsonb;
BEGIN
 snapshot=wolfy_pack_snapshot('20000000-0000-0000-0000-000000000001');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snapshot->'members') m
  WHERE m->>'user_id'=auth.uid()::text AND m->>'fix' IS NOT NULL) THEN RAISE EXCEPTION 'Joined participant missing from spatial roster'; END IF;
 PERFORM wolfy_pack_send_howl('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',gen_random_uuid());
 IF has_function_privilege('authenticated','wolfy_pack_session_member(uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Private membership helper exposed'; END IF;
END $$;
RESET ROLE;
UPDATE session_participants SET left_at=now();
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM campaign_presence WHERE lat IS NOT NULL OR location_fixed_at IS NOT NULL) THEN RAISE EXCEPTION 'Leaving retained precise location'; END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM campaign_presence) THEN RAISE EXCEPTION 'Revoked participant visible through raw table'; END IF;
 BEGIN
  PERFORM wolfy_pack_heartbeat('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','idle');
  RAISE EXCEPTION 'Departed participant could heartbeat';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM wolfy_pack_send_howl('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',gen_random_uuid());
  RAISE EXCEPTION 'Departed participant could send howl';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- Clearing your own presence remains legal after losing session membership.
 PERFORM wolfy_pack_clear_presence('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');
END $$;
RESET ROLE;
UPDATE session_participants SET left_at=NULL;
SELECT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,0,2,'idle');
UPDATE sessions SET is_paused=true WHERE id='30000000-0000-0000-0000-000000000001';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM campaign_presence WHERE lat IS NOT NULL) THEN RAISE EXCEPTION 'Host pause retained participant fix'; END IF;
END $$;
UPDATE sessions SET is_paused=false WHERE id='30000000-0000-0000-0000-000000000001';
SELECT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,0,3,'idle');
DELETE FROM session_participants;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM campaign_presence WHERE lat IS NOT NULL) THEN RAISE EXCEPTION 'Deleted participation retained fix'; END IF;
 RAISE NOTICE 'Participant publication, roster, howl, direct RLS, departure, host pause and deletion passed';
END $$;
ROLLBACK;
