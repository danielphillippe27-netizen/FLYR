-- Wolfy v2 foundation. Flags remain OFF until the full release gates pass.
-- No customer data is included in the Pack projection. Run after existing Wolfy migrations.
BEGIN;
CREATE TABLE public.wolfy_v2_config (
 id boolean PRIMARY KEY DEFAULT true CHECK(id), version integer NOT NULL DEFAULT 2,
 personal_enabled boolean NOT NULL DEFAULT false, pack_enabled boolean NOT NULL DEFAULT false,
 thresholds bigint[] NOT NULL DEFAULT ARRAY[0,2500,12000,40000,100000]::bigint[],
 rewards jsonb NOT NULL DEFAULT '{"door":2,"conversation":5,"follow_up":10,"lead":25,"appointment":75,"verified_sale":200,"doors_10":20,"doors_25":50,"doors_50":100,"daily_goal":150,"personal_best":250}',
 CHECK(array_length(thresholds,1)=5 AND thresholds[1]=0 AND thresholds[2]>thresholds[1]
 AND thresholds[3]>thresholds[2] AND thresholds[4]>thresholds[3] AND thresholds[5]>thresholds[4])
);
INSERT INTO public.wolfy_v2_config(id) VALUES(true);
CREATE TABLE public.wolfy_v2_profiles (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 imported_xp bigint NOT NULL DEFAULT 0 CHECK(imported_xp>=0),
 imported_at timestamptz NOT NULL DEFAULT now(),
 timezone text NOT NULL DEFAULT 'UTC', sharing_enabled boolean NOT NULL DEFAULT false,
 sharing_configured boolean NOT NULL DEFAULT false,
 haptics text NOT NULL DEFAULT 'subtle' CHECK(haptics IN ('off','subtle','full')),
 sounds text NOT NULL DEFAULT 'hapticsOnly' CHECK(sounds IN ('off','hapticsOnly','full')),
 team_haptics boolean NOT NULL DEFAULT true, camera_emphasis boolean NOT NULL DEFAULT false
);
-- One-time import. Never sum workspace totals during subsequent reads or refreshes.
INSERT INTO public.wolfy_v2_profiles(user_id,imported_xp)
 SELECT user_id,sum(xp) FROM public.wolfy_profiles GROUP BY user_id ON CONFLICT DO NOTHING;
CREATE TABLE public.wolfy_v2_ledger (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES auth.users(id),
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id), campaign_id uuid REFERENCES public.campaigns(id),
 session_id uuid REFERENCES public.sessions(id), event_type text NOT NULL, source_key text NOT NULL,
 xp bigint NOT NULL, rule_version integer NOT NULL, occurred_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), reversal_of uuid UNIQUE REFERENCES public.wolfy_v2_ledger(id),
 UNIQUE(user_id,event_type,source_key), CHECK(xp>=0 OR reversal_of IS NOT NULL)
);
CREATE INDEX wolfy_v2_ledger_scope ON public.wolfy_v2_ledger(campaign_id,occurred_at,user_id);
CREATE TABLE public.wolfy_pack_policy (
 workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id),
 managers_visible boolean NOT NULL DEFAULT true, teammates_visible boolean NOT NULL DEFAULT true
);
CREATE TABLE public.wolfy_pack_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
 actor_id uuid REFERENCES auth.users(id), recipient_id uuid REFERENCES auth.users(id), kind text NOT NULL,
 source_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 starts_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL DEFAULT now()+interval '30 seconds',
 animation_seed integer NOT NULL DEFAULT floor(random()*2147483647)::integer,
 UNIQUE(campaign_id,source_key), CHECK(expires_at>starts_at)
);
CREATE INDEX wolfy_pack_events_recent ON public.wolfy_pack_events(campaign_id,created_at);
ALTER TABLE public.campaign_presence
 ADD COLUMN IF NOT EXISTS location_fixed_at timestamptz,
 ADD COLUMN IF NOT EXISTS location_accuracy double precision,
 ADD COLUMN IF NOT EXISTS heading double precision,
 ADD COLUMN IF NOT EXISTS speed double precision,
 ADD COLUMN IF NOT EXISTS sequence bigint NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS activity_state text NOT NULL DEFAULT 'idle';

CREATE FUNCTION public.wolfy_pack_manager(p_campaign uuid,p_user uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM campaigns c WHERE c.id=p_campaign AND
 (c.owner_id=p_user OR EXISTS(SELECT 1 FROM workspaces w WHERE w.id=c.workspace_id AND w.owner_id=p_user)
 OR EXISTS(SELECT 1 FROM workspace_members m WHERE m.workspace_id=c.workspace_id AND m.user_id=p_user
 AND m.role IN ('owner','admin','manager'))))
$$;
CREATE FUNCTION public.wolfy_pack_location_allowed(p_campaign uuid,p_subject uuid,p_session uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT auth.uid() IS NOT NULL
 AND EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled)
 AND public.is_campaign_member(p_campaign,auth.uid())
 AND public.is_campaign_member(p_campaign,p_subject)
 AND EXISTS(SELECT 1 FROM wolfy_v2_profiles WHERE user_id=p_subject AND sharing_enabled)
 AND EXISTS(SELECT 1 FROM sessions s WHERE s.id=p_session AND s.user_id=p_subject AND s.campaign_id=p_campaign
 AND s.end_time IS NULL AND NOT coalesce(s.is_paused,false))
 AND EXISTS(SELECT 1 FROM campaigns c LEFT JOIN wolfy_pack_policy p ON p.workspace_id=c.workspace_id
 WHERE c.id=p_campaign AND (p_subject=auth.uid()
 OR CASE WHEN wolfy_pack_manager(p_campaign,auth.uid()) THEN coalesce(p.managers_visible,true)
 ELSE coalesce(p.teammates_visible,true) END))
$$;
-- Protect the old table too: hiding coordinates only in the new UI would still leak via REST/realtime.
DROP POLICY IF EXISTS campaign_presence_select_member ON public.campaign_presence;
CREATE FUNCTION public.wolfy_pack_presence_read_allowed(p_campaign uuid,p_user uuid,p_session uuid,p_fixed_at timestamptz) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled) THEN
  public.wolfy_pack_location_allowed(p_campaign,p_user,p_session)
  AND p_fixed_at>now()-interval '180 seconds' AND p_fixed_at<=now()+interval '5 seconds'
 ELSE
  auth.uid() IS NOT NULL AND public.is_campaign_member(p_campaign,auth.uid())
  AND coalesce((SELECT NOT sharing_configured OR sharing_enabled FROM wolfy_v2_profiles WHERE user_id=p_user),true)
 END
$$;
CREATE POLICY campaign_presence_select_member ON public.campaign_presence FOR SELECT TO authenticated
 USING(public.wolfy_pack_presence_read_allowed(campaign_id,user_id,session_id,location_fixed_at));

CREATE FUNCTION public.wolfy_v2_stage(p_user uuid) RETURNS integer
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT greatest(1,(SELECT count(*)::integer FROM wolfy_v2_config c,
 unnest(c.thresholds) t WHERE t<=greatest(0,coalesce((SELECT imported_xp FROM wolfy_v2_profiles WHERE user_id=p_user),0)
 +coalesce((SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=p_user),0))))
$$;
CREATE FUNCTION public.wolfy_v2_snapshot() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u uuid:=auth.uid(); result jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 INSERT INTO wolfy_v2_profiles(user_id) VALUES(u) ON CONFLICT DO NOTHING;
 SELECT jsonb_build_object('version',2,'profile',to_jsonb(p),
 'xp',greatest(0,p.imported_xp+coalesce((SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u),0)),
 'stage',wolfy_v2_stage(u),'config',(SELECT to_jsonb(c)-'id' FROM wolfy_v2_config c)) INTO result
 FROM wolfy_v2_profiles p WHERE user_id=u;
 RETURN result;
END $$;
CREATE FUNCTION public.wolfy_v2_preferences(p_sharing boolean,p_haptics text,p_sounds text,p_team_haptics boolean,p_camera boolean,p_timezone text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'Invalid timezone'; END IF;
 INSERT INTO wolfy_v2_profiles(user_id,sharing_enabled,sharing_configured,haptics,sounds,team_haptics,camera_emphasis,timezone)
 VALUES(auth.uid(),p_sharing,true,p_haptics,p_sounds,p_team_haptics,p_camera,p_timezone)
 ON CONFLICT(user_id) DO UPDATE SET sharing_enabled=excluded.sharing_enabled,sharing_configured=true,haptics=excluded.haptics,
 sounds=excluded.sounds,team_haptics=excluded.team_haptics,camera_emphasis=excluded.camera_emphasis,timezone=excluded.timezone;
 IF NOT p_sharing THEN
 UPDATE campaign_presence SET lat=NULL,lng=NULL,location_fixed_at=NULL,location_accuracy=NULL,heading=NULL,speed=NULL,status='inactive'
 WHERE user_id=auth.uid();
 END IF;
 RETURN wolfy_v2_snapshot();
END $$;
CREATE FUNCTION public.wolfy_pack_publish(p_campaign uuid,p_session uuid,p_lat double precision,p_lng double precision,
 p_fixed_at timestamptz,p_accuracy double precision,p_heading double precision,p_speed double precision,p_sequence bigint,p_activity text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE previous campaign_presence; elapsed double precision; distance double precision; u uuid:=auth.uid();
BEGIN
 IF NOT coalesce(wolfy_pack_location_allowed(p_campaign,u,p_session),false) THEN RAISE EXCEPTION 'Location sharing unavailable' USING ERRCODE='42501'; END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL OR p_speed IS NULL OR p_fixed_at IS NULL OR p_sequence IS NULL
 OR NOT(p_lat BETWEEN -90 AND 90) OR NOT(p_lng BETWEEN -180 AND 180)
 OR NOT(p_accuracy BETWEEN 0 AND 50) OR NOT(p_speed BETWEEN 0 AND 12)
 OR (p_heading IS NOT NULL AND NOT(p_heading>=0 AND p_heading<360))
 OR p_fixed_at>now()+interval '5 seconds' OR p_fixed_at<=now()-interval '180 seconds'
 OR p_sequence<0 OR p_activity NOT IN ('moving','idle','atDoor','conversation') THEN RETURN false; END IF;
 -- Serialize first inserts as well as updates; sequence belongs to an existing session.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_campaign::text||u::text,0));
 SELECT * INTO previous FROM campaign_presence WHERE campaign_id=p_campaign AND user_id=u FOR UPDATE;
 IF FOUND AND previous.session_id=p_session AND previous.location_fixed_at IS NOT NULL THEN
  IF p_sequence<=previous.sequence OR p_fixed_at<=previous.location_fixed_at THEN RETURN false; END IF;
  IF previous.updated_at>now()-interval '5 seconds' THEN RETURN false; END IF;
  elapsed=extract(epoch FROM p_fixed_at-previous.location_fixed_at);
  distance=6371000*2*asin(sqrt(least(1,power(sin(radians(p_lat-previous.lat)/2),2)
   +cos(radians(p_lat))*cos(radians(previous.lat))*power(sin(radians(p_lng-previous.lng)/2),2))));
  IF distance>12*elapsed+least(50,coalesce(previous.location_accuracy,0)+p_accuracy) THEN RETURN false; END IF;
 END IF;
 INSERT INTO campaign_presence(campaign_id,user_id,session_id,lat,lng,updated_at,status,location_fixed_at,location_accuracy,heading,speed,sequence,activity_state)
 VALUES(p_campaign,u,p_session,p_lat,p_lng,now(),'active',p_fixed_at,p_accuracy,p_heading,p_speed,p_sequence,p_activity)
 ON CONFLICT(campaign_id,user_id) DO UPDATE SET session_id=excluded.session_id,lat=excluded.lat,lng=excluded.lng,
 updated_at=excluded.updated_at,status=excluded.status,location_fixed_at=excluded.location_fixed_at,
 location_accuracy=excluded.location_accuracy,heading=excluded.heading,speed=excluded.speed,sequence=excluded.sequence,activity_state=excluded.activity_state;
 RETURN true;
END $$;
-- Legacy clients may still write presence, but cannot refresh a v2 fix timestamp or bypass session consent.
-- v2-only columns are writable exclusively through the validated RPC.
REVOKE INSERT,UPDATE ON public.campaign_presence FROM authenticated;
GRANT INSERT(campaign_id,user_id,session_id,lat,lng,updated_at,status),
 UPDATE(campaign_id,user_id,session_id,lat,lng,updated_at,status) ON public.campaign_presence TO authenticated;
CREATE FUNCTION public.wolfy_pack_legacy_presence_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF current_user='authenticated' THEN
  NEW.location_fixed_at=NULL; NEW.location_accuracy=NULL; NEW.heading=NULL; NEW.speed=NULL;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_pack_legacy_presence_guard BEFORE INSERT OR UPDATE ON public.campaign_presence
 FOR EACH ROW EXECUTE FUNCTION public.wolfy_pack_legacy_presence_guard();

CREATE FUNCTION public.wolfy_pack_send_howl(p_campaign uuid,p_recipient uuid,p_request uuid) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u uuid:=auth.uid(); result uuid;
BEGIN
 IF u IS NULL OR p_recipient=u OR NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE pack_enabled)
 OR NOT public.is_campaign_member(p_campaign,u) OR NOT public.is_campaign_member(p_campaign,p_recipient)
 OR NOT EXISTS(SELECT 1 FROM sessions WHERE user_id=u AND campaign_id=p_campaign AND end_time IS NULL AND NOT coalesce(is_paused,false))
 OR NOT EXISTS(SELECT 1 FROM sessions WHERE user_id=p_recipient AND campaign_id=p_campaign AND end_time IS NULL AND NOT coalesce(is_paused,false))
 THEN RAISE EXCEPTION 'Active shared campaign required' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-howl:'||u::text,0));
 SELECT id INTO result FROM wolfy_pack_events WHERE campaign_id=p_campaign AND source_key='howl:'||u::text||':'||p_request::text;
 IF result IS NOT NULL THEN RETURN result; END IF;
 IF (SELECT count(*) FROM wolfy_pack_events WHERE actor_id=u AND kind='howl' AND created_at>now()-interval '1 minute')>=3
 OR EXISTS(SELECT 1 FROM wolfy_pack_events WHERE actor_id=u AND recipient_id=p_recipient AND kind='howl' AND created_at>now()-interval '5 minutes')
 THEN RAISE EXCEPTION 'Howl cooldown active' USING ERRCODE='P0001'; END IF;
 INSERT INTO wolfy_pack_events(campaign_id,actor_id,recipient_id,kind,source_key,expires_at)
 VALUES(p_campaign,u,p_recipient,'howl','howl:'||u::text||':'||p_request::text,now()+interval '60 seconds') RETURNING id INTO result;
 RETURN result;
END $$;

ALTER TABLE public.wolfy_v2_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wolfy_v2_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wolfy_v2_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wolfy_pack_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wolfy_pack_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wolfy_v2_config,public.wolfy_v2_profiles,public.wolfy_v2_ledger,public.wolfy_pack_policy,public.wolfy_pack_events FROM PUBLIC,anon,authenticated;
-- Read through RPC until the private realtime projection and revocation tests are complete.
REVOKE ALL ON FUNCTION public.wolfy_pack_manager(uuid,uuid),public.wolfy_v2_stage(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.wolfy_pack_presence_read_allowed(uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_pack_presence_read_allowed(uuid,uuid,uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.wolfy_pack_location_allowed(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_pack_location_allowed(uuid,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.wolfy_v2_snapshot(),public.wolfy_v2_preferences(boolean,text,text,boolean,boolean,text),
 public.wolfy_pack_publish(uuid,uuid,double precision,double precision,timestamptz,double precision,double precision,double precision,bigint,text),
 public.wolfy_pack_send_howl(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_v2_snapshot(),public.wolfy_v2_preferences(boolean,text,text,boolean,boolean,text),
 public.wolfy_pack_publish(uuid,uuid,double precision,double precision,timestamptz,double precision,double precision,double precision,bigint,text),
 public.wolfy_pack_send_howl(uuid,uuid,uuid) TO authenticated;
COMMIT;
