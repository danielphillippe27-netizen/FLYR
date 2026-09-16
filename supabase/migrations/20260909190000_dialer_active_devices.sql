BEGIN;

-- Ephemeral display state. Call history and telecom controls remain in dialer_calls.
CREATE TABLE public.dialer_active_devices (
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL,
  platform text NOT NULL CHECK (platform IN ('ios', 'web')),
  call_snapshot jsonb NOT NULL,
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, user_id, device_id)
);

CREATE INDEX dialer_active_devices_expiry ON public.dialer_active_devices(expires_at);
ALTER TABLE public.dialer_active_devices ENABLE ROW LEVEL SECURITY;
-- Only the authenticated API (service role) accesses presence. No direct client grants.
REVOKE ALL ON public.dialer_active_devices FROM anon, authenticated;
GRANT ALL ON public.dialer_active_devices TO service_role;

COMMIT;
