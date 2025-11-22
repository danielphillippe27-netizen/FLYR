-- Migration: Create campaign_landing_pages table
-- Created: 2025-01-27
-- Purpose: Store campaign-level landing pages (one per campaign)

-- Create campaign_landing_pages table
CREATE TABLE IF NOT EXISTS public.campaign_landing_pages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    slug TEXT NOT NULL UNIQUE,
    headline TEXT,
    subheadline TEXT,
    hero_url TEXT,
    cta_type TEXT, -- "book", "home_value", "contact", "custom", etc.
    cta_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure one landing page per campaign
    CONSTRAINT unique_campaign_landing_page UNIQUE (campaign_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_campaign_landing_pages_campaign_id ON public.campaign_landing_pages(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_landing_pages_slug ON public.campaign_landing_pages(slug);

-- Trigger for updated_at
CREATE TRIGGER update_campaign_landing_pages_updated_at
    BEFORE UPDATE ON public.campaign_landing_pages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

ALTER TABLE public.campaign_landing_pages ENABLE ROW LEVEL SECURITY;

-- Users can read landing pages for campaigns they own
CREATE POLICY "Users can read their own campaign landing pages"
    ON public.campaign_landing_pages
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can insert landing pages for campaigns they own
CREATE POLICY "Users can insert their own campaign landing pages"
    ON public.campaign_landing_pages
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can update landing pages for campaigns they own
CREATE POLICY "Users can update their own campaign landing pages"
    ON public.campaign_landing_pages
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can delete landing pages for campaigns they own
CREATE POLICY "Users can delete their own campaign landing pages"
    ON public.campaign_landing_pages
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.campaign_landing_pages IS 'Campaign-level landing pages (one per campaign)';
COMMENT ON COLUMN public.campaign_landing_pages.slug IS 'URL-friendly identifier: used in https://flyr.app/l/<slug>';
COMMENT ON COLUMN public.campaign_landing_pages.cta_type IS 'CTA button type: book, home_value, contact, custom, etc.';
COMMENT ON COLUMN public.campaign_landing_pages.hero_url IS 'URL to hero image stored in Supabase Storage';



