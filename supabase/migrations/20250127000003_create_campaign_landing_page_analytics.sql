-- Migration: Create campaign_landing_page_analytics table
-- Created: 2025-01-27
-- Purpose: Track analytics for campaign landing pages (views, unique views, CTA clicks)

-- Create campaign_landing_page_analytics table
CREATE TABLE IF NOT EXISTS public.campaign_landing_page_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    landing_page_id UUID NOT NULL REFERENCES public.campaign_landing_pages(id) ON DELETE CASCADE,
    views INT NOT NULL DEFAULT 0,
    unique_views INT NOT NULL DEFAULT 0,
    cta_clicks INT NOT NULL DEFAULT 0,
    timestamp_bucket DATE NOT NULL DEFAULT CURRENT_DATE,
    
    -- One row per landing page per day
    CONSTRAINT unique_landing_page_date UNIQUE (landing_page_id, timestamp_bucket)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_campaign_landing_page_analytics_landing_page_id ON public.campaign_landing_page_analytics(landing_page_id);
CREATE INDEX IF NOT EXISTS idx_campaign_landing_page_analytics_timestamp ON public.campaign_landing_page_analytics(timestamp_bucket DESC);
CREATE INDEX IF NOT EXISTS idx_campaign_landing_page_analytics_landing_page_timestamp ON public.campaign_landing_page_analytics(landing_page_id, timestamp_bucket DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

ALTER TABLE public.campaign_landing_page_analytics ENABLE ROW LEVEL SECURITY;

-- Users can read analytics for landing pages they own
CREATE POLICY "Users can read their own landing page analytics"
    ON public.campaign_landing_page_analytics
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaign_landing_pages clp
            JOIN public.campaigns c ON c.id = clp.campaign_id
            WHERE clp.id = campaign_landing_page_analytics.landing_page_id
            AND c.owner_id = auth.uid()
        )
    );

-- Public can insert analytics (for tracking views/clicks)
CREATE POLICY "Public can insert landing page analytics"
    ON public.campaign_landing_page_analytics
    FOR INSERT
    WITH CHECK (true);

-- Users can update analytics for landing pages they own
CREATE POLICY "Users can update their own landing page analytics"
    ON public.campaign_landing_page_analytics
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaign_landing_pages clp
            JOIN public.campaigns c ON c.id = clp.campaign_id
            WHERE clp.id = campaign_landing_page_analytics.landing_page_id
            AND c.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.campaign_landing_page_analytics IS 'Analytics tracking for campaign landing pages';
COMMENT ON COLUMN public.campaign_landing_page_analytics.timestamp_bucket IS 'Date bucket for aggregating analytics (one row per day per landing page)';



