CREATE TABLE IF NOT EXISTS public.email_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('icloud')),
  email_address text NOT NULL,
  app_password_encrypted text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  last_uid bigint,
  last_synced_at timestamptz,
  sync_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, user_id, provider)
);

ALTER TABLE public.email_connections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.email_connections FROM anon, authenticated;
CREATE INDEX IF NOT EXISTS email_connections_active_idx
  ON public.email_connections(is_active, updated_at DESC);
