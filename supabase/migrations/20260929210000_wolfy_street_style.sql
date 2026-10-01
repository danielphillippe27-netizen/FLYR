BEGIN;

-- Free cosmetic options; each occupies one wardrobe slot. Earrings use their
-- own slot so they can be worn with glasses or a cap.
INSERT INTO public.wolfy_catalog
  (id,name,category,socket,rarity,price,required_level,asset,render_kind,price_currency,active)
VALUES
  ('street_shades','Midnight Aviators','face','socket_face','common',0,1,'embedded:street_shades','model3d','coins',true),
  ('crucifix_chain','Hanging Jesus Chain','neck','socket_neck','common',0,1,'embedded:crucifix_chain','model3d','coins',true),
  ('midnight_cap','Midnight Baseball Cap','head','socket_head','common',0,1,'embedded:midnight_cap','model3d','coins',true),
  ('gold_hoops','Gold Hoop Earrings','ears','socket_head','common',0,1,'embedded:gold_hoops','model3d','coins',true),
  ('diamond_studs','Diamond Stud Earrings','ears','socket_head','common',0,1,'embedded:diamond_studs','model3d','coins',true),
  ('rose_bow','Rose Bow','head','socket_head','common',0,1,'embedded:rose_bow','model3d','coins',true),
  ('neon_glow','Neon Glow','auras','socket_aura','common',0,1,'embedded:neon_glow','model3d','coins',true)
ON CONFLICT (id) DO UPDATE SET
  name=EXCLUDED.name, category=EXCLUDED.category, socket=EXCLUDED.socket,
  price=0, required_level=1, required_achievement=NULL,
  asset=EXCLUDED.asset, render_kind='model3d', price_currency='coins', active=true;

COMMIT;
