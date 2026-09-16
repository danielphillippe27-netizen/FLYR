BEGIN;
UPDATE wolfy_v2_config SET pack_enabled=true,personal_enabled=false;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000001';c uuid:='20000000-0000-0000-0000-000000000001';s uuid:='30000000-0000-0000-0000-000000000001';d date;before_xp bigint;projection jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 SELECT coalesce(sum(xp),0) INTO before_xp FROM wolfy_v2_ledger;
 PERFORM wolfy_pack_set_goals(c,100,NULL,NULL,NULL,'America/Toronto');
 FOR i IN 1..100 LOOP
  INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'pack-door-'||i,'completed_manual');
 END LOOP;
 d=(clock_timestamp() AT TIME ZONE 'America/Toronto')::date;
 PERFORM wolfy_pack_claim_day(c,d);
 PERFORM wolfy_pack_claim_day(c,d);
 IF (SELECT count(*) FROM wolfy_pack_events WHERE campaign_id=c AND kind IN ('pack_goal','pack_milestone'))<>2 THEN RAISE EXCEPTION 'Pack claims missing or duplicated'; END IF;
 IF EXISTS(SELECT 1 FROM wolfy_pack_events WHERE kind IN ('pack_goal','pack_milestone') AND (starts_at<created_at+interval '1 second' OR expires_at<=starts_at)) THEN RAISE EXCEPTION 'Synchronized start window incorrect'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'pack-door-100','completion_undone');
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'pack-door-100','completed_manual');
 PERFORM wolfy_pack_set_goals(c,50,NULL,NULL,NULL,'America/Toronto');
 IF (SELECT count(*) FROM wolfy_pack_events WHERE campaign_id=c AND kind IN ('pack_goal','pack_milestone'))<>2 THEN RAISE EXCEPTION 'Correction or goal edits replayed claims'; END IF;
 IF (SELECT coalesce(sum(xp),0) FROM wolfy_v2_ledger)<>before_xp THEN RAISE EXCEPTION 'Pack achievements granted personal XP'; END IF;
 projection=wolfy_pack_snapshot(c,NULL);
 IF projection->'summary'->>'goals'<>'1' OR projection->'summary'->>'milestones'<>'1' OR jsonb_array_length(projection->'events')<>0 THEN RAISE EXCEPTION 'Resume should summarize without replay'; END IF;
 projection=wolfy_pack_snapshot(c,now()-interval '10 seconds');
 IF jsonb_array_length(projection->'events')<>2 OR projection->'events'->0->'details'->>'metric'<>'doors' THEN RAISE EXCEPTION 'Live events missing safe detail'; END IF;
 IF has_function_privilege('authenticated','wolfy_pack_claim_day(uuid,date)','EXECUTE') THEN RAISE EXCEPTION 'Client can claim milestone'; END IF;
 RAISE NOTICE 'Pack goal/milestone idempotence, correction replay prevention, synchronized windows, and zero bonus XP passed';
END $$;
ROLLBACK;
