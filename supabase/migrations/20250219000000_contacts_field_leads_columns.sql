-- Add field_leads-compatible columns to contacts so iOS/web can use contacts
-- instead of field_leads with a simple table switch (same shape, same behavior).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) New columns on contacts (match field_leads for easy switch)
-- ---------------------------------------------------------------------------

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS qr_code text,
  ADD COLUMN IF NOT EXISTS external_crm_id text,
  ADD COLUMN IF NOT EXISTS last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS sync_status text;

-- Constrain sync_status to same values as field_leads
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'contacts_sync_status_check'
  ) THEN
    ALTER TABLE public.contacts
      ADD CONSTRAINT contacts_sync_status_check
      CHECK (sync_status IS NULL OR sync_status IN ('pending', 'synced', 'failed'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_contacts_session_id
  ON public.contacts(session_id);

COMMENT ON COLUMN public.contacts.session_id IS 'Session when lead was captured (door session); enables filtering by session like field_leads.';
COMMENT ON COLUMN public.contacts.qr_code IS 'QR code data if lead came from QR scan.';
COMMENT ON COLUMN public.contacts.external_crm_id IS 'ID in external CRM after sync.';
COMMENT ON COLUMN public.contacts.last_synced_at IS 'Last successful sync to external CRM.';
COMMENT ON COLUMN public.contacts.sync_status IS 'pending | synced | failed; NULL if not synced.';

-- ---------------------------------------------------------------------------
-- 2) Expand status CHECK to allow field_lead values
-- So iOS can write not_home | interested | qr_scanned | no_answer directly.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  cname text;
BEGIN
  -- Drop any existing status check on contacts (name varies by Postgres version)
  FOR cname IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    WHERE rel.relname = 'contacts'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.contacts DROP CONSTRAINT IF EXISTS %I', cname);
  END LOOP;
  -- Add unified check: CRM (hot, warm, cold, new) + door (not_home, interested, qr_scanned, no_answer)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.contacts'::regclass AND conname = 'contacts_status_check'
  ) THEN
    ALTER TABLE public.contacts
      ADD CONSTRAINT contacts_status_check
      CHECK (status IN (
        'hot', 'warm', 'cold', 'new',
        'not_home', 'interested', 'qr_scanned', 'no_answer'
      ));
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3) Enable Realtime on contacts (same as field_leads for web sync)
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'contacts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.contacts;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
