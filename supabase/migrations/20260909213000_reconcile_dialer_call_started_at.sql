-- The original dialer table predates the Telnyx call-log schema. The later
-- CREATE TABLE IF NOT EXISTS migration did not add this column to existing
-- tables, causing the iOS call-history select to fail with PostgreSQL 42703.
-- Keep historical values NULL; the app falls back to created_at for display.
BEGIN;

ALTER TABLE public.dialer_calls
  ADD COLUMN IF NOT EXISTS started_at timestamptz;

NOTIFY pgrst, 'reload schema';

COMMIT;
