-- =====================================================
-- Field Leads table (session-captured leads, optional CRM sync)
-- Phase 1: One-way FLYR → CRM; CSV export; webhook.
-- =====================================================

CREATE TABLE IF NOT EXISTS public.field_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    address TEXT NOT NULL,
    name TEXT,
    phone TEXT,
    status TEXT NOT NULL DEFAULT 'not_home' CHECK (status IN ('not_home', 'interested', 'qr_scanned', 'no_answer')),
    notes TEXT,
    qr_code TEXT,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    session_id UUID REFERENCES public.sessions(id) ON DELETE SET NULL,
    external_crm_id TEXT,
    last_synced_at TIMESTAMPTZ,
    sync_status TEXT CHECK (sync_status IS NULL OR sync_status IN ('pending', 'synced', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_field_leads_user_id ON public.field_leads(user_id);
CREATE INDEX IF NOT EXISTS idx_field_leads_campaign_id ON public.field_leads(campaign_id);
CREATE INDEX IF NOT EXISTS idx_field_leads_session_id ON public.field_leads(session_id);
CREATE INDEX IF NOT EXISTS idx_field_leads_created_at ON public.field_leads(created_at DESC);

-- RLS
ALTER TABLE public.field_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "field_leads_select_own" ON public.field_leads;
CREATE POLICY "field_leads_select_own"
    ON public.field_leads FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "field_leads_insert_own" ON public.field_leads;
CREATE POLICY "field_leads_insert_own"
    ON public.field_leads FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "field_leads_update_own" ON public.field_leads;
CREATE POLICY "field_leads_update_own"
    ON public.field_leads FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "field_leads_delete_own" ON public.field_leads;
CREATE POLICY "field_leads_delete_own"
    ON public.field_leads FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- updated_at trigger (reuse app trigger fn if exists)
CREATE OR REPLACE FUNCTION update_field_leads_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_field_leads_updated_at ON public.field_leads;
CREATE TRIGGER update_field_leads_updated_at
    BEFORE UPDATE ON public.field_leads
    FOR EACH ROW
    EXECUTE FUNCTION update_field_leads_updated_at();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.field_leads TO authenticated;

COMMENT ON TABLE public.field_leads IS 'Field-captured leads from door sessions; optional sync to external CRM.';

NOTIFY pgrst, 'reload schema';
