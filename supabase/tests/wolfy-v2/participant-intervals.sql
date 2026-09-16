BEGIN;
UPDATE wolfy_v2_config SET personal_enabled=true,pack_enabled=true;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000002';
 s uuid:='30000000-0000-0000-0000-000000000001';c uuid:='20000000-0000-0000-0000-000000000001';
BEGIN
 INSERT INTO session_participants(session_id,campaign_id,user_id,joined_at,left_at)
 VALUES(s,c,u,now()-interval '10 minutes',now()-interval '5 minutes');
 UPDATE session_participants SET left_at=NULL WHERE user_id=u;
 IF (SELECT count(*) FROM wolfy_v2_participant_intervals WHERE user_id=u)<>2 THEN RAISE EXCEPTION 'Rejoin lost prior participation window'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at)
 VALUES(s,u,'historical-valid','completed_manual',now()-interval '7 minutes'),
 (s,u,'gap-invalid','completed_manual',now()-interval '2 minutes');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>2 THEN RAISE EXCEPTION 'Rejoin widened eligibility across absence'; END IF;
 UPDATE session_participants SET joined_at=now()-interval '1 day' WHERE user_id=u;
 IF wolfy_v2_session_actor_at(s,u,now()-interval '2 minutes') THEN RAISE EXCEPTION 'Heartbeat/date edit rewrote immutable history'; END IF;
 DELETE FROM session_participants WHERE user_id=u;
 IF NOT wolfy_v2_session_actor_at(s,u,now()-interval '7 minutes') THEN RAISE EXCEPTION 'Deleting participant lost historical eligibility'; END IF;
 IF EXISTS(SELECT 1 FROM wolfy_v2_participant_intervals WHERE user_id=u AND left_at IS NULL) THEN RAISE EXCEPTION 'Delete retained an open interval'; END IF;
 IF has_table_privilege('authenticated','wolfy_v2_participant_intervals','SELECT') THEN RAISE EXCEPTION 'Private participation history exposed'; END IF;
 RAISE NOTICE 'Leave/rejoin intervals, absence rejection, immutable history and delete preservation passed';
END $$;
ROLLBACK;
