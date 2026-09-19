\set ON_ERROR_STOP on
BEGIN;
UPDATE wolfy_v2_config SET pack_enabled=true;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE first jsonb; again jsonb; BEGIN
 first=wolfy_v2_snapshot(); again=wolfy_v2_snapshot();
 ASSERT (first->>'xp')::bigint=3500 AND (again->>'xp')::bigint=3500,'XP import must happen once';
 ASSERT (first->>'stage')::int=2;
END $$;
SELECT wolfy_v2_preferences(true,'subtle','hapticsOnly',true,false,'America/Toronto');
DO $$ BEGIN
 ASSERT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,1,1,'moving');
 ASSERT NOT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,1,1,'moving'),'duplicate sequence rejected';
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DO $$ BEGIN
 ASSERT (SELECT count(*)=1 FROM campaign_presence),'teammate sees permitted fresh presence';
 BEGIN PERFORM * FROM wolfy_v2_profiles; RAISE EXCEPTION 'private profile leaked'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,1,2,'moving'); RAISE EXCEPTION 'foreign session accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM campaign_presence),'foreign workspace location leaked'; END $$;
RESET ROLE;
UPDATE campaign_presence SET updated_at=now(),location_fixed_at=now()-interval '181 seconds';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM campaign_presence),'heartbeat revived old location'; END $$;
RESET ROLE;
UPDATE campaign_presence SET location_fixed_at=now();
UPDATE sessions SET is_paused=true WHERE user_id='00000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM campaign_presence),'paused location visible'; END $$;
RESET ROLE;
UPDATE sessions SET is_paused=false;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
SELECT wolfy_v2_preferences(false,'off','off',false,false,'America/Toronto');
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM campaign_presence),'revoked sharing location visible'; END $$;
DO $$ DECLARE a uuid;b uuid; BEGIN
 a=wolfy_pack_send_howl('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001');
 b=wolfy_pack_send_howl('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001');
 ASSERT a=b,'howl retry duplicated';
 BEGIN
  PERFORM wolfy_pack_send_howl('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002');
  RAISE EXCEPTION USING ERRCODE='XX000',MESSAGE='howl cooldown bypassed';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN NULL; END;
END $$;
ROLLBACK;
\echo 'PASS: one-time XP, self-only profile, location authorization, stale fixes, paused sessions, sharing revocation, howl idempotency and cooldown'
