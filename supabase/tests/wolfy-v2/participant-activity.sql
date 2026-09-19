BEGIN;
UPDATE wolfy_v2_config SET personal_enabled=true,pack_enabled=true;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000002';
 s uuid:='30000000-0000-0000-0000-000000000001';c uuid:='20000000-0000-0000-0000-000000000001';
BEGIN
 INSERT INTO session_participants(session_id,campaign_id,user_id,joined_at,left_at)
 VALUES(s,c,u,now()-interval '10 minutes',now()-interval '1 minute');
 -- Uploaded after leaving; the actual event occurred during participation.
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at)
 VALUES(s,u,'joined-door','completed_manual',now()-interval '5 minutes');
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at,metadata)
 VALUES(s,u,'joined-door','conversation',now()-interval '4 minutes','{"address_status":"talked"}');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>7 THEN RAISE EXCEPTION 'Participant did not earn their own door/conversation XP'; END IF;
 IF EXISTS(SELECT 1 FROM wolfy_v2_ledger WHERE user_id<>u) THEN RAISE EXCEPTION 'Participant activity awarded host XP'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at)
 VALUES(s,u,'before-join','completed_manual',now()-interval '11 minutes'),(s,u,'after-leave','completed_manual',now());
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>7 THEN RAISE EXCEPTION 'Activity outside participation earned XP'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at)
 VALUES(s,u,'joined-door','completed_manual',now()-interval '3 minutes');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>7 THEN RAISE EXCEPTION 'Duplicate participant door earned XP'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'joined-door','completion_undone');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>0 THEN RAISE EXCEPTION 'Post-departure correction failed to compensate'; END IF;
 UPDATE sessions SET end_time=now() WHERE user_id=u;
 s='30000000-0000-0000-0000-000000000099';
 INSERT INTO sessions(id,user_id,campaign_id,workspace_id,start_time,is_paused)
 VALUES(s,'00000000-0000-0000-0000-000000000001',c,'10000000-0000-0000-0000-000000000001',now(),false);
 INSERT INTO session_participants(session_id,campaign_id,user_id,joined_at) VALUES(s,c,u,now());
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'new-joined-door','completed_manual');
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 IF wolfy_v2_snapshot()->>'current_session_streak'<>'1' THEN RAISE EXCEPTION 'Private status omitted joined session streak'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(wolfy_pack_stats(c,'today')->'members') m
  WHERE m->>'user_id'=u::text AND m->>'current_session_streak'='1') THEN RAISE EXCEPTION 'Pack stats omitted joined session streak'; END IF;
 IF has_function_privilege('authenticated','wolfy_v2_session_actor_at(uuid,uuid,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'Private history helper exposed'; END IF;
 RAISE NOTICE 'Participant XP ownership, historical offline eligibility, duplicate prevention and departure corrections passed';
END $$;
ROLLBACK;
