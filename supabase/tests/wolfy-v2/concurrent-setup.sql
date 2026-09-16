UPDATE wolfy_v2_config SET pack_enabled=true,personal_enabled=false;
UPDATE wolfy_pack_goals SET doors=100 WHERE campaign_id='20000000-0000-0000-0000-000000000001';
INSERT INTO session_events(session_id,user_id,building_id,event_type)
 SELECT '30000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000001'::uuid,'concurrent-'||i,'completed_manual' FROM generate_series(1,98) i;
