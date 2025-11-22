-- Migration: Create conversions table
-- Created: 2025-11-16
-- Purpose: Track conversion events (form submissions, sign-ups, etc.) for A/B tests

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- conversions table
-- Tracks conversion events for A/B testing analytics
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.conversions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID REFERENCES public.experiments(id) ON DELETE SET NULL,
    variant_id UUID REFERENCES public.experiment_variants(id) ON DELETE SET NULL,
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    landing_page_id UUID NOT NULL REFERENCES public.landing_pages(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for conversions
CREATE INDEX IF NOT EXISTS idx_conversions_experiment_id ON public.conversions(experiment_id) WHERE experiment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_conversions_variant_id ON public.conversions(variant_id) WHERE variant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_conversions_campaign_id ON public.conversions(campaign_id);
CREATE INDEX IF NOT EXISTS idx_conversions_landing_page_id ON public.conversions(landing_page_id);
CREATE INDEX IF NOT EXISTS idx_conversions_created_at ON public.conversions(created_at DESC);

-- Composite index for experiment conversion queries
CREATE INDEX IF NOT EXISTS idx_conversions_experiment_variant ON public.conversions(experiment_id, variant_id) WHERE experiment_id IS NOT NULL AND variant_id IS NOT NULL;

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.conversions ENABLE ROW LEVEL SECURITY;

-- Anyone can insert conversions (public tracking)
CREATE POLICY "Anyone can insert conversions"
    ON public.conversions
    FOR INSERT
    WITH CHECK (true);

-- Users can read conversions for their own campaigns/experiments
CREATE POLICY "Users can read conversions for their campaigns"
    ON public.conversions
    FOR SELECT
    USING (
        -- Allow if campaign belongs to user
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = conversions.campaign_id
            AND c.owner_id = auth.uid()
        )
        OR
        -- Allow if experiment belongs to user
        (experiment_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = conversions.experiment_id
            AND c.owner_id = auth.uid()
        ))
        OR
        -- Allow if landing page belongs to user
        EXISTS (
            SELECT 1 FROM public.landing_pages lp
            WHERE lp.id = conversions.landing_page_id
            AND lp.user_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.conversions IS 'Tracks conversion events (form submissions, sign-ups, etc.) for A/B testing analytics';
COMMENT ON COLUMN public.conversions.experiment_id IS 'Optional: Links to A/B test experiment';
COMMENT ON COLUMN public.conversions.variant_id IS 'Optional: Links to specific variant (A or B) that generated the conversion';

