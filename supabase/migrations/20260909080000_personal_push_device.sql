BEGIN;
CREATE TABLE IF NOT EXISTS public.user_push_tokens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 token text NOT NULL, platform text NOT NULL DEFAULT 'ios',
 environment text NOT NULL DEFAULT 'production', enabled boolean NOT NULL DEFAULT true,
 last_seen_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,token),
 CHECK (platform='ios'), CHECK (environment IN ('sandbox','production'))
);
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_push_tokens FROM anon,authenticated;
GRANT ALL ON public.user_push_tokens TO service_role;
-- Historical duplicate tokens cannot establish which user is currently signed in.
-- Disable all ambiguous registrations until the device re-registers.
UPDATE public.user_push_tokens p SET enabled=false
WHERE enabled AND EXISTS (SELECT 1 FROM public.user_push_tokens other
 WHERE other.token=p.token AND other.platform=p.platform AND other.environment=p.environment
 AND other.user_id<>p.user_id AND other.enabled);
CREATE UNIQUE INDEX personal_push_device_active_uidx
ON public.user_push_tokens(token,platform,environment) WHERE enabled;
COMMIT;
