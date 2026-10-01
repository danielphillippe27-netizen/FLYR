BEGIN;

-- 3-D customization is a free, immediately available wardrobe. Door-based
-- growth remains the only progression gate for the wolf's body stage.
UPDATE public.wolfy_catalog
SET price = 0,
    price_currency = 'coins',
    required_level = 1,
    required_achievement = NULL,
    active = true
WHERE render_kind = 'model3d';

-- New companions have no equipped items. Keep existing players' explicit
-- choices; the stage asset now renders unselected accessories independently.

-- Equipment references inventory in the original schema. Free customization
-- must allow a user to equip catalog items without purchasing/owning them.
DO $$
DECLARE constraint_name text;
BEGIN
  FOR constraint_name IN
    SELECT conname FROM pg_constraint
    WHERE conrelid='public.wolfy_equipment'::regclass
      AND contype='f' AND confrelid='public.wolfy_inventory'::regclass
  LOOP
    EXECUTE format('ALTER TABLE public.wolfy_equipment DROP CONSTRAINT %I',constraint_name);
  END LOOP;
END $$;
ALTER TABLE public.wolfy_equipment
  ADD CONSTRAINT wolfy_equipment_profile_fk
    FOREIGN KEY(workspace_id,user_id) REFERENCES public.wolfy_profiles(workspace_id,user_id) ON DELETE CASCADE,
  ADD CONSTRAINT wolfy_equipment_catalog_fk
    FOREIGN KEY(item_id) REFERENCES public.wolfy_catalog(id);

CREATE OR REPLACE FUNCTION public.wolfy_equip(
  p_workspace uuid,p_user uuid,p_item text,p_equipped boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item public.wolfy_catalog;
BEGIN
  PERFORM public.wolfy_assert_owner(p_workspace,p_user);
  INSERT INTO public.wolfy_profiles(workspace_id,user_id)
  VALUES(p_workspace,p_user) ON CONFLICT DO NOTHING;
  PERFORM 1 FROM public.wolfy_profiles
  WHERE workspace_id=p_workspace AND user_id=p_user FOR UPDATE;
  SELECT * INTO STRICT item FROM public.wolfy_catalog
  WHERE id=p_item AND active AND render_kind='model3d';

  IF p_equipped THEN
    INSERT INTO public.wolfy_equipment(workspace_id,user_id,slot,item_id)
    VALUES(p_workspace,p_user,item.category,p_item)
    ON CONFLICT(workspace_id,user_id,slot)
    DO UPDATE SET item_id=excluded.item_id,updated_at=now();
  ELSE
    DELETE FROM public.wolfy_equipment
    WHERE workspace_id=p_workspace AND user_id=p_user AND item_id=p_item;
  END IF;
  RETURN public.wolfy_snapshot(p_workspace,p_user);
END $$;

COMMIT;
