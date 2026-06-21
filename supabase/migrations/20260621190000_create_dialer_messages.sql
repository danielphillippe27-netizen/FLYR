-- Telnyx-backed SMS/MMS log for iOS and web salesperson texting.

BEGIN;

CREATE TABLE IF NOT EXISTS public.dialer_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  sender_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  provider text NOT NULL DEFAULT 'telnyx',
  provider_message_id text,
  last_provider_event_id text,
  direction text NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  from_number_e164 text NOT NULL,
  to_number_e164 text NOT NULL,
  body text NOT NULL DEFAULT '',
  message_type text NOT NULL DEFAULT 'SMS',
  status text NOT NULL DEFAULT 'queued',
  media jsonb NOT NULL DEFAULT '[]'::jsonb,
  error jsonb,
  raw_payload jsonb,
  sent_at timestamptz,
  received_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_dialer_messages_provider_message_id
  ON public.dialer_messages(provider, provider_message_id)
;

CREATE INDEX IF NOT EXISTS idx_dialer_messages_workspace_created
  ON public.dialer_messages(workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dialer_messages_contact_created
  ON public.dialer_messages(contact_id, created_at DESC)
  WHERE contact_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dialer_messages_numbers_created
  ON public.dialer_messages(workspace_id, from_number_e164, to_number_e164, created_at DESC);

CREATE OR REPLACE FUNCTION public.update_dialer_messages_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_dialer_messages_updated_at ON public.dialer_messages;
CREATE TRIGGER update_dialer_messages_updated_at
  BEFORE UPDATE ON public.dialer_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_dialer_messages_updated_at();

ALTER TABLE public.dialer_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workspace members can view dialer messages" ON public.dialer_messages;
CREATE POLICY "workspace members can view dialer messages"
  ON public.dialer_messages
  FOR SELECT
  TO authenticated
  USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "workspace members can insert outbound dialer messages" ON public.dialer_messages;
CREATE POLICY "workspace members can insert outbound dialer messages"
  ON public.dialer_messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    direction = 'outbound'
    AND sender_user_id = auth.uid()
    AND public.is_workspace_member(workspace_id)
  );

DROP POLICY IF EXISTS "workspace members can update own outbound dialer messages" ON public.dialer_messages;
CREATE POLICY "workspace members can update own outbound dialer messages"
  ON public.dialer_messages
  FOR UPDATE
  TO authenticated
  USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));

GRANT SELECT, INSERT, UPDATE ON public.dialer_messages TO authenticated;

COMMENT ON TABLE public.dialer_messages IS 'Outbound and inbound Telnyx SMS/MMS events linked to workspaces and contacts.';

COMMIT;

NOTIFY pgrst, 'reload schema';
