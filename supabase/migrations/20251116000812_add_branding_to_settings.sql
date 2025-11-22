-- Migration: Add branding columns to user_settings
-- Created: 2025-11-16
-- Purpose: Store global branding preferences for landing pages

-- ============================================================================
-- Add branding columns to user_settings table
-- ============================================================================

ALTER TABLE public.user_settings
    ADD COLUMN IF NOT EXISTS brand_color TEXT, -- hex color code
    ADD COLUMN IF NOT EXISTS logo_url TEXT,
    ADD COLUMN IF NOT EXISTS realtor_profile_card JSONB, -- profile card data
    ADD COLUMN IF NOT EXISTS default_cta_color TEXT, -- hex color code
    ADD COLUMN IF NOT EXISTS font_style TEXT, -- font preset name
    ADD COLUMN IF NOT EXISTS default_template_id UUID REFERENCES public.landing_page_templates(id) ON DELETE SET NULL;

-- ============================================================================
-- Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_user_settings_default_template_id ON public.user_settings(default_template_id) 
    WHERE default_template_id IS NOT NULL;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.user_settings.brand_color IS 'Global brand color (hex) applied to all landing pages';
COMMENT ON COLUMN public.user_settings.logo_url IS 'URL to user logo image';
COMMENT ON COLUMN public.user_settings.realtor_profile_card IS 'JSONB data for realtor profile card (name, photo, contact, etc.)';
COMMENT ON COLUMN public.user_settings.default_cta_color IS 'Default CTA button color (hex)';
COMMENT ON COLUMN public.user_settings.font_style IS 'Font style preset (e.g., "system", "serif", "sans-serif")';
COMMENT ON COLUMN public.user_settings.default_template_id IS 'Default template to use when auto-generating landing pages';

