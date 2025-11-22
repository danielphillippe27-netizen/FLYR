-- Migration: Enhance landing_pages table
-- Created: 2025-11-16
-- Purpose: Add campaign/address linking, template selection, content fields, and slug support

-- ============================================================================
-- Add new columns to landing_pages table
-- ============================================================================

-- Add campaign and address foreign keys
ALTER TABLE public.landing_pages
    ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES public.campaigns(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS address_id UUID REFERENCES public.campaign_addresses(id) ON DELETE CASCADE;

-- Add template reference
ALTER TABLE public.landing_pages
    ADD COLUMN IF NOT EXISTS template_id UUID REFERENCES public.landing_page_templates(id) ON DELETE SET NULL;

-- Add content fields
ALTER TABLE public.landing_pages
    ADD COLUMN IF NOT EXISTS title TEXT,
    ADD COLUMN IF NOT EXISTS subtitle TEXT,
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS cta_text TEXT,
    ADD COLUMN IF NOT EXISTS cta_url TEXT,
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS video_url TEXT,
    ADD COLUMN IF NOT EXISTS dynamic_data JSONB DEFAULT '{}'::jsonb, -- comps, AVM, stats
    ADD COLUMN IF NOT EXISTS slug TEXT; -- e.g., "/main/5875" or "/camp/{campaignSlug}/{addressSlug}"

-- ============================================================================
-- Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_landing_pages_campaign_id ON public.landing_pages(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_landing_pages_address_id ON public.landing_pages(address_id) WHERE address_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_landing_pages_template_id ON public.landing_pages(template_id) WHERE template_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_landing_pages_slug_unique ON public.landing_pages(slug) WHERE slug IS NOT NULL;

-- Composite index for common queries
CREATE INDEX IF NOT EXISTS idx_landing_pages_campaign_address ON public.landing_pages(campaign_id, address_id) 
    WHERE campaign_id IS NOT NULL AND address_id IS NOT NULL;

-- ============================================================================
-- Update RLS policies to include campaign ownership
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can read their own landing pages" ON public.landing_pages;
DROP POLICY IF EXISTS "Users can insert their own landing pages" ON public.landing_pages;
DROP POLICY IF EXISTS "Users can update their own landing pages" ON public.landing_pages;
DROP POLICY IF EXISTS "Users can delete their own landing pages" ON public.landing_pages;

-- Users can read landing pages for their campaigns or their own user_id
CREATE POLICY "Users can read their own landing pages"
    ON public.landing_pages
    FOR SELECT
    USING (
        user_id = auth.uid() OR
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        ))
    );

-- Users can insert landing pages for their campaigns
CREATE POLICY "Users can insert their own landing pages"
    ON public.landing_pages
    FOR INSERT
    WITH CHECK (
        user_id = auth.uid() AND
        (campaign_id IS NULL OR EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        ))
    );

-- Users can update landing pages for their campaigns
CREATE POLICY "Users can update their own landing pages"
    ON public.landing_pages
    FOR UPDATE
    USING (
        user_id = auth.uid() OR
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        ))
    )
    WITH CHECK (
        user_id = auth.uid() OR
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        ))
    );

-- Users can delete landing pages for their campaigns
CREATE POLICY "Users can delete their own landing pages"
    ON public.landing_pages
    FOR DELETE
    USING (
        user_id = auth.uid() OR
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = landing_pages.campaign_id
            AND c.owner_id = auth.uid()
        ))
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.landing_pages.campaign_id IS 'Links landing page to a specific campaign';
COMMENT ON COLUMN public.landing_pages.address_id IS 'Links landing page to a specific address within a campaign';
COMMENT ON COLUMN public.landing_pages.template_id IS 'References the template design to use for rendering';
COMMENT ON COLUMN public.landing_pages.slug IS 'URL-friendly identifier: /camp/{campaignSlug}/{addressSlug}';
COMMENT ON COLUMN public.landing_pages.dynamic_data IS 'JSONB data for dynamic content: comps, AVM, stats, etc.';

