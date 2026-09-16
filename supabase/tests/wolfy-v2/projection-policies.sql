\set ON_ERROR_STOP on
BEGIN;
UPDATE wolfy_v2_config SET pack_enabled=true;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
SELECT wolfy_v2_preferences(true,'subtle','hapticsOnly',true,false,'America/Toronto');
SELECT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now(),5,0,1,1,'moving');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DO $$ DECLARE s jsonb; m jsonb; BEGIN
 s=wolfy_pack_snapshot('20000000-0000-0000-0000-000000000001',now()-interval '1 minute');
 ASSERT jsonb_array_length(s->'members')=2;
 SELECT value INTO m FROM jsonb_array_elements(s->'members') WHERE value->>'first_name'='Daniel';
 ASSERT m->'fix'->>'latitude'='43';
 ASSERT NOT (m ? 'xp') AND NOT(m ? 'imported_xp') AND NOT(m ? 'email') AND NOT(m ? 'full_name');
END $$;
RESET ROLE;
INSERT INTO wolfy_pack_policy(workspace_id,teammates_visible,managers_visible) VALUES('10000000-0000-0000-0000-000000000001',false,true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE s jsonb;m jsonb; BEGIN
 s=wolfy_pack_snapshot('20000000-0000-0000-0000-000000000001');
 SELECT value INTO m FROM jsonb_array_elements(s->'members') WHERE value->>'first_name'='Daniel';
 ASSERT m->'fix'='null'::jsonb,'teammate policy bypass';
 ASSERT (SELECT count(*)=0 FROM campaign_presence),'raw REST policy bypass';
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
DO $$ BEGIN
 BEGIN PERFORM wolfy_pack_snapshot('20000000-0000-0000-0000-000000000001');
 RAISE EXCEPTION USING ERRCODE='XX000',MESSAGE='foreign campaign snapshot leaked';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DELETE FROM workspace_members WHERE user_id='00000000-0000-0000-0000-000000000002';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
DO $$ BEGIN
 BEGIN PERFORM wolfy_pack_snapshot('20000000-0000-0000-0000-000000000001');
 RAISE EXCEPTION USING ERRCODE='XX000',MESSAGE='revoked campaign snapshot leaked';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo 'PASS: Pack field allowlist, hidden-location roster, teammate policy, foreign workspace and membership revocation'
