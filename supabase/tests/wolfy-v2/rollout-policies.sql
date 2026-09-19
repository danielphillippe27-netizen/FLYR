\set ON_ERROR_STOP on
BEGIN;
INSERT INTO campaign_presence(campaign_id,user_id,session_id,lat,lng,updated_at,status)
 VALUES('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),'active');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DO $$ BEGIN ASSERT (SELECT count(*)=1 FROM campaign_presence),'disabled Pack changed existing visibility'; END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
SELECT wolfy_v2_preferences(false,'subtle','hapticsOnly',true,false,'UTC');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM campaign_presence),'explicit opt-out ignored during rollout'; END $$;
RESET ROLE;
UPDATE wolfy_v2_config SET pack_enabled=true;
UPDATE wolfy_v2_profiles SET sharing_enabled=true;
SET LOCAL ROLE authenticated;
DO $$ BEGIN ASSERT (SELECT count(*)=0 FROM campaign_presence),'legacy heartbeat presented as a fresh v2 fix'; END $$;
ROLLBACK;
\echo 'PASS: disabled rollout preserves legacy access; explicit opt-out and fresh-fix requirements hold'
