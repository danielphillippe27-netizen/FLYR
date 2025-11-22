-- Migration: Create landing_pages table
-- Created: 2025-11-16
-- Purpose: Store landing page configurations for QR codes, A/B tests, and future AI landing page generator

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- landing_pages table
-- Stores landing page configurations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.landing_pages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    type TEXT, -- e.g., 'home_value', 'listings', 'appointment', etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for landing_pages
CREATE INDEX IF NOT EXISTS idx_landing_pages_user_id ON public.landing_pages(user_id);
CREATE INDEX IF NOT EXISTS idx_landing_pages_created_at ON public.landing_pages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_landing_pages_type ON public.landing_pages(type) WHERE type IS NOT NULL;

-- Trigger for updated_at on landing_pages
CREATE OR REPLACE FUNCTION update_landing_pages_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_landing_pages_updated_at
    BEFORE UPDATE ON public.landing_pages
    FOR EACH ROW
    EXECUTE FUNCTION update_landing_pages_updated_at();

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.landing_pages ENABLE ROW LEVEL SECURITY;

-- Users can read their own landing pages
CREATE POLICY "Users can read their own landing pages"
    ON public.landing_pages
    FOR SELECT
    USING (user_id = auth.uid());

-- Users can insert their own landing pages
CREATE POLICY "Users can insert their own landing pages"
    ON public.landing_pages
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can update their own landing pages
CREATE POLICY "Users can update their own landing pages"
    ON public.landing_pages
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can delete their own landing pages
CREATE POLICY "Users can delete their own landing pages"
    ON public.landing_pages
    FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.landing_pages IS 'Stores landing page configurations for QR codes, A/B tests, and analytics';
COMMENT ON COLUMN public.landing_pages.type IS 'Landing page type for future automation: home_value, listings, appointment, etc.';

