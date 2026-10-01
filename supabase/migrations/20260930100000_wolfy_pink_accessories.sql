BEGIN;

-- Free pink colorways of every fitted 3-D wolf accessory.
-- Each variant uses the same category slot as its original.
INSERT INTO public.wolfy_catalog
  (id,name,category,socket,rarity,price,required_level,asset,render_kind,price_currency,active)
VALUES
  ('pink_basic_collar', 'Pink Basic Collar', 'neck', 'socket_neck', 'common',0,1,'embedded:pink_basic_collar','model3d','coins',true),
  ('pink_bandana', 'Pink Bandana', 'neck', 'socket_neck', 'common',0,1,'embedded:pink_bandana','model3d','coins',true),
  ('pink_chain', 'Pink Chain', 'neck', 'socket_neck', 'common',0,1,'embedded:pink_chain','model3d','coins',true),
  ('pink_gold_chain', 'Pink Heavy Chain', 'neck', 'socket_neck', 'common',0,1,'embedded:pink_gold_chain','model3d','coins',true),
  ('pink_cap', 'Pink WolfGrid Cap', 'head', 'socket_head', 'common',0,1,'embedded:pink_cap','model3d','coins',true),
  ('pink_beanie', 'Pink Beanie', 'head', 'socket_head', 'common',0,1,'embedded:pink_beanie','model3d','coins',true),
  ('pink_hard_hat', 'Pink Roofing Hard Hat', 'head', 'socket_head', 'common',0,1,'embedded:pink_hard_hat','model3d','coins',true),
  ('pink_glasses', 'Pink Glasses', 'face', 'socket_face', 'common',0,1,'embedded:pink_glasses','model3d','coins',true),
  ('pink_sunglasses', 'Pink Sunglasses', 'face', 'socket_face', 'common',0,1,'embedded:pink_sunglasses','model3d','coins',true),
  ('pink_headset', 'Pink Headset', 'head', 'socket_head', 'common',0,1,'embedded:pink_headset','model3d','coins',true),
  ('pink_clipboard', 'Pink Clipboard', 'hands', 'socket_hand_l', 'common',0,1,'embedded:pink_clipboard','model3d','coins',true),
  ('pink_tablet', 'Pink Sales Tablet', 'hands', 'socket_hand_l', 'common',0,1,'embedded:pink_tablet','model3d','coins',true),
  ('pink_backpack', 'Pink WolfGrid Backpack', 'back', 'socket_back', 'common',0,1,'embedded:pink_backpack','model3d','coins',true),
  ('pink_hi_vis', 'Pink Vest', 'outerwear', 'socket_chest', 'common',0,1,'embedded:pink_hi_vis','model3d','coins',true),
  ('pink_storm_jacket', 'Pink Storm Jacket', 'outerwear', 'socket_chest', 'common',0,1,'embedded:pink_storm_jacket','model3d','coins',true),
  ('pink_alpha_jacket', 'Pink Alpha Bomber', 'outerwear', 'socket_chest', 'common',0,1,'embedded:pink_alpha_jacket','model3d','coins',true),
  ('pink_tool_belt', 'Pink Tool Belt', 'waist', 'socket_waist', 'common',0,1,'embedded:pink_tool_belt','model3d','coins',true),
  ('pink_blue_aura', 'Pink Aura', 'auras', 'socket_aura', 'common',0,1,'embedded:pink_blue_aura','model3d','coins',true),
  ('pink_white_sneakers', 'Pink Sneakers', 'feet', 'socket_feet', 'common',0,1,'embedded:pink_white_sneakers','model3d','coins',true),
  ('pink_work_boots', 'Pink Premium Work Boots', 'feet', 'socket_feet', 'common',0,1,'embedded:pink_work_boots','model3d','coins',true),
  ('pink_gloves', 'Pink Work Gloves', 'hands', 'socket_hand_r', 'common',0,1,'embedded:pink_gloves','model3d','coins',true),
  ('pink_street_shades', 'Pink Midnight Aviators', 'face', 'socket_face', 'common',0,1,'embedded:pink_street_shades','model3d','coins',true),
  ('pink_crucifix_chain', 'Pink Hanging Jesus Chain', 'neck', 'socket_neck', 'common',0,1,'embedded:pink_crucifix_chain','model3d','coins',true),
  ('pink_midnight_cap', 'Pink Midnight Baseball Cap', 'head', 'socket_head', 'common',0,1,'embedded:pink_midnight_cap','model3d','coins',true),
  ('pink_gold_hoops', 'Pink Hoop Earrings', 'ears', 'socket_head', 'common',0,1,'embedded:pink_gold_hoops','model3d','coins',true),
  ('pink_diamond_studs', 'Pink Stud Earrings', 'ears', 'socket_head', 'common',0,1,'embedded:pink_diamond_studs','model3d','coins',true),
  ('pink_rose_bow', 'Pink Rose Bow', 'head', 'socket_head', 'common',0,1,'embedded:pink_rose_bow','model3d','coins',true),
  ('pink_neon_glow', 'Pink Neon Glow', 'auras', 'socket_aura', 'common',0,1,'embedded:pink_neon_glow','model3d','coins',true)
ON CONFLICT (id) DO UPDATE SET
  name=EXCLUDED.name, category=EXCLUDED.category, socket=EXCLUDED.socket,
  price=0, required_level=1, required_achievement=NULL,
  asset=EXCLUDED.asset, render_kind='model3d', price_currency='coins', active=true;

COMMIT;
