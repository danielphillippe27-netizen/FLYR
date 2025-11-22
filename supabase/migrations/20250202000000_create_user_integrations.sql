-- Migration: Create user_integrations table
-- Created: 2025-02-02
-- Purpose: Store CRM integration connections for users (HubSpot, Monday, FUB, KVCore, Zapier)

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- user_integrations table
-- Stores CRM integration credentials and connection details
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('fub', 'kvcore', 'hubspot', 'monday', 'zapier')),
    access_token TEXT,
    refresh_token TEXT,
    api_key TEXT,
    webhook_url TEXT,
    expires_at BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure only one integration per provider per user
    UNIQUE(user_id, provider)
);

-- Indexes for user_integrations
CREATE INDEX IF NOT EXISTS idx_user_integrations_user_id 
    ON public.user_integrations(user_id);

CREATE INDEX IF NOT EXISTS idx_user_integrations_provider 
    ON public.user_integrations(provider);

CREATE INDEX IF NOT EXISTS idx_user_integrations_user_provider 
    ON public.user_integrations(user_id, provider);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.user_integrations ENABLE ROW LEVEL SECURITY;

-- Users can only read their own integrations
CREATE POLICY "Users can read their own integrations"
    ON public.user_integrations
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Users can insert their own integrations
CREATE POLICY "Users can insert their own integrations"
    ON public.user_integrations
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own integrations
CREATE POLICY "Users can update their own integrations"
    ON public.user_integrations
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own integrations
CREATE POLICY "Users can delete their own integrations"
    ON public.user_integrations
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Service role can update tokens (for OAuth refresh flows)
CREATE POLICY "Service role can update tokens"
    ON public.user_integrations
    FOR UPDATE
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- Triggers
-- ============================================================================

-- Create updated_at trigger function (if not exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_user_integrations_updated_at ON public.user_integrations;
CREATE TRIGGER update_user_integrations_updated_at
    BEFORE UPDATE ON public.user_integrations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Grants
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_integrations TO authenticated;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.user_integrations IS 'CRM integration connections for users (HubSpot, Monday, Follow Up Boss, KVCore, Zapier)';
COMMENT ON COLUMN public.user_integrations.provider IS 'CRM provider: fub, kvcore, hubspot, monday, zapier';
COMMENT ON COLUMN public.user_integrations.access_token IS 'OAuth access token (for HubSpot, Monday)';
COMMENT ON COLUMN public.user_integrations.refresh_token IS 'OAuth refresh token (for HubSpot, Monday)';
COMMENT ON COLUMN public.user_integrations.api_key IS 'API key (for FUB, KVCore)';
COMMENT ON COLUMN public.user_integrations.webhook_url IS 'Webhook URL (for Zapier)';
COMMENT ON COLUMN public.user_integrations.expires_at IS 'Token expiration timestamp (Unix epoch in seconds)';


