-- Migration: Create experiment_variants table
-- Created: 2025-11-16
-- Purpose: Store A/B test variant configurations (Variant A and Variant B)

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- experiment_variants table
-- Stores A/B test variant configurations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.experiment_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES public.experiments(id) ON DELETE CASCADE,
    key TEXT NOT NULL CHECK (key IN ('A', 'B')),
    url_slug TEXT NOT NULL UNIQUE,
    qr_code_id UUID REFERENCES public.qr_codes(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Constraint: Each experiment can only have one variant A and one variant B
    UNIQUE(experiment_id, key)
);

-- Indexes for experiment_variants
CREATE INDEX IF NOT EXISTS idx_experiment_variants_experiment_id ON public.experiment_variants(experiment_id);
CREATE INDEX IF NOT EXISTS idx_experiment_variants_url_slug ON public.experiment_variants(url_slug);
CREATE INDEX IF NOT EXISTS idx_experiment_variants_qr_code_id ON public.experiment_variants(qr_code_id) WHERE qr_code_id IS NOT NULL;

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.experiment_variants ENABLE ROW LEVEL SECURITY;

-- Users can read variants for their own experiments
CREATE POLICY "Users can read variants for their experiments"
    ON public.experiment_variants
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = experiment_variants.experiment_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can insert variants for their own experiments
CREATE POLICY "Users can insert variants for their experiments"
    ON public.experiment_variants
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = experiment_variants.experiment_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can update variants for their own experiments
CREATE POLICY "Users can update variants for their experiments"
    ON public.experiment_variants
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = experiment_variants.experiment_id
            AND c.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = experiment_variants.experiment_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can delete variants for their own experiments
CREATE POLICY "Users can delete variants for their experiments"
    ON public.experiment_variants
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = experiment_variants.experiment_id
            AND c.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.experiment_variants IS 'Stores A/B test variant configurations (Variant A and Variant B)';
COMMENT ON COLUMN public.experiment_variants.key IS 'Variant key: A or B';
COMMENT ON COLUMN public.experiment_variants.url_slug IS 'Unique URL slug for routing: https://flyr.app/q/<slug>?variant=A';

