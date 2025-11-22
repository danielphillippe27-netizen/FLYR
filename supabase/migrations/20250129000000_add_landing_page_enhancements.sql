-- Migration: Add title and hero_type to campaign_landing_pages table
-- Created: 2025-01-29
-- Purpose: Enhance landing pages with title field and support for multiple hero media types (image/video/youtube)

-- Add title column
ALTER TABLE public.campaign_landing_pages
    ADD COLUMN IF NOT EXISTS title TEXT;

-- Add hero_type column with constraint
ALTER TABLE public.campaign_landing_pages
    ADD COLUMN IF NOT EXISTS hero_type TEXT;

-- Add check constraint to ensure hero_type is one of the allowed values
ALTER TABLE public.campaign_landing_pages
    ADD CONSTRAINT check_hero_type 
    CHECK (hero_type IS NULL OR hero_type IN ('image', 'video', 'youtube'));

-- Update existing rows: set hero_type to 'image' if hero_url exists
UPDATE public.campaign_landing_pages
SET hero_type = 'image'
WHERE hero_type IS NULL AND hero_url IS NOT NULL;

-- Set default hero_type to 'image' for rows that still have NULL
UPDATE public.campaign_landing_pages
SET hero_type = 'image'
WHERE hero_type IS NULL;

-- Add comments
COMMENT ON COLUMN public.campaign_landing_pages.title IS 'Landing page title displayed above headline';
COMMENT ON COLUMN public.campaign_landing_pages.hero_type IS 'Type of hero media: image, video, or youtube';


