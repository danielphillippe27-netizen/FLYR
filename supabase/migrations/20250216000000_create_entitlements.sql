-- =====================================================
-- User entitlements (subscription plan): free | pro | team
-- Source: apple (IAP), stripe (web), none
-- GET /api/billing/entitlement creates default free row if missing.
-- =====================================================

CREATE TABLE IF NOT EXISTS public.entitlements (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'pro', 'team')),
    is_active BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'none' CHECK (source IN ('apple', 'stripe', 'none')),
    current_period_end TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_entitlements_user_id ON public.entitlements(user_id);

ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "entitlements_select_own" ON public.entitlements;
CREATE POLICY "entitlements_select_own"
    ON public.entitlements FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- Service role (backend) can insert/update for JWT-authenticated users
DROP POLICY IF EXISTS "entitlements_service_all" ON public.entitlements;
CREATE POLICY "entitlements_service_all"
    ON public.entitlements FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

COMMENT ON TABLE public.entitlements IS 'User subscription entitlement; backend creates default free row on first GET.';
