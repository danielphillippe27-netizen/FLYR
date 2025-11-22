-- Migration: Add metadata column to campaign_landing_pages table
-- Created: 2025-01-30
-- Purpose: Store designer theme/configuration metadata as JSONB for Linktree-style mini-designer

-- Add metadata column
ALTER TABLE public.campaign_landing_pages
    ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Add index for metadata queries (GIN index for JSONB)
CREATE INDEX IF NOT EXISTS idx_campaign_landing_pages_metadata 
    ON public.campaign_landing_pages USING GIN (metadata);

-- Add comment
COMMENT ON COLUMN public.campaign_landing_pages.metadata IS 'JSONB metadata storing designer theme configuration: themeStyle, wallpaperStyle, fonts, buttons, colors, hero settings';


