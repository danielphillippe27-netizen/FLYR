-- Add clearly identified, non-sign-in demo accounts to the live leaderboard.
-- Target: the Supabase project bundled by the iOS app (kfnsnwqylsdsbgnwgxva).
-- Run with: supabase db query --linked --file supabase/seed_leaderboard_ryan_crow.sql
-- Safe to rerun: deterministic account and session IDs update only these demo rows.
-- Existing users and their sessions are never changed.

BEGIN;

DO $seed$
DECLARE
  item RECORD;
  demo_user_id UUID;
  demo_session_id UUID;
  demo_email TEXT;
  instance_id UUID;
BEGIN
  SELECT id INTO instance_id FROM auth.instances LIMIT 1;
  instance_id := COALESCE(instance_id, '00000000-0000-0000-0000-000000000000'::UUID);

  FOR item IN
    SELECT * FROM (VALUES
      ('ryan-crow',       'Ryan',     'Crow',       2600, 286, 74, 92.4),
      ('chloe-bennett',   'Chloe',    'Bennett',     734,  82, 21, 31.8),
      ('owen-mitchell',   'Owen',     'Mitchell',    661,  75, 18, 29.4),
      ('isabella-ross',   'Isabella', 'Ross',        593,  69, 17, 27.1),
      ('lucas-grant',     'Lucas',    'Grant',       551,  61, 15, 25.2),
      ('zoe-thompson',    'Zoe',      'Thompson',    472,  54, 14, 22.8),
      ('benjamin-lee',    'Benjamin','Lee',         406,  46, 12, 19.7),
      ('amelia-foster',   'Amelia',   'Foster',      367,  43, 11, 18.1),
      ('jackson-morris',  'Jackson',  'Morris',      319,  37,  9, 15.5),
      ('natalie-ward',    'Natalie',  'Ward',        274,  31,  8, 13.6),
      ('caleb-hughes',    'Caleb',    'Hughes',      236,  28,  7, 11.9),
      ('ella-sullivan',   'Ella',     'Sullivan',    191,  23,  6,  9.7),
      ('adrian-cooper',   'Adrian',   'Cooper',      163,  19,  5,  8.5),
      ('ruby-nguyen',     'Ruby',     'Nguyen',      139,  16,  4,  7.2),
      ('mason-clarke',    'Mason',    'Clarke',      113,  13,  3,  5.9),
      ('leila-ahmed',     'Leila',    'Ahmed',        87,  10,  2,  4.6)
    ) AS v(slug, first_name, last_name, doors, conversations, leads, distance_km)
  LOOP
    demo_user_id := md5('wolfgrid-leaderboard-demo-v2:user:' || item.slug)::UUID;
    demo_session_id := md5('wolfgrid-leaderboard-demo-v2:session:' || item.slug)::UUID;
    demo_email := 'leaderboard.demo.' || item.slug || '@example.com';

    IF EXISTS (
      SELECT 1 FROM auth.users
      WHERE (id = demo_user_id AND email IS DISTINCT FROM demo_email)
         OR (email = demo_email AND id <> demo_user_id)
    ) THEN
      RAISE EXCEPTION 'Demo account ID or email collision for %', item.slug;
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.sessions
      WHERE id = demo_session_id AND user_id <> demo_user_id
    ) THEN
      RAISE EXCEPTION 'Demo session ID collision for %', item.slug;
    END IF;

    -- No password or auth identity is created: these are display-only accounts.
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, raw_user_meta_data,
      raw_app_meta_data, created_at, updated_at
    ) VALUES (
      demo_user_id, instance_id, 'authenticated', 'authenticated', demo_email,
      jsonb_build_object('full_name', item.first_name || ' ' || item.last_name,
                         'country_code', 'CA', 'brokerage', 'Demo participant',
                         'is_mock', true,
                         'mock_source', 'leaderboard-demo-v2'),
      '{"provider":"email","providers":["email"]}'::JSONB, NOW(), NOW()
    ) ON CONFLICT (id) DO UPDATE SET
      raw_user_meta_data = EXCLUDED.raw_user_meta_data,
      updated_at = NOW();

    INSERT INTO public.profiles (id, email, full_name, first_name, last_name)
    VALUES (demo_user_id, demo_email, item.first_name || ' ' || item.last_name,
            item.first_name, item.last_name)
    ON CONFLICT (id) DO UPDATE SET
      full_name = EXCLUDED.full_name,
      first_name = EXCLUDED.first_name,
      last_name = EXCLUDED.last_name;

    INSERT INTO public.user_profiles (user_id, first_name, last_name, country_code)
    VALUES (demo_user_id, item.first_name, item.last_name, 'CA')
    ON CONFLICT (user_id) DO UPDATE SET
      first_name = EXCLUDED.first_name,
      last_name = EXCLUDED.last_name,
      country_code = EXCLUDED.country_code;

    INSERT INTO public.sessions (
      id, user_id, start_time, end_time, distance_meters,
      goal_type, goal_amount, path_geojson, doors_hit, completed_count,
      flyers_delivered, conversations, leads_created, notes
    ) VALUES (
      demo_session_id, demo_user_id, NOW() - INTERVAL '2 days',
      NOW() - INTERVAL '2 days' + INTERVAL '3 hours', item.distance_km * 1000,
      'knocks', item.doors, '{"type":"LineString","coordinates":[]}',
      item.doors, item.doors, item.doors, item.conversations, item.leads,
      'Synthetic leaderboard demo data; source=leaderboard-demo-v2'
    ) ON CONFLICT (id) DO UPDATE SET
      distance_meters = EXCLUDED.distance_meters,
      goal_amount = EXCLUDED.goal_amount,
      doors_hit = EXCLUDED.doors_hit,
      completed_count = EXCLUDED.completed_count,
      flyers_delivered = EXCLUDED.flyers_delivered,
      conversations = EXCLUDED.conversations,
      leads_created = EXCLUDED.leads_created;
  END LOOP;
END;
$seed$;

COMMIT;
