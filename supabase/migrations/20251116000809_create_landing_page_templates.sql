-- Migration: Create landing_page_templates table
-- Created: 2025-11-16
-- Purpose: Store landing page template designs (themes) for the landing page engine

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- landing_page_templates table
-- Stores the design structure (the "theme")
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.landing_page_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL, -- e.g., "Minimal Black", "Real Estate Luxe Card", "Neighborhood Spotlight"
    description TEXT,
    preview_image_url TEXT,
    components JSONB DEFAULT '{}'::jsonb, -- defines layout blocks structure
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for landing_page_templates
CREATE INDEX IF NOT EXISTS idx_landing_page_templates_name ON public.landing_page_templates(name);
CREATE INDEX IF NOT EXISTS idx_landing_page_templates_created_at ON public.landing_page_templates(created_at DESC);

-- Trigger for updated_at on landing_page_templates
CREATE OR REPLACE FUNCTION update_landing_page_templates_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_landing_page_templates_updated_at
    BEFORE UPDATE ON public.landing_page_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_landing_page_templates_updated_at();

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.landing_page_templates ENABLE ROW LEVEL SECURITY;

-- Templates are read-only for all authenticated users (system templates)
CREATE POLICY "Anyone can read landing page templates"
    ON public.landing_page_templates
    FOR SELECT
    USING (true);

-- Only service role can insert/update templates (system managed)
-- Users cannot modify templates directly

-- ============================================================================
-- Insert default templates
-- ============================================================================

-- Template 1: Minimal Black
INSERT INTO public.landing_page_templates (id, name, description, components)
VALUES (
    gen_random_uuid(),
    'Minimal Black',
    'Apple-inspired minimal design with black background, bold headline, and centered CTA',
    '{"layout": "minimal_black", "sections": ["hero_image", "headline", "subheadline", "cta_button", "description", "profile_footer"]}'::jsonb
) ON CONFLICT DO NOTHING;

-- Template 2: Real Estate Luxe Card
INSERT INTO public.landing_page_templates (id, name, description, components)
VALUES (
    gen_random_uuid(),
    'Real Estate Luxe Card',
    'Luxury real estate design with house hero photo, home value CTA card, and market stats',
    '{"layout": "luxe_card", "sections": ["hero_photo", "home_value_cta", "market_stats", "contact_section"]}'::jsonb
) ON CONFLICT DO NOTHING;

-- Template 3: Neighborhood Spotlight
INSERT INTO public.landing_page_templates (id, name, description, components)
VALUES (
    gen_random_uuid(),
    'Neighborhood Spotlight',
    'Community-focused design with local photo, claim offer CTA, and neighborhood content list',
    '{"layout": "spotlight", "sections": ["local_photo", "claim_offer_cta", "description_block", "neighborhood_list"]}'::jsonb
) ON CONFLICT DO NOTHING;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.landing_page_templates IS 'Stores landing page template designs (themes) for the landing page engine';
COMMENT ON COLUMN public.landing_page_templates.components IS 'JSONB structure defining layout blocks and sections for the template';

