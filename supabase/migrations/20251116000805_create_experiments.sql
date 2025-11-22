-- Migration: Create experiments table
-- Created: 2025-11-16
-- Purpose: Store A/B test experiment configurations

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- experiments table
-- Stores A/B test experiment configurations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.experiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    landing_page_id UUID NOT NULL REFERENCES public.landing_pages(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'running', 'completed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for experiments
CREATE INDEX IF NOT EXISTS idx_experiments_campaign_id ON public.experiments(campaign_id);
CREATE INDEX IF NOT EXISTS idx_experiments_landing_page_id ON public.experiments(landing_page_id);
CREATE INDEX IF NOT EXISTS idx_experiments_status ON public.experiments(status);
CREATE INDEX IF NOT EXISTS idx_experiments_created_at ON public.experiments(created_at DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.experiments ENABLE ROW LEVEL SECURITY;

-- Users can read experiments for their own campaigns
CREATE POLICY "Users can read experiments for their campaigns"
    ON public.experiments
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = experiments.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can insert experiments for their own campaigns
CREATE POLICY "Users can insert experiments for their campaigns"
    ON public.experiments
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = experiments.campaign_id
            AND c.owner_id = auth.uid()
        )
        AND EXISTS (
            SELECT 1 FROM public.landing_pages lp
            WHERE lp.id = experiments.landing_page_id
            AND lp.user_id = auth.uid()
        )
    );

-- Users can update experiments for their own campaigns
CREATE POLICY "Users can update experiments for their campaigns"
    ON public.experiments
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = experiments.campaign_id
            AND c.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = experiments.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can delete experiments for their own campaigns
CREATE POLICY "Users can delete experiments for their campaigns"
    ON public.experiments
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = experiments.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.experiments IS 'Stores A/B test experiment configurations';
COMMENT ON COLUMN public.experiments.status IS 'Experiment status: draft, running, or completed';

