BEGIN;
CREATE TABLE public.wolfy_profiles (
 workspace_id uuid NOT NULL REFERENCES public.workspaces(id), user_id uuid NOT NULL REFERENCES auth.users(id),
 timezone text NOT NULL DEFAULT 'UTC',
 xp bigint NOT NULL DEFAULT 0 CHECK(xp>=0), coins bigint NOT NULL DEFAULT 0 CHECK(coins>=0),
 happiness integer NOT NULL DEFAULT 60 CHECK(happiness BETWEEN 0 AND 100),
 last_feed timestamptz, last_play timestamptz, work_start integer NOT NULL DEFAULT 9 CHECK(work_start BETWEEN 0 AND 23),
 work_end integer NOT NULL DEFAULT 18 CHECK(work_end BETWEEN 0 AND 23), dnd boolean NOT NULL DEFAULT false,
 PRIMARY KEY(workspace_id,user_id)
);
CREATE TABLE public.wolfy_catalog (
 id text PRIMARY KEY, name text NOT NULL, category text NOT NULL, socket text NOT NULL,
 rarity text NOT NULL, price integer NOT NULL CHECK(price>=0), required_level integer NOT NULL DEFAULT 1 CHECK(required_level>=1),
 required_achievement text, asset text, active boolean NOT NULL DEFAULT true,
 starts_at timestamptz, ends_at timestamptz
);
CREATE TABLE public.wolfy_ledger (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL, user_id uuid NOT NULL,
 source_event text NOT NULL, xp bigint NOT NULL DEFAULT 0 CHECK(xp>=0), coins bigint NOT NULL,
 reason text NOT NULL, related_entity text, idempotency_key text NOT NULL,
 reversal_of uuid REFERENCES public.wolfy_ledger(id), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(workspace_id,user_id,idempotency_key), FOREIGN KEY(workspace_id,user_id) REFERENCES public.wolfy_profiles
);
CREATE UNIQUE INDEX wolfy_one_reversal ON public.wolfy_ledger(reversal_of) WHERE reversal_of IS NOT NULL;
CREATE TABLE public.wolfy_inventory (
 workspace_id uuid NOT NULL, user_id uuid NOT NULL, item_id text NOT NULL REFERENCES public.wolfy_catalog(id),
 acquired_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(workspace_id,user_id,item_id),
 FOREIGN KEY(workspace_id,user_id) REFERENCES public.wolfy_profiles
);
CREATE TABLE public.wolfy_equipment (
 workspace_id uuid NOT NULL, user_id uuid NOT NULL, slot text NOT NULL, item_id text NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(workspace_id,user_id,slot),
 FOREIGN KEY(workspace_id,user_id,item_id) REFERENCES public.wolfy_inventory(workspace_id,user_id,item_id)
);
CREATE TABLE public.wolfy_achievements (
 workspace_id uuid NOT NULL, user_id uuid NOT NULL, achievement_id text NOT NULL,
 earned_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(workspace_id,user_id,achievement_id),
 FOREIGN KEY(workspace_id,user_id) REFERENCES public.wolfy_profiles
);
CREATE TABLE public.wolfy_interactions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL, user_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('feed','play','train')), created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(workspace_id,user_id) REFERENCES public.wolfy_profiles
);
CREATE TABLE public.wolfy_reward_claims (
 workspace_id uuid NOT NULL,user_id uuid NOT NULL,event_type text NOT NULL,entity_id text NOT NULL,
 PRIMARY KEY(workspace_id,user_id,event_type,entity_id)
);
ALTER TABLE public.wolfy_reward_claims ENABLE ROW LEVEL SECURITY;
CREATE TABLE public.wolfy_reward_rules (
 event_type text PRIMARY KEY, xp integer NOT NULL CHECK(xp>=0), coins integer NOT NULL CHECK(coins>=0)
);
INSERT INTO public.wolfy_reward_rules VALUES ('door',2,1),('conversation',5,2),('qualified_lead',30,15),
 ('appointment',60,30),('verified_sale',250,125),('goal',50,25),('training',10,5),('follow_up',15,8),('campaign',100,50),('streak',25,12);

CREATE FUNCTION public.wolfy_level(p_xp bigint) RETURNS integer LANGUAGE sql IMMUTABLE AS $$
 SELECT least(100,1+floor(sqrt(greatest(0,p_xp)::numeric/100))::integer)
$$;
CREATE FUNCTION public.wolfy_assert_owner(p_workspace uuid,p_user uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS DISTINCT FROM p_user OR NOT EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id=p_workspace AND user_id=p_user)
 THEN RAISE EXCEPTION 'Workspace owner access required' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.wolfy_immutable_ledger() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Wolfy ledger is append only'; END $$;
CREATE TRIGGER wolfy_ledger_no_mutation BEFORE UPDATE OR DELETE ON public.wolfy_ledger FOR EACH ROW EXECUTE FUNCTION public.wolfy_immutable_ledger();

-- Internal/server-only award path. Clients never supply award amounts or facts.
CREATE FUNCTION public.wolfy_award(p_workspace uuid,p_user uuid,p_type text,p_source text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r wolfy_reward_rules; inserted_id uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id=p_workspace AND user_id=p_user) THEN RETURN false; END IF;
 SELECT * INTO STRICT r FROM wolfy_reward_rules WHERE event_type=p_type;
 INSERT INTO wolfy_profiles(workspace_id,user_id) VALUES(p_workspace,p_user) ON CONFLICT DO NOTHING;
 PERFORM 1 FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
 INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,xp,coins,reason,related_entity,idempotency_key)
 VALUES(p_workspace,p_user,p_type,r.xp,r.coins,p_type,p_source,'award:'||p_type||':'||p_source)
 ON CONFLICT DO NOTHING RETURNING id INTO inserted_id;
 IF inserted_id IS NULL THEN RETURN false; END IF;
 UPDATE wolfy_profiles SET xp=xp+r.xp,coins=coins+r.coins WHERE workspace_id=p_workspace AND user_id=p_user;
 INSERT INTO wolfy_achievements(workspace_id,user_id,achievement_id) VALUES(p_workspace,p_user,'first_'||p_type) ON CONFLICT DO NOTHING;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_award(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wolfy_award(uuid,uuid,text,text) TO service_role;

CREATE FUNCTION public.wolfy_settings(p_workspace uuid,p_user uuid,p_start integer,p_end integer,p_dnd boolean,p_timezone text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'Unknown timezone'; END IF;
 UPDATE wolfy_profiles SET work_start=p_start,work_end=p_end,dnd=p_dnd,timezone=p_timezone WHERE workspace_id=p_workspace AND user_id=p_user;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_settings(uuid,uuid,integer,integer,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_settings(uuid,uuid,integer,integer,boolean,text) TO authenticated;

CREATE FUNCTION public.wolfy_reconcile_goals(p_workspace uuid,p_user uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE zone text; day_start timestamptz; week_start timestamptz; m jsonb; daily integer; weekly integer;
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 SELECT timezone INTO zone FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user;
 day_start=date_trunc('day',now() AT TIME ZONE zone) AT TIME ZONE zone;
 week_start=date_trunc('week',now() AT TIME ZONE zone) AT TIME ZONE zone;
 SELECT daily_door_goal,weekly_door_goal INTO daily,weekly FROM user_profiles WHERE user_id=p_user;
 m=wolfy_home_metrics(p_workspace,day_start,week_start,now());
 IF daily>0 AND (m->>'doors')::integer>=daily THEN PERFORM wolfy_award(p_workspace,p_user,'goal','day:'||day_start::date); END IF;
 IF weekly>0 AND (m->>'weekly_doors')::integer>=weekly THEN PERFORM wolfy_award(p_workspace,p_user,'goal','week:'||week_start::date); END IF;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_reconcile_goals(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.wolfy_snapshot(p_workspace uuid,p_user uuid,p_timezone text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 INSERT INTO wolfy_profiles(workspace_id,user_id) VALUES(p_workspace,p_user) ON CONFLICT DO NOTHING;
 IF p_timezone IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN RAISE EXCEPTION 'Unknown timezone'; END IF;
  UPDATE wolfy_profiles SET timezone=p_timezone WHERE workspace_id=p_workspace AND user_id=p_user;
 END IF;
 PERFORM wolfy_reconcile_goals(p_workspace,p_user);
 INSERT INTO wolfy_inventory(workspace_id,user_id,item_id) SELECT p_workspace,p_user,id FROM wolfy_catalog WHERE price=0 AND active ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('profile',(SELECT to_jsonb(p) FROM wolfy_profiles p WHERE workspace_id=p_workspace AND user_id=p_user),
 'owned',coalesce((SELECT jsonb_agg(item_id) FROM wolfy_inventory WHERE workspace_id=p_workspace AND user_id=p_user),'[]'::jsonb),
 'equipped',coalesce((SELECT jsonb_object_agg(slot,item_id) FROM wolfy_equipment WHERE workspace_id=p_workspace AND user_id=p_user),'{}'::jsonb),
 'achievements',coalesce((SELECT jsonb_agg(achievement_id) FROM wolfy_achievements WHERE workspace_id=p_workspace AND user_id=p_user),'[]'::jsonb),
 'rewards',coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM (SELECT id,source_event FROM wolfy_ledger WHERE workspace_id=p_workspace AND user_id=p_user AND xp>0 ORDER BY created_at DESC LIMIT 5) r),'[]'::jsonb),
 'catalog',(SELECT jsonb_agg(to_jsonb(c)) FROM wolfy_catalog c WHERE active));
END $$;

CREATE FUNCTION public.wolfy_purchase(p_workspace uuid,p_user uuid,p_item text,p_request uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item wolfy_catalog; wallet wolfy_profiles; old wolfy_ledger;
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 SELECT * INTO STRICT item FROM wolfy_catalog WHERE id=p_item AND active;
 SELECT * INTO STRICT wallet FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
 SELECT * INTO old FROM wolfy_ledger WHERE workspace_id=p_workspace AND user_id=p_user AND idempotency_key='purchase:'||p_request;
 IF FOUND THEN
  IF old.related_entity IS DISTINCT FROM p_item THEN RAISE EXCEPTION 'Request already used for another item'; END IF;
  RETURN wolfy_snapshot(p_workspace,p_user);
 END IF;
 IF EXISTS(SELECT 1 FROM wolfy_inventory WHERE workspace_id=p_workspace AND user_id=p_user AND item_id=p_item) THEN RETURN wolfy_snapshot(p_workspace,p_user); END IF;
 IF (item.starts_at IS NOT NULL AND now()<item.starts_at) OR (item.ends_at IS NOT NULL AND now()>item.ends_at) THEN RAISE EXCEPTION 'Item unavailable'; END IF;
 IF wolfy_level(wallet.xp)<item.required_level THEN RAISE EXCEPTION 'Required level %',item.required_level; END IF;
 IF item.required_achievement IS NOT NULL AND NOT EXISTS(SELECT 1 FROM wolfy_achievements WHERE workspace_id=p_workspace AND user_id=p_user AND achievement_id=item.required_achievement) THEN RAISE EXCEPTION 'Achievement required'; END IF;
 IF wallet.coins<item.price THEN RAISE EXCEPTION 'Insufficient Grid Coins'; END IF;
 INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,coins,reason,related_entity,idempotency_key)
 VALUES(p_workspace,p_user,'purchase',-item.price,'Accessory purchase',p_item,'purchase:'||p_request);
 UPDATE wolfy_profiles SET coins=coins-item.price WHERE workspace_id=p_workspace AND user_id=p_user;
 INSERT INTO wolfy_inventory(workspace_id,user_id,item_id) VALUES(p_workspace,p_user,p_item);
 RETURN wolfy_snapshot(p_workspace,p_user);
END $$;

-- Support-only coin refund, appended as a reversal. XP is never changed.
CREATE FUNCTION public.wolfy_refund(p_transaction uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old wolfy_ledger; inserted_id uuid;
BEGIN
 SELECT * INTO STRICT old FROM wolfy_ledger WHERE id=p_transaction AND source_event='purchase';
 PERFORM 1 FROM wolfy_profiles WHERE workspace_id=old.workspace_id AND user_id=old.user_id FOR UPDATE;
 INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,coins,reason,related_entity,idempotency_key,reversal_of)
 VALUES(old.workspace_id,old.user_id,'refund',-old.coins,'Support refund',old.related_entity,'refund:'||old.id,old.id)
 ON CONFLICT DO NOTHING RETURNING id INTO inserted_id;
 IF inserted_id IS NOT NULL THEN UPDATE wolfy_profiles SET coins=coins-old.coins WHERE workspace_id=old.workspace_id AND user_id=old.user_id; END IF;
END $$;
REVOKE ALL ON FUNCTION public.wolfy_refund(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wolfy_refund(uuid) TO service_role;

CREATE FUNCTION public.wolfy_equip(p_workspace uuid,p_user uuid,p_item text,p_equipped boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item wolfy_catalog;
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 PERFORM 1 FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
 SELECT c.* INTO STRICT item FROM wolfy_catalog c JOIN wolfy_inventory i ON i.item_id=c.id
 WHERE i.workspace_id=p_workspace AND i.user_id=p_user AND c.id=p_item;
 IF p_equipped THEN
  INSERT INTO wolfy_equipment(workspace_id,user_id,slot,item_id) VALUES(p_workspace,p_user,item.category,p_item)
  ON CONFLICT(workspace_id,user_id,slot) DO UPDATE SET item_id=excluded.item_id,updated_at=now();
 ELSE DELETE FROM wolfy_equipment WHERE workspace_id=p_workspace AND user_id=p_user AND item_id=p_item;
 END IF;
 RETURN wolfy_snapshot(p_workspace,p_user);
END $$;

CREATE FUNCTION public.wolfy_interact(p_workspace uuid,p_user uuid,p_kind text,p_answer text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE wallet wolfy_profiles;
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 SELECT * INTO STRICT wallet FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
 IF p_kind='feed' THEN
  IF wallet.last_feed>now()-interval '4 hours' THEN RAISE EXCEPTION 'Treat available every four hours'; END IF;
  UPDATE wolfy_profiles SET happiness=least(100,happiness+3),last_feed=now() WHERE workspace_id=p_workspace AND user_id=p_user;
 ELSIF p_kind='play' THEN
  IF wallet.last_play>now()-interval '30 minutes' THEN RAISE EXCEPTION 'Play available every thirty minutes'; END IF;
  UPDATE wolfy_profiles SET happiness=least(100,happiness+2),last_play=now() WHERE workspace_id=p_workspace AND user_id=p_user;
 ELSIF p_kind='train' THEN
  -- A fixed server-reviewed objection drill; the client cannot submit arbitrary reward claims.
  IF p_answer IS DISTINCT FROM 'ask_permission' THEN RAISE EXCEPTION 'Try acknowledging the objection and asking permission for one question'; END IF;
  PERFORM wolfy_award(p_workspace,p_user,'training',to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD'));
 ELSE RAISE EXCEPTION 'Unknown interaction'; END IF;
 INSERT INTO wolfy_interactions(workspace_id,user_id,kind) VALUES(p_workspace,p_user,p_kind);
 RETURN wolfy_snapshot(p_workspace,p_user);
END $$;

CREATE FUNCTION public.wolfy_record_business_event() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE w uuid; u uuid; source text; claimed text;
BEGIN
 IF TG_TABLE_NAME='session_events' THEN
  SELECT workspace_id,user_id INTO w,u FROM sessions WHERE id=NEW.session_id;
  source=coalesce(NEW.building_id::text,NEW.address_id::text)||':'||to_char(NEW.created_at AT TIME ZONE 'UTC','YYYY-MM-DD');
  IF NEW.event_type IN ('flyer_left','conversation','completed_manual','completed_auto') AND source IS NOT NULL THEN
   PERFORM wolfy_award(w,u,'door',source);
   IF NEW.event_type='conversation' AND coalesce(NEW.metadata->>'address_status','') IN ('talked','appointment','hot_lead','future_seller') THEN PERFORM wolfy_award(w,u,'conversation',source); END IF;
  END IF;
 ELSIF TG_TABLE_NAME='contacts' THEN
  IF NEW.workspace_id IS NOT NULL AND NEW.lead_kind='field' AND NEW.status IN ('qualified','hot_lead','appointment') THEN
   source=coalesce(nullif(regexp_replace(coalesce(NEW.phone,''),'[^0-9]','','g'),''),nullif(lower(trim(NEW.email)),''),nullif(lower(trim(NEW.address)),''),NEW.id::text);
   source=md5(source);
   INSERT INTO wolfy_reward_claims VALUES(NEW.workspace_id,NEW.user_id,'qualified_lead',NEW.id::text)
   ON CONFLICT DO NOTHING RETURNING entity_id INTO claimed;
   IF claimed IS NOT NULL THEN PERFORM wolfy_award(NEW.workspace_id,NEW.user_id,'qualified_lead',source); END IF;
  END IF;
 ELSIF TG_TABLE_NAME='contact_activities' AND NEW.type='meeting' THEN
  SELECT workspace_id,user_id INTO w,u FROM contacts WHERE id=NEW.contact_id;
  PERFORM wolfy_award(w,u,'appointment',NEW.contact_id::text);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER wolfy_session_reward AFTER INSERT ON public.session_events FOR EACH ROW EXECUTE FUNCTION public.wolfy_record_business_event();
CREATE TRIGGER wolfy_lead_reward AFTER INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.wolfy_record_business_event();
CREATE TRIGGER wolfy_appointment_reward AFTER INSERT ON public.contact_activities FOR EACH ROW EXECUTE FUNCTION public.wolfy_record_business_event();

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['wolfy_profiles','wolfy_ledger','wolfy_inventory','wolfy_equipment','wolfy_achievements','wolfy_interactions'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY owner_read ON public.%I FOR SELECT TO authenticated USING (user_id=auth.uid() AND EXISTS(SELECT 1 FROM public.workspace_members m WHERE m.workspace_id=%I.workspace_id AND m.user_id=auth.uid()))',t,t);
  EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 END LOOP;
END $$;
ALTER TABLE public.wolfy_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_read ON public.wolfy_catalog FOR SELECT TO authenticated USING(active);
GRANT SELECT ON public.wolfy_catalog TO authenticated;
ALTER TABLE public.wolfy_reward_rules ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION public.wolfy_assert_owner(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wolfy_snapshot(uuid,uuid,text),public.wolfy_purchase(uuid,uuid,text,uuid),public.wolfy_equip(uuid,uuid,text,boolean),public.wolfy_interact(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_snapshot(uuid,uuid,text),public.wolfy_purchase(uuid,uuid,text,uuid),public.wolfy_equip(uuid,uuid,text,boolean),public.wolfy_interact(uuid,uuid,text,text) TO authenticated;
INSERT INTO public.wolfy_catalog(id,name,category,socket,rarity,price,required_level,asset) VALUES
('default_hoodie','Black W Hoodie','tops','socket_chest','common',0,1,NULL),
('default_pants','Dark Cargo Pants','pants','socket_waist','common',0,1,NULL),
('default_shoes','Black and White Sneakers','feet','socket_feet','common',0,1,NULL),
('basic_collar','Basic Collar','neck','socket_neck','common',0,1,'basic_collar.usdz'),
('default_den','Default Den','den','socket_vehicle_scene','common',0,1,NULL),
('cap','WolfGrid Cap','head','socket_head','common',150,1,'cap.usdz'),
('beanie','Black Beanie','head','socket_head','common',100,1,'beanie.usdz'),
('silver_chain','Silver Chain','neck','socket_neck','common',200,1,'silver_chain.usdz'),
('glasses','Clear Glasses','face','socket_face','common',150,1,'glasses.usdz'),
('sunglasses','Dark Sunglasses','face','socket_face','common',200,1,'sunglasses.usdz'),
('bandana','Black Bandana','neck','socket_neck','common',100,1,'bandana.usdz'),
('white_sneakers','White Sneakers','feet','socket_feet','common',300,1,'white_sneakers.usdz'),
('gloves','Work Gloves','hands','socket_hand_r','common',200,1,'gloves.usdz'),
('hard_hat','Roofing Hard Hat','head','socket_head','rare',500,10,'hard_hat.usdz'),
('hi_vis','High Visibility Vest','outerwear','socket_chest','rare',500,10,'hi_vis.usdz'),
('tool_belt','Tool Belt','waist','socket_waist','rare',600,10,'tool_belt.usdz'),
('clipboard','Clipboard','hands','socket_hand_l','rare',400,10,'clipboard.usdz'),
('backpack','WolfGrid Backpack','back','socket_back','rare',700,10,'backpack.usdz'),
('storm_jacket','Storm Jacket','outerwear','socket_chest','rare',900,10,'storm_jacket.usdz'),
('work_boots','Premium Work Boots','feet','socket_feet','rare',650,10,'work_boots.usdz'),
('headset','Headset','head','socket_head','rare',450,10,'headset.usdz'),
('alpha_jacket','Alpha Bomber','outerwear','socket_chest','epic',1800,50,'alpha_jacket.usdz'),
('gold_chain','Heavy Gold Chain','neck','socket_neck','epic',1500,25,'gold_chain.usdz'),
('tablet','Sales Tablet','hands','socket_hand_l','epic',1200,25,'tablet.usdz'),
('blue_aura','Electric Blue Aura','auras','socket_aura','epic',2500,25,'blue_aura.usdz');
COMMIT;
