-- Telnyx-backed call log for iOS salesperson inbox, especially missed calls.

BEGIN;

CREATE TABLE IF NOT EXISTS public.dialer_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  provider text NOT NULL DEFAULT 'telnyx',
  provider_call_id text,
  direction text NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  from_number_e164 text,
  to_number_e164 text,
  status text NOT NULL DEFAULT 'missed',
  disposition text,
  started_at timestamptz,
  answered_at timestamptz,
  ended_at timestamptz,
  missed_at timestamptz,
  duration_seconds integer,
  raw_payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_dialer_calls_provider_call_id
  ON public.dialer_calls(provider, provider_call_id)
  WHERE provider_call_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dialer_calls_workspace_created
  ON public.dialer_calls(workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dialer_calls_contact_created
  ON public.dialer_calls(contact_id, created_at DESC)
  WHERE contact_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dialer_calls_missed
  ON public.dialer_calls(workspace_id, missed_at DESC)
  WHERE missed_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.update_dialer_calls_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_dialer_calls_updated_at ON public.dialer_calls;
CREATE TRIGGER update_dialer_calls_updated_at
  BEFORE UPDATE ON public.dialer_calls
  FOR EACH ROW
  EXECUTE FUNCTION public.update_dialer_calls_updated_at();

ALTER TABLE public.dialer_calls ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workspace members can view dialer calls" ON public.dialer_calls;
CREATE POLICY "workspace members can view dialer calls"
  ON public.dialer_calls
  FOR SELECT
  TO authenticated
  USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "workspace members can insert dialer calls" ON public.dialer_calls;
CREATE POLICY "workspace members can insert dialer calls"
  ON public.dialer_calls
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "workspace members can update dialer calls" ON public.dialer_calls;
CREATE POLICY "workspace members can update dialer calls"
  ON public.dialer_calls
  FOR UPDATE
  TO authenticated
  USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));

GRANT SELECT, INSERT, UPDATE ON public.dialer_calls TO authenticated;

COMMENT ON TABLE public.dialer_calls IS 'Inbound and outbound Telnyx call events linked to workspaces and contacts. Used by Inbox for missed calls.';

COMMIT;

NOTIFY pgrst, 'reload schema';
