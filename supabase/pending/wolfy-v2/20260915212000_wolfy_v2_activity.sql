-- Authoritative, reversible activity facts. No authenticated award endpoint.
BEGIN;
CREATE TABLE public.wolfy_v2_days (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES auth.users(id),
 starts_at timestamptz NOT NULL,ends_at timestamptz NOT NULL,local_date date NOT NULL,timezone text NOT NULL,
 door_goal integer NOT NULL CHECK(door_goal>0),UNIQUE(user_id,starts_at),CHECK(ends_at>starts_at)
);
CREATE TABLE public.wolfy_v2_facts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES auth.users(id),
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id),campaign_id uuid REFERENCES public.campaigns(id),session_id uuid REFERENCES public.sessions(id),
 day_id uuid NOT NULL REFERENCES public.wolfy_v2_days(id),kind text NOT NULL,source_key text NOT NULL,
 active boolean NOT NULL DEFAULT false,revision integer NOT NULL DEFAULT 0,
 reward_xp bigint NOT NULL CHECK(reward_xp>=0),rule_version integer NOT NULL,
 award_id uuid REFERENCES public.wolfy_v2_ledger(id),occurred_at timestamptz NOT NULL,
 UNIQUE(user_id,kind,source_key)
);
CREATE INDEX wolfy_v2_fact_day ON public.wolfy_v2_facts(user_id,day_id,kind) WHERE active;
CREATE INDEX wolfy_v2_fact_session ON public.wolfy_v2_facts(session_id,kind) WHERE active;
ALTER TABLE wolfy_v2_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE wolfy_v2_facts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON wolfy_v2_days,wolfy_v2_facts FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.wolfy_v2_ledger_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Wolfy activity ledger is append only'; END $$;
CREATE TRIGGER wolfy_v2_ledger_immutable BEFORE UPDATE OR DELETE ON wolfy_v2_ledger
 FOR EACH ROW EXECUTE FUNCTION wolfy_v2_ledger_immutable();

CREATE FUNCTION public.wolfy_v2_day(p_user uuid,p_at timestamptz) RETURNS uuid
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE d wolfy_v2_days;tz text;start_at timestamptz;end_at timestamptz;g integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-user:'||p_user::text,0));
 SELECT * INTO d FROM wolfy_v2_days WHERE user_id=p_user AND p_at>=starts_at AND p_at<ends_at;
 IF FOUND THEN RETURN d.id; END IF;
 SELECT timezone INTO tz FROM wolfy_v2_profiles WHERE user_id=p_user;
 tz=coalesce(tz,'UTC');
 start_at=date_trunc('day',p_at AT TIME ZONE tz) AT TIME ZONE tz;
 end_at=(date_trunc('day',p_at AT TIME ZONE tz)+interval '1 day') AT TIME ZONE tz;
 -- Timezone changes cannot overlap a day already opened by another device.
 SELECT greatest(start_at,coalesce(max(ends_at),start_at)) INTO start_at FROM wolfy_v2_days WHERE user_id=p_user AND ends_at<=p_at;
 SELECT least(end_at,coalesce(min(starts_at),end_at)) INTO end_at FROM wolfy_v2_days WHERE user_id=p_user AND starts_at>p_at;
 SELECT daily_door_goal INTO g FROM user_profiles WHERE user_id=p_user;
 INSERT INTO wolfy_v2_days(user_id,starts_at,ends_at,local_date,timezone,door_goal)
 VALUES(p_user,start_at,end_at,(p_at AT TIME ZONE tz)::date,tz,greatest(1,coalesce(g,60))) RETURNING * INTO d;
 RETURN d.id;
END $$;

CREATE FUNCTION public.wolfy_v2_fact(p_user uuid,p_workspace uuid,p_campaign uuid,p_session uuid,p_day uuid,
 p_kind text,p_source text,p_active boolean,p_at timestamptz) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE f wolfy_v2_facts;cfg wolfy_v2_config;amount bigint;entry uuid;
BEGIN
 IF p_user IS NULL OR p_workspace IS NULL OR p_source IS NULL OR p_active IS NULL THEN RETURN false; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-user:'||p_user::text,0));
 SELECT * INTO f FROM wolfy_v2_facts WHERE user_id=p_user AND kind=p_kind AND source_key=p_source FOR UPDATE;
 IF NOT FOUND THEN
  IF NOT p_active OR NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE personal_enabled) THEN RETURN false; END IF;
  SELECT * INTO STRICT cfg FROM wolfy_v2_config;
  IF jsonb_typeof(cfg.rewards->p_kind) IS DISTINCT FROM 'number' OR (cfg.rewards->>p_kind)!~'^[0-9]+$' THEN
   RAISE EXCEPTION 'Invalid reward configuration for %',p_kind;
  END IF;
  amount=(cfg.rewards->>p_kind)::bigint;
  INSERT INTO wolfy_v2_profiles(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
  INSERT INTO wolfy_v2_facts(user_id,workspace_id,campaign_id,session_id,day_id,kind,source_key,reward_xp,rule_version,occurred_at)
  VALUES(p_user,p_workspace,p_campaign,p_session,p_day,p_kind,p_source,amount,cfg.version,p_at) RETURNING * INTO f;
 END IF;
 IF f.active=p_active THEN RETURN false; END IF;
 INSERT INTO wolfy_v2_ledger(user_id,workspace_id,campaign_id,session_id,event_type,source_key,xp,rule_version,occurred_at,reversal_of)
 VALUES(f.user_id,f.workspace_id,f.campaign_id,f.session_id,f.kind,f.id::text||':'||(f.revision+1)::text,
 CASE WHEN p_active THEN f.reward_xp ELSE -f.reward_xp END,f.rule_version,p_at,CASE WHEN p_active THEN NULL ELSE f.award_id END)
 RETURNING id INTO entry;
 UPDATE wolfy_v2_facts SET active=p_active,revision=revision+1,award_id=CASE WHEN p_active THEN entry ELSE award_id END WHERE id=f.id;
 RETURN true;
END $$;

CREATE FUNCTION public.wolfy_v2_reconcile_milestones(p_user uuid,p_day uuid,p_session uuid,p_workspace uuid,p_campaign uuid,p_at timestamptz) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE doors integer;session_doors integer;goal integer;
BEGIN
 SELECT count(*) INTO doors FROM wolfy_v2_facts WHERE user_id=p_user AND day_id=p_day AND kind='door' AND active;
 SELECT door_goal INTO goal FROM wolfy_v2_days WHERE id=p_day AND user_id=p_user;
 PERFORM wolfy_v2_fact(p_user,p_workspace,p_campaign,NULL,p_day,'doors_50',p_day::text,doors>=50,p_at);
 PERFORM wolfy_v2_fact(p_user,p_workspace,p_campaign,NULL,p_day,'daily_goal',p_day::text,doors>=goal,p_at);
 IF p_session IS NOT NULL THEN
  SELECT count(*) INTO session_doors FROM wolfy_v2_facts WHERE user_id=p_user AND session_id=p_session AND kind='door' AND active;
  PERFORM wolfy_v2_fact(p_user,p_workspace,p_campaign,p_session,p_day,'doors_10',p_session::text,session_doors>=10,p_at);
  PERFORM wolfy_v2_fact(p_user,p_workspace,p_campaign,p_session,p_day,'doors_25',p_session::text,session_doors>=25,p_at);
 END IF;
END $$;

CREATE INDEX wolfy_v2_session_event_property ON public.session_events
 (session_id,(coalesce(nullif(building_id,''),address_id::text)),created_at,id);
CREATE FUNCTION public.wolfy_v2_session_activity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s sessions;d uuid;key text;property text;f wolfy_v2_facts;latest session_events;
 undone session_events;first_completion session_events;conversation_exists boolean;
BEGIN
 IF NEW.event_type NOT IN ('completion_undone','flyer_left','conversation','completed_manual','completed_auto') THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE personal_enabled)
  AND NOT EXISTS(SELECT 1 FROM wolfy_v2_facts WHERE session_id=NEW.session_id) THEN RETURN NEW; END IF;
 SELECT * INTO s FROM sessions WHERE id=NEW.session_id;
 IF s.user_id IS DISTINCT FROM NEW.user_id OR s.workspace_id IS NULL THEN RETURN NEW; END IF;
 property=coalesce(nullif(NEW.building_id,''),NEW.address_id::text);
 IF property IS NULL THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-user:'||s.user_id::text,0));
 key=property||':'||s.id::text;
 -- Rebuild this property's state from durable event order, not upload arrival order.
 SELECT * INTO latest FROM session_events e WHERE e.session_id=s.id AND e.user_id=s.user_id
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property
  AND e.event_type IN ('completion_undone','flyer_left','conversation','completed_manual','completed_auto')
  ORDER BY e.created_at DESC,e.id DESC LIMIT 1;
 IF latest.event_type='completion_undone' THEN
  FOR f IN SELECT * FROM wolfy_v2_facts WHERE user_id=s.user_id AND session_id=s.id
   AND kind IN ('door','conversation') AND source_key=key AND active LOOP
   PERFORM wolfy_v2_fact(s.user_id,s.workspace_id,s.campaign_id,s.id,f.day_id,f.kind,f.source_key,false,latest.created_at);
   PERFORM wolfy_v2_reconcile_milestones(s.user_id,f.day_id,s.id,s.workspace_id,s.campaign_id,latest.created_at);
  END LOOP;
  RETURN NEW;
 END IF;
 SELECT * INTO undone FROM session_events e WHERE e.session_id=s.id AND e.user_id=s.user_id
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property AND e.event_type='completion_undone'
  ORDER BY e.created_at DESC,e.id DESC LIMIT 1;
 SELECT * INTO first_completion FROM session_events e WHERE e.session_id=s.id AND e.user_id=s.user_id
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property
  AND e.event_type IN ('flyer_left','conversation','completed_manual','completed_auto')
  AND (undone.id IS NULL OR (e.created_at,e.id)>(undone.created_at,undone.id))
  ORDER BY e.created_at,e.id LIMIT 1;
 IF first_completion.id IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO f FROM wolfy_v2_facts WHERE user_id=s.user_id AND kind='door' AND source_key=key;
 d=coalesce(f.day_id,wolfy_v2_day(s.user_id,first_completion.created_at));
 PERFORM wolfy_v2_fact(s.user_id,s.workspace_id,s.campaign_id,s.id,d,'door',key,true,latest.created_at);
 SELECT EXISTS(SELECT 1 FROM session_events e WHERE e.session_id=s.id AND e.user_id=s.user_id
  AND coalesce(nullif(e.building_id,''),e.address_id::text)=property AND e.event_type='conversation'
  AND coalesce(e.metadata->>'address_status','') IN ('talked','appointment','hot_lead','future_seller')
  AND (undone.id IS NULL OR (e.created_at,e.id)>(undone.created_at,undone.id))) INTO conversation_exists;
 PERFORM wolfy_v2_fact(s.user_id,s.workspace_id,s.campaign_id,s.id,d,'conversation',key,conversation_exists,latest.created_at);
 PERFORM wolfy_v2_reconcile_milestones(s.user_id,d,s.id,s.workspace_id,s.campaign_id,latest.created_at);
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_v2_session_activity AFTER INSERT ON session_events FOR EACH ROW EXECUTE FUNCTION wolfy_v2_session_activity();

CREATE FUNCTION public.wolfy_v2_contact_activity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE c contacts;f wolfy_v2_facts;d uuid;rowdata jsonb;event_kind text;valid boolean;at_time timestamptz;
BEGIN
 rowdata=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF TG_TABLE_NAME='contacts' THEN
  SELECT * INTO c FROM jsonb_populate_record(NULL::contacts,rowdata);
  event_kind='lead';valid=TG_OP<>'DELETE' AND c.lead_kind='field';
 ELSE
  SELECT * INTO c FROM contacts WHERE id=(rowdata->>'contact_id')::uuid;
  event_kind='appointment';valid=TG_OP<>'DELETE' AND c.id IS NOT NULL AND rowdata->>'type'='meeting'
   AND coalesce(rowdata->>'status','') NOT IN ('cancelled','canceled');
 END IF;
 -- A correction always belongs to the original earner, including cascading deletes.
 SELECT * INTO f FROM wolfy_v2_facts WHERE kind=event_kind AND source_key=(rowdata->>'id');
 IF FOUND THEN
  valid=coalesce(valid,false) AND c.user_id IS NOT DISTINCT FROM f.user_id;
  PERFORM wolfy_v2_fact(f.user_id,f.workspace_id,f.campaign_id,NULL,f.day_id,event_kind,f.source_key,valid,now());
  RETURN NULL;
 END IF;
 -- Updating pre-rollout records or changing ownership cannot manufacture a reward.
 IF TG_OP<>'INSERT' OR NOT coalesce(valid,false) OR c.user_id IS NULL OR c.workspace_id IS NULL
  OR NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE personal_enabled) THEN RETURN NULL; END IF;
 at_time=coalesce((rowdata->>'created_at')::timestamptz,now());
 d=wolfy_v2_day(c.user_id,at_time);
 PERFORM wolfy_v2_fact(c.user_id,c.workspace_id,c.campaign_id,NULL,d,event_kind,rowdata->>'id',true,at_time);
 RETURN NULL;
END $$;
CREATE TRIGGER wolfy_v2_lead_activity AFTER INSERT OR UPDATE OR DELETE ON contacts FOR EACH ROW EXECUTE FUNCTION wolfy_v2_contact_activity();
CREATE TRIGGER wolfy_v2_appointment_activity AFTER INSERT OR UPDATE OR DELETE ON contact_activities FOR EACH ROW EXECUTE FUNCTION wolfy_v2_contact_activity();

CREATE FUNCTION public.wolfy_v2_sale_activity() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE f wolfy_v2_facts;d uuid;valid boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM wolfy_v2_config WHERE personal_enabled)
  AND NOT EXISTS(SELECT 1 FROM wolfy_v2_facts WHERE kind='verified_sale' AND source_key=NEW.id::text) THEN RETURN NEW; END IF;
 valid=NEW.status='verified' AND NEW.verified_by IS NOT NULL AND NEW.verified_at IS NOT NULL;
 -- Serialize all owners in stable order before compensating a reassignment.
 PERFORM pg_advisory_xact_lock(hashtextextended('wolfy-user:'||owner_id::text,0))
 FROM (SELECT user_id owner_id FROM wolfy_v2_facts WHERE kind='verified_sale' AND source_key=NEW.id::text
       UNION SELECT NEW.rep_id) owners ORDER BY owner_id;
 FOR f IN SELECT * FROM wolfy_v2_facts WHERE kind='verified_sale' AND source_key=NEW.id::text AND user_id<>NEW.rep_id AND active LOOP
  PERFORM wolfy_v2_fact(f.user_id,f.workspace_id,f.campaign_id,NULL,f.day_id,f.kind,f.source_key,false,now());
 END LOOP;
 SELECT * INTO f FROM wolfy_v2_facts WHERE kind='verified_sale' AND source_key=NEW.id::text AND user_id=NEW.rep_id;
 IF NOT valid AND f.id IS NULL THEN RETURN NEW; END IF;
 d=coalesce(f.day_id,wolfy_v2_day(NEW.rep_id,coalesce(NEW.verified_at,now())));
 PERFORM wolfy_v2_fact(NEW.rep_id,NEW.workspace_id,NEW.campaign_id,NULL,d,'verified_sale',NEW.id::text,valid,now());
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_v2_sale_activity AFTER INSERT OR UPDATE ON field_sales FOR EACH ROW EXECUTE FUNCTION wolfy_v2_sale_activity();

CREATE OR REPLACE FUNCTION public.wolfy_v2_snapshot() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u uuid:=auth.uid();result jsonb;d wolfy_v2_days;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 INSERT INTO wolfy_v2_profiles(user_id) VALUES(u) ON CONFLICT DO NOTHING;
 SELECT * INTO d FROM wolfy_v2_days WHERE user_id=u AND now()>=starts_at AND now()<ends_at;
 SELECT jsonb_build_object('version',2,'profile',to_jsonb(p),
 'xp',greatest(0,p.imported_xp+coalesce((SELECT sum(xp) FROM wolfy_v2_ledger WHERE user_id=u),0)),
 'stage',wolfy_v2_stage(u),'config',(SELECT to_jsonb(c)-'id' FROM wolfy_v2_config c),
 'today',jsonb_build_object('door_goal',coalesce(d.door_goal,(SELECT daily_door_goal FROM user_profiles WHERE user_id=u),60),
 'doors',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='door' AND active),
 'conversations',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='conversation' AND active),
 'leads',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='lead' AND active),
 'appointments',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='appointment' AND active),
 'follow_ups',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='follow_up' AND active),
 'verified_sales',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND day_id=d.id AND kind='verified_sale' AND active)),
 'current_session_streak',(SELECT count(*) FROM wolfy_v2_facts WHERE user_id=u AND kind='door' AND active
  AND session_id=(SELECT id FROM sessions WHERE user_id=u AND end_time IS NULL ORDER BY start_time DESC,id LIMIT 1)),
 'recent_rewards',coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM (SELECT id,event_type,xp,created_at FROM wolfy_v2_ledger WHERE user_id=u ORDER BY created_at DESC,id LIMIT 20) r),'[]'::jsonb))
 INTO result FROM wolfy_v2_profiles p WHERE user_id=u;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION wolfy_v2_day(uuid,timestamptz),wolfy_v2_fact(uuid,uuid,uuid,uuid,uuid,text,text,boolean,timestamptz),
 wolfy_v2_reconcile_milestones(uuid,uuid,uuid,uuid,uuid,timestamptz),wolfy_v2_session_activity(),wolfy_v2_contact_activity(),wolfy_v2_sale_activity(),wolfy_v2_ledger_immutable() FROM PUBLIC,anon,authenticated;
COMMIT;
