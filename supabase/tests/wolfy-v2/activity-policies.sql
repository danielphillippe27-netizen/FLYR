BEGIN;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000001';w uuid:='10000000-0000-0000-0000-000000000001';s uuid:='30000000-0000-0000-0000-000000000001';c uuid;meeting uuid;sale uuid;total bigint;d uuid;
BEGIN
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'disabled','completed_manual');
 IF EXISTS(SELECT 1 FROM wolfy_v2_facts) THEN RAISE EXCEPTION 'Disabled flag awarded XP'; END IF;
 UPDATE wolfy_v2_config SET personal_enabled=true;
 INSERT INTO user_profiles VALUES(u,10);
 FOR i IN 1..10 LOOP
  INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'door_'||i,'completed_manual');
 END LOOP;
 SELECT sum(xp) INTO total FROM wolfy_v2_ledger WHERE user_id=u;
 IF total<>190 THEN RAISE EXCEPTION 'Door milestone/goal expected 190 got %',total; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'door_10','completed_manual');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>190 THEN RAISE EXCEPTION 'Duplicate door rewarded'; END IF;
 UPDATE user_profiles SET daily_door_goal=60;
 UPDATE wolfy_v2_profiles SET timezone='Pacific/Auckland' WHERE user_id=u;
 SELECT id INTO d FROM wolfy_v2_days WHERE user_id=u;
 IF wolfy_v2_day(u,now())<>d OR (SELECT door_goal FROM wolfy_v2_days WHERE id=d)<>10 THEN RAISE EXCEPTION 'Day was not frozen'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'door_10','completion_undone');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>18 THEN RAISE EXCEPTION 'Undo did not compensate bonuses'; END IF;
 UPDATE wolfy_v2_config SET rewards=jsonb_set(rewards,'{door}','99'),version=version+1;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'door_10','completed_manual');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>190 THEN RAISE EXCEPTION 'Redo changed frozen reward'; END IF;
 INSERT INTO contacts(user_id,workspace_id,lead_kind) VALUES(u,w,'field') RETURNING id INTO c;
 INSERT INTO contact_activities(contact_id,type) VALUES(c,'meeting') RETURNING id INTO meeting;
 UPDATE contact_activities SET status='cancelled' WHERE id=meeting;
 UPDATE contact_activities SET status='scheduled' WHERE id=meeting;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>290 THEN RAISE EXCEPTION 'Lead/appointment expected 290'; END IF;
 DELETE FROM contacts WHERE id=c;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>190 THEN RAISE EXCEPTION 'Cascade did not reverse appointment and lead'; END IF;
 INSERT INTO field_sales(rep_id,workspace_id,status,verified_by,verified_at) VALUES(u,w,'verified',u,now()) RETURNING id INTO sale;
 UPDATE field_sales SET status='pending',verified_at=NULL WHERE id=sale;
 UPDATE field_sales SET status='verified',verified_at=now() WHERE id=sale;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>390 THEN RAISE EXCEPTION 'Sale reconciliation incorrect'; END IF;
 UPDATE field_sales SET rep_id='00000000-0000-0000-0000-000000000002' WHERE id=sale;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>190 THEN RAISE EXCEPTION 'Reassignment left XP with former rep'; END IF;
 UPDATE field_sales SET rep_id=u WHERE id=sale;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>390 OR (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id='00000000-0000-0000-0000-000000000002')<>0 THEN RAISE EXCEPTION 'Repeated reassignment duplicated XP'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 IF (wolfy_v2_snapshot()->>'xp')::bigint<>3890 THEN RAISE EXCEPTION 'Private snapshot XP lost import or ledger'; END IF;
 INSERT INTO calendar_events(user_id,workspace_id,event_type) VALUES(u,w,'follow_up') RETURNING id INTO meeting;
 PERFORM wolfy_v2_complete_followup(meeting,true);
 PERFORM wolfy_v2_complete_followup(meeting,true);
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>400 THEN RAISE EXCEPTION 'Follow-up retry duplicated XP'; END IF;
 PERFORM wolfy_v2_complete_followup(meeting,false);
 PERFORM wolfy_v2_complete_followup(meeting,true);
 UPDATE wolfy_v2_config SET personal_enabled=false;
 UPDATE calendar_events SET deleted_at=now() WHERE id=meeting;
 UPDATE wolfy_v2_config SET personal_enabled=true;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>390 THEN RAISE EXCEPTION 'Follow-up deletion did not compensate'; END IF;
 BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  PERFORM wolfy_v2_complete_followup(meeting,true);
  RAISE EXCEPTION 'Foreign completion allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  UPDATE wolfy_v2_ledger SET xp=1;
  RAISE EXCEPTION 'Mutable ledger';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'Wolfy activity ledger is append only' THEN RAISE; END IF;
 END;
 IF has_function_privilege('authenticated','wolfy_v2_fact(uuid,uuid,uuid,uuid,uuid,text,text,boolean,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'Client can award XP'; END IF;
 RAISE NOTICE 'Activity rewards: duplicates, corrections, frozen rules/day, cascading deletion, sale reversal, permissions passed';
END $$;
ROLLBACK;
BEGIN;
UPDATE wolfy_v2_config SET personal_enabled=true;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000001';s uuid:='30000000-0000-0000-0000-000000000001';
BEGIN
 FOR i IN 1..60 LOOP
  INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'property_'||i,'completed_manual');
 END LOOP;
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>440 THEN RAISE EXCEPTION '60 doors and all milestones should be 440 XP'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type,metadata) VALUES(s,u,'property_1','conversation','{"address_status":"talked"}');
 INSERT INTO session_events(session_id,user_id,building_id,event_type,metadata) VALUES(s,u,'property_1','conversation','{"address_status":"talked"}');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>445 THEN RAISE EXCEPTION 'Conversation duplicated'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,u,'property_%','completion_undone');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>445 THEN RAISE EXCEPTION 'Wildcard property undid unrelated doors'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type) VALUES(s,'00000000-0000-0000-0000-000000000002','foreign_actor','completed_manual');
 IF EXISTS(SELECT 1 FROM wolfy_v2_facts WHERE source_key LIKE 'foreign_actor:%') THEN RAISE EXCEPTION 'Foreign actor awarded'; END IF;
 RAISE NOTICE '60-door milestones, conversations, literal property matching and session ownership passed';
END $$;
ROLLBACK;
BEGIN;
UPDATE wolfy_v2_config SET personal_enabled=true;
DO $$
DECLARE u uuid:='00000000-0000-0000-0000-000000000001';s uuid:='30000000-0000-0000-0000-000000000001';t timestamptz:=now()-interval '1 hour';
BEGIN
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at) VALUES(s,u,'reordered','completion_undone',t+interval '2 minutes');
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at) VALUES(s,u,'reordered','completed_manual',t);
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at,metadata) VALUES(s,u,'reordered','conversation',t+interval '1 minute','{"address_status":"talked"}');
 IF EXISTS(SELECT 1 FROM wolfy_v2_facts WHERE active) THEN RAISE EXCEPTION 'Late upload resurrected undone property'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at) VALUES(s,u,'reordered','completed_manual',t+interval '3 minutes');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>2 THEN RAISE EXCEPTION 'Recompletion resurrected old conversation'; END IF;
 INSERT INTO session_events(session_id,user_id,building_id,event_type,created_at) VALUES(s,u,'reordered','completion_undone',t+interval '90 seconds');
 IF (SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u)<>2 THEN RAISE EXCEPTION 'Old undo removed newer completion'; END IF;
 RAISE NOTICE 'Reordered offline completion/conversation/undo reconciliation passed';
END $$;
ROLLBACK;
