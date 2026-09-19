BEGIN;
UPDATE wolfy_v2_config SET pack_enabled=true,personal_enabled=false;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000001';v uuid:='00000000-0000-0000-0000-000000000002';
 c uuid:='20000000-0000-0000-0000-000000000001';s uuid:='30000000-0000-0000-0000-000000000001';w uuid:='10000000-0000-0000-0000-000000000001';result jsonb;lead uuid;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM wolfy_pack_set_goals(c,100,NULL,5,NULL,'America/Toronto');
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'unique-door','completed_manual');
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES('30000000-0000-0000-0000-000000000002',v,'unique-door','completed_manual');
 INSERT INTO session_events(session_id,user_id,building_id,event_type,metadata) VALUES(s,u,'unique-door','conversation','{"address_status":"talked"}');
 INSERT INTO contacts(user_id,workspace_id,campaign_id,lead_kind) VALUES(u,w,c,'field') RETURNING id INTO lead;
 INSERT INTO contact_activities(contact_id,type) VALUES(lead,'meeting');
 INSERT INTO field_sales(rep_id,workspace_id,campaign_id,status,verified_by,verified_at) VALUES(u,w,c,'verified',u,now());
 result=wolfy_pack_stats(c,'today');
 IF result->'totals'->>'doors'<>'1' OR result->'totals'->>'conversations'<>'1' OR result->'totals'->>'appointments'<>'1' THEN RAISE EXCEPTION 'Unique campaign totals incorrect: %',result; END IF;
 IF EXISTS(SELECT 1 FROM wolfy_v2_ledger) THEN RAISE EXCEPTION 'Pack statistics required personal XP'; END IF;
 IF result->'goals' ? 'conversations' OR result->'goals' ? 'verified_sales' THEN RAISE EXCEPTION 'Unset goals should remain absent'; END IF;
 IF result::text ~ '(unique-door|imported_xp|lifetime|@|contact_id|phone|notes)' THEN RAISE EXCEPTION 'Private data in stats'; END IF;
 PERFORM set_config('request.jwt.claim.sub',v::text,true);
 result=wolfy_pack_stats(c,'today');
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'members') m WHERE m->>'user_id'=u::text AND m->>'revenue_minor' IS NOT NULL) THEN RAISE EXCEPTION 'Revenue leaked to teammate'; END IF;
 BEGIN
  PERFORM wolfy_pack_set_goals(c,1,1,1,1,'UTC');
  RAISE EXCEPTION 'Teammate changed manager goals';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 BEGIN
  PERFORM wolfy_pack_set_goals(c,1,1,1,1,'UTC');
  RAISE EXCEPTION 'Changed reporting day after activity';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'Campaign reporting timezone is fixed after activity begins' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
 BEGIN
  PERFORM wolfy_pack_stats(c,'campaign');
  RAISE EXCEPTION 'Foreign workspace accessed stats';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at)
 VALUES(s,u,'previous-day-door','completed_manual',(date_trunc('day',now() AT TIME ZONE 'America/Toronto') AT TIME ZONE 'America/Toronto')-interval '1 second');
 IF wolfy_pack_stats(c,'today')->'totals'->>'doors'<>'1' OR wolfy_pack_stats(c,'campaign')->'totals'->>'doors'<>'2' THEN RAISE EXCEPTION 'Reporting timezone date boundary wrong'; END IF;
 IF has_function_privilege('authenticated','wolfy_pack_activity(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Raw activity keys exposed'; END IF;
 RAISE NOTICE 'Pack totals independent of XP, unique campaign doors, goal permissions, frozen timezone and revenue privacy passed';
END $$;
ROLLBACK;
