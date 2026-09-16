-- Portrait store: spending never changes lifetime XP or rank.
BEGIN;
ALTER TABLE public.wolfy_profiles ADD COLUMN spendable_xp bigint NOT NULL DEFAULT 0 CHECK(spendable_xp>=0);
ALTER TABLE public.wolfy_ledger ADD COLUMN spendable_xp_delta bigint NOT NULL DEFAULT 0;
ALTER TABLE public.wolfy_catalog ADD COLUMN render_kind text NOT NULL DEFAULT 'model3d' CHECK(render_kind IN ('model3d','portrait'));
ALTER TABLE public.wolfy_catalog ADD COLUMN price_currency text NOT NULL DEFAULT 'coins' CHECK(price_currency IN ('coins','xp'));
-- Preserve existing purchasing power, recorded separately from earned lifetime XP.
UPDATE public.wolfy_profiles SET spendable_xp=coins;
INSERT INTO public.wolfy_ledger(workspace_id,user_id,source_event,coins,spendable_xp_delta,reason,idempotency_key)
SELECT workspace_id,user_id,'wallet_conversion',0,coins,'Unspent Grid Coins converted 1:1 to spendable XP','wallet:xp:v1'
FROM public.wolfy_profiles WHERE coins>0;
CREATE OR REPLACE FUNCTION public.wolfy_award(p_workspace uuid,p_user uuid,p_type text,p_source text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r wolfy_reward_rules; inserted_id uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id=p_workspace AND user_id=p_user) THEN RETURN false; END IF;
 SELECT * INTO STRICT r FROM wolfy_reward_rules WHERE event_type=p_type;
 INSERT INTO wolfy_profiles(workspace_id,user_id) VALUES(p_workspace,p_user) ON CONFLICT DO NOTHING;
 PERFORM 1 FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
 INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,xp,coins,spendable_xp_delta,reason,related_entity,idempotency_key)
 VALUES(p_workspace,p_user,p_type,r.xp,0,r.xp,p_type,p_source,'award:'||p_type||':'||p_source)
 ON CONFLICT DO NOTHING RETURNING id INTO inserted_id;
 IF inserted_id IS NULL THEN RETURN false; END IF;
 UPDATE wolfy_profiles SET xp=xp+r.xp,spendable_xp=spendable_xp+r.xp WHERE workspace_id=p_workspace AND user_id=p_user;
 INSERT INTO wolfy_achievements(workspace_id,user_id,achievement_id) VALUES(p_workspace,p_user,'first_'||p_type) ON CONFLICT DO NOTHING;
 RETURN true;
END $$;

-- Old clients must not spend the now-frozen legacy coin balance a second time.
CREATE OR REPLACE FUNCTION public.wolfy_purchase(p_workspace uuid,p_user uuid,p_item text,p_request uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 RAISE EXCEPTION 'Update WolfGrid to use the XP accessory store';
END $$;

CREATE FUNCTION public.wolfy_purchase_portrait(p_workspace uuid,p_user uuid,p_item text,p_request uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item wolfy_catalog; wallet wolfy_profiles; previous wolfy_ledger;
BEGIN
 PERFORM wolfy_assert_owner(p_workspace,p_user);
 SELECT * INTO STRICT item FROM wolfy_catalog WHERE id=p_item AND active AND render_kind='portrait' AND price_currency='xp';
 SELECT * INTO STRICT wallet FROM wolfy_profiles WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
 SELECT * INTO previous FROM wolfy_ledger WHERE workspace_id=p_workspace AND user_id=p_user AND idempotency_key='portrait-purchase:'||p_request;
 IF FOUND THEN
  IF previous.related_entity IS DISTINCT FROM p_item THEN RAISE EXCEPTION 'Request already used for another item'; END IF;
  RETURN wolfy_snapshot(p_workspace,p_user);
 END IF;
 IF (item.starts_at IS NOT NULL AND now()<item.starts_at) OR (item.ends_at IS NOT NULL AND now()>item.ends_at) THEN RAISE EXCEPTION 'Item unavailable'; END IF;
 IF wolfy_level(wallet.xp)<item.required_level THEN RAISE EXCEPTION 'Required level %',item.required_level; END IF;
 IF item.required_achievement IS NOT NULL AND NOT EXISTS(SELECT 1 FROM wolfy_achievements WHERE workspace_id=p_workspace AND user_id=p_user AND achievement_id=item.required_achievement) THEN RAISE EXCEPTION 'Achievement required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM wolfy_inventory WHERE workspace_id=p_workspace AND user_id=p_user AND item_id=p_item) THEN
  IF wallet.spendable_xp<item.price THEN RAISE EXCEPTION 'Not enough spendable XP'; END IF;
  INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,coins,spendable_xp_delta,reason,related_entity,idempotency_key)
  VALUES(p_workspace,p_user,'portrait_purchase',0,-item.price,'Portrait accessory purchase',p_item,'portrait-purchase:'||p_request);
  UPDATE wolfy_profiles SET spendable_xp=spendable_xp-item.price WHERE workspace_id=p_workspace AND user_id=p_user;
  INSERT INTO wolfy_inventory(workspace_id,user_id,item_id) VALUES(p_workspace,p_user,p_item);
 END IF;
 -- Buying and equipping are one transaction: failures roll back both.
 INSERT INTO wolfy_equipment(workspace_id,user_id,slot,item_id) VALUES(p_workspace,p_user,item.category,item.id)
 ON CONFLICT(workspace_id,user_id,slot) DO UPDATE SET item_id=excluded.item_id,updated_at=now();
 RETURN wolfy_snapshot(p_workspace,p_user);
END $$;
REVOKE ALL ON FUNCTION public.wolfy_purchase_portrait(uuid,uuid,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.wolfy_purchase_portrait(uuid,uuid,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.wolfy_refund(p_transaction uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old wolfy_ledger; inserted_id uuid; amount bigint;
BEGIN
 SELECT * INTO STRICT old FROM wolfy_ledger WHERE id=p_transaction AND source_event IN ('purchase','portrait_purchase');
 PERFORM 1 FROM wolfy_profiles WHERE workspace_id=old.workspace_id AND user_id=old.user_id FOR UPDATE;
 amount=CASE WHEN old.source_event='purchase' THEN -old.coins ELSE -old.spendable_xp_delta END;
 INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,coins,spendable_xp_delta,reason,related_entity,idempotency_key,reversal_of)
 VALUES(old.workspace_id,old.user_id,'refund',0,amount,'Support refund',old.related_entity,'refund:'||old.id,old.id)
 ON CONFLICT DO NOTHING RETURNING id INTO inserted_id;
 IF inserted_id IS NOT NULL THEN UPDATE wolfy_profiles SET spendable_xp=spendable_xp+amount WHERE workspace_id=old.workspace_id AND user_id=old.user_id; END IF;
END $$;

INSERT INTO public.wolfy_catalog(id,name,category,socket,rarity,price,required_level,asset,render_kind,price_currency) VALUES
('portrait_chain_silver','Silver Chain','neck','portrait_neck','common',150,1,'chain_silver','portrait','xp'),
('portrait_chain_gold','Gold Chain','neck','portrait_neck','rare',400,1,'chain_gold','portrait','xp'),
('portrait_chain_cuban','Cuban Link','neck','portrait_neck','epic',900,1,'chain_cuban','portrait','xp'),
('portrait_chain_orange','Orange Pendant','neck','portrait_neck','rare',600,1,'chain_orange','portrait','xp'),
('portrait_glasses_classic','Classic Shades','eyewear','portrait_eyes','common',100,1,'glasses_classic','portrait','xp'),
('portrait_glasses_aviator','Gold Aviators','eyewear','portrait_eyes','rare',300,1,'glasses_aviator','portrait','xp'),
('portrait_glasses_round','Round Frames','eyewear','portrait_eyes','common',250,1,'glasses_round','portrait','xp'),
('portrait_glasses_visor','Orange Visor','eyewear','portrait_eyes','epic',650,1,'glasses_visor','portrait','xp'),
('portrait_collar_orange','WolfGrid Collar','neck','portrait_neck','common',75,1,'collar_orange','portrait','xp'),
('portrait_collar_black','Midnight Collar','neck','portrait_neck','common',100,1,'collar_black','portrait','xp'),
('portrait_collar_teal','Teal Collar','neck','portrait_neck','common',150,1,'collar_teal','portrait','xp'),
('portrait_collar_studded','Studded Collar','neck','portrait_neck','rare',350,1,'collar_studded','portrait','xp'),
('portrait_aura_ember','Ember Glow','aura','portrait_aura','common',100,1,'aura_ember','portrait','xp'),
('portrait_aura_ice','Arctic Glow','aura','portrait_aura','rare',250,1,'aura_ice','portrait','xp'),
('portrait_aura_gold','Golden Glow','aura','portrait_aura','rare',500,1,'aura_gold','portrait','xp'),
('portrait_aura_prism','Prism Glow','aura','portrait_aura','epic',900,1,'aura_prism','portrait','xp');
COMMIT;
