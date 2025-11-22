-- Migration: Create qr_scan_events table
-- Created: 2025-11-16
-- Purpose: Track QR code scan events for A/B testing and analytics

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- qr_scan_events table
-- Tracks QR code scan events with A/B test support
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.qr_scan_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID REFERENCES public.experiments(id) ON DELETE SET NULL,
    variant_id UUID REFERENCES public.experiment_variants(id) ON DELETE SET NULL,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    landing_page_id UUID REFERENCES public.landing_pages(id) ON DELETE SET NULL,
    device_type TEXT,
    city TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for qr_scan_events
CREATE INDEX IF NOT EXISTS idx_qr_scan_events_experiment_id ON public.qr_scan_events(experiment_id) WHERE experiment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_scan_events_variant_id ON public.qr_scan_events(variant_id) WHERE variant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_scan_events_campaign_id ON public.qr_scan_events(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_scan_events_landing_page_id ON public.qr_scan_events(landing_page_id) WHERE landing_page_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_qr_scan_events_created_at ON public.qr_scan_events(created_at DESC);

-- Composite index for experiment analytics queries
CREATE INDEX IF NOT EXISTS idx_qr_scan_events_experiment_variant ON public.qr_scan_events(experiment_id, variant_id) WHERE experiment_id IS NOT NULL AND variant_id IS NOT NULL;

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.qr_scan_events ENABLE ROW LEVEL SECURITY;

-- Anyone can insert scan events (public tracking)
CREATE POLICY "Anyone can insert QR scan events"
    ON public.qr_scan_events
    FOR INSERT
    WITH CHECK (true);

-- Users can read scan events for their own campaigns/experiments
CREATE POLICY "Users can read scan events for their campaigns"
    ON public.qr_scan_events
    FOR SELECT
    USING (
        -- Allow if campaign belongs to user
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = qr_scan_events.campaign_id
            AND c.owner_id = auth.uid()
        ))
        OR
        -- Allow if experiment belongs to user
        (experiment_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.experiments e
            JOIN public.campaigns c ON c.id = e.campaign_id
            WHERE e.id = qr_scan_events.experiment_id
            AND c.owner_id = auth.uid()
        ))
        OR
        -- Allow if landing page belongs to user
        (landing_page_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.landing_pages lp
            WHERE lp.id = qr_scan_events.landing_page_id
            AND lp.user_id = auth.uid()
        ))
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.qr_scan_events IS 'Tracks QR code scan events for A/B testing and analytics';
COMMENT ON COLUMN public.qr_scan_events.experiment_id IS 'Optional: Links to A/B test experiment';
COMMENT ON COLUMN public.qr_scan_events.variant_id IS 'Optional: Links to specific variant (A or B)';
COMMENT ON COLUMN public.qr_scan_events.city IS 'Generalized city location (privacy-friendly)';

