-- =====================================================
-- CRM connections (status only; secrets in crm_connection_secrets)
-- FUB and other API-key CRMs: backend stores encrypted key, app reads status.
-- =====================================================

CREATE TABLE IF NOT EXISTS public.crm_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('fub', 'kvcore', 'hubspot', 'monday', 'zapier')),
    status TEXT NOT NULL DEFAULT 'disconnected' CHECK (status IN ('connected', 'disconnected', 'error')),
    connected_at TIMESTAMPTZ,
    last_sync_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    error_reason TEXT,
    UNIQUE(user_id, provider)
);

CREATE INDEX IF NOT EXISTS idx_crm_connections_user_id ON public.crm_connections(user_id);
CREATE INDEX IF NOT EXISTS idx_crm_connections_user_provider ON public.crm_connections(user_id, provider);

ALTER TABLE public.crm_connections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_connections_select_own" ON public.crm_connections;
CREATE POLICY "crm_connections_select_own"
    ON public.crm_connections FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_connections_insert_own" ON public.crm_connections;
CREATE POLICY "crm_connections_insert_own"
    ON public.crm_connections FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_connections_update_own" ON public.crm_connections;
CREATE POLICY "crm_connections_update_own"
    ON public.crm_connections FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "crm_connections_delete_own" ON public.crm_connections;
CREATE POLICY "crm_connections_delete_own"
    ON public.crm_connections FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_crm_connections_updated_at ON public.crm_connections;
CREATE TRIGGER update_crm_connections_updated_at
    BEFORE UPDATE ON public.crm_connections
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_connections TO authenticated;

-- =====================================================
-- Secrets table (service role only; app never reads)
-- UNIQUE(connection_id) for safe upsert from backend.
-- =====================================================

CREATE TABLE IF NOT EXISTS public.crm_connection_secrets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES public.crm_connections(id) ON DELETE CASCADE,
    encrypted_api_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(connection_id)
);

CREATE INDEX IF NOT EXISTS idx_crm_connection_secrets_connection_id ON public.crm_connection_secrets(connection_id);

ALTER TABLE public.crm_connection_secrets ENABLE ROW LEVEL SECURITY;

-- No policies for anon/authenticated: deny all. Service role only for backend writes.
-- (Do not create SELECT/INSERT/UPDATE/DELETE for authenticated/anon.)

GRANT ALL ON public.crm_connection_secrets TO service_role;

COMMENT ON TABLE public.crm_connections IS 'CRM connection status per user; encrypted keys in crm_connection_secrets (service role only).';
COMMENT ON TABLE public.crm_connection_secrets IS 'Encrypted API keys for CRM connections; backend only.';

NOTIFY pgrst, 'reload schema';
