-- Reset: delete all app data (workspaces, campaigns, sessions, contacts, etc.) so you can start fresh.
-- Does NOT delete auth.users; clear those in Supabase Dashboard → Authentication → Users if you want a full reset.
-- Run this only when you intend to wipe the database.
-- Each table is truncated only if it exists (avoids errors when migrations differ per environment).

BEGIN;

-- Helper: truncate table only if it exists
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'workspaces',
    'profiles',
    'user_stats',
    'user_settings',
    'entitlements',
    'crm_connections',
    'crm_events',
    'crm_object_links',
    'user_integrations',
    'landing_page_templates',
    'landing_pages',
    'batches',
    'farms',
    'challenges',
    'building_touches',
    'qr_sets'
  ];
BEGIN
  FOREACH t IN ARRAY tables
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
      EXECUTE format('TRUNCATE public.%I CASCADE', t);
    END IF;
  END LOOP;
END $$;

COMMIT;

-- To also remove all auth users (optional):
-- Use Supabase Dashboard → Authentication → Users → delete all,
-- or Supabase Auth Admin API: list users and delete each.
