BEGIN;

-- 3-D gear uses the same spendable XP wallet as the accessory store. Lifetime
-- XP and the door-based growth stage remain untouched by purchases.
UPDATE public.wolfy_catalog
SET price_currency = 'xp',
    required_level = 1,
    required_achievement = NULL,
    active = true
WHERE render_kind = 'model3d';

CREATE OR REPLACE FUNCTION public.wolfy_purchase(
  p_workspace uuid, p_user uuid, p_item text, p_request uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item wolfy_catalog; wallet wolfy_profiles; previous wolfy_ledger;
BEGIN
  PERFORM wolfy_assert_owner(p_workspace,p_user);
  SELECT * INTO STRICT item FROM wolfy_catalog
  WHERE id=p_item AND active AND render_kind='model3d' AND price_currency='xp';
  SELECT * INTO STRICT wallet FROM wolfy_profiles
  WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;

  SELECT * INTO previous FROM wolfy_ledger
  WHERE workspace_id=p_workspace AND user_id=p_user
    AND idempotency_key='model-purchase:'||p_request;
  IF FOUND THEN
    IF previous.related_entity IS DISTINCT FROM p_item THEN
      RAISE EXCEPTION 'Request already used for another item';
    END IF;
    RETURN wolfy_snapshot(p_workspace,p_user);
  END IF;
  IF EXISTS (SELECT 1 FROM wolfy_inventory
    WHERE workspace_id=p_workspace AND user_id=p_user AND item_id=p_item) THEN
    RETURN wolfy_snapshot(p_workspace,p_user);
  END IF;
  IF (item.starts_at IS NOT NULL AND now()<item.starts_at)
     OR (item.ends_at IS NOT NULL AND now()>item.ends_at) THEN
    RAISE EXCEPTION 'Item unavailable';
  END IF;
  IF wolfy_level(wallet.xp)<item.required_level THEN
    RAISE EXCEPTION 'Required level %',item.required_level;
  END IF;
  IF item.required_achievement IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM wolfy_achievements WHERE workspace_id=p_workspace
      AND user_id=p_user AND achievement_id=item.required_achievement
  ) THEN RAISE EXCEPTION 'Achievement required'; END IF;
  IF wallet.spendable_xp<item.price THEN RAISE EXCEPTION 'Not enough spendable XP'; END IF;

  INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,coins,spendable_xp_delta,
    reason,related_entity,idempotency_key)
  VALUES(p_workspace,p_user,'model_purchase',0,-item.price,'3-D accessory purchase',
    p_item,'model-purchase:'||p_request);
  UPDATE wolfy_profiles SET spendable_xp=spendable_xp-item.price
  WHERE workspace_id=p_workspace AND user_id=p_user;
  INSERT INTO wolfy_inventory(workspace_id,user_id,item_id)
  VALUES(p_workspace,p_user,p_item);
  RETURN wolfy_snapshot(p_workspace,p_user);
END $$;

CREATE OR REPLACE FUNCTION public.wolfy_refund(p_transaction uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old wolfy_ledger; inserted_id uuid; amount bigint;
BEGIN
  SELECT * INTO STRICT old FROM wolfy_ledger
  WHERE id=p_transaction AND source_event IN ('purchase','portrait_purchase','model_purchase');
  PERFORM 1 FROM wolfy_profiles
  WHERE workspace_id=old.workspace_id AND user_id=old.user_id FOR UPDATE;
  amount=CASE WHEN old.source_event='purchase' THEN -old.coins ELSE -old.spendable_xp_delta END;
  INSERT INTO wolfy_ledger(workspace_id,user_id,source_event,coins,spendable_xp_delta,
    reason,related_entity,idempotency_key,reversal_of)
  VALUES(old.workspace_id,old.user_id,'refund',0,amount,'Support refund',
    old.related_entity,'refund:'||old.id,old.id)
  ON CONFLICT DO NOTHING RETURNING id INTO inserted_id;
  IF inserted_id IS NOT NULL THEN
    UPDATE wolfy_profiles SET spendable_xp=spendable_xp+amount
    WHERE workspace_id=old.workspace_id AND user_id=old.user_id;
  END IF;
END $$;

COMMIT;
