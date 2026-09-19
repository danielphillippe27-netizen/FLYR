BEGIN;
UPDATE wolfy_v2_config SET pack_enabled=true;
UPDATE wolfy_v2_profiles SET sharing_enabled=true,sharing_configured=true;
UPDATE sessions SET end_time=NULL,is_paused=false;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
DELETE FROM campaign_presence;
SELECT wolfy_pack_publish('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',43,-79,now()-interval '70 seconds',5,0,0,1,'idle');
UPDATE campaign_presence SET updated_at=now()-interval '31 seconds';
DO $$
DECLARE old_fix timestamptz;old_sequence bigint;
BEGIN
 SELECT location_fixed_at,sequence INTO old_fix,old_sequence FROM campaign_presence;
 IF NOT wolfy_pack_heartbeat('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','idle') THEN RAISE EXCEPTION 'Stationary heartbeat rejected'; END IF;
 IF (SELECT location_fixed_at FROM campaign_presence) IS DISTINCT FROM old_fix OR (SELECT sequence FROM campaign_presence)<>old_sequence THEN RAISE EXCEPTION 'Heartbeat made stale GPS fresh'; END IF;
 IF wolfy_pack_heartbeat('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','idle') THEN RAISE EXCEPTION 'Heartbeat throttle failed'; END IF;
 UPDATE sessions SET is_paused=true WHERE id='30000000-0000-0000-0000-000000000001';
 IF EXISTS(SELECT 1 FROM campaign_presence WHERE lat IS NOT NULL OR location_fixed_at IS NOT NULL) THEN RAISE EXCEPTION 'Pause retained precise coordinates'; END IF;
 BEGIN
  PERFORM wolfy_pack_heartbeat('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','idle');
  RAISE EXCEPTION 'Paused session could heartbeat';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RAISE NOTICE 'Stationary heartbeat, actual fix timestamp, throttling and immediate pause cleanup passed';
END $$;
ROLLBACK;
