CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios',
  environment TEXT NOT NULL DEFAULT 'production',
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, token),
  CHECK (platform IN ('ios')),
  CHECK (environment IN ('sandbox', 'production'))
);

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_enabled
  ON public.user_push_tokens(user_id, enabled);

ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can read their own push tokens"
  ON public.user_push_tokens
  FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert their own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can insert their own push tokens"
  ON public.user_push_tokens
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can update their own push tokens"
  ON public.user_push_tokens
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.campaign_ready_notifications (
  campaign_id UUID PRIMARY KEY REFERENCES public.campaigns(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  campaign_name TEXT NOT NULL,
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  device_count INTEGER NOT NULL DEFAULT 0,
  error TEXT
);

CREATE INDEX IF NOT EXISTS idx_campaign_ready_notifications_user_id
  ON public.campaign_ready_notifications(user_id);

ALTER TABLE public.campaign_ready_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own campaign ready notifications" ON public.campaign_ready_notifications;
CREATE POLICY "Users can read their own campaign ready notifications"
  ON public.campaign_ready_notifications
  FOR SELECT
  USING (user_id = auth.uid());

COMMENT ON TABLE public.user_push_tokens IS
'APNs device tokens for campaign-ready and future user notifications.';

COMMENT ON TABLE public.campaign_ready_notifications IS
'Deduplication and audit marker for campaign-ready push notifications.';
