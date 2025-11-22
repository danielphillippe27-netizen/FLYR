-- Migration: Add landing_page_id and qr_variant to qr_codes table
-- Created: 2025-01-27
-- Purpose: Link QR codes to campaign landing pages with A/B variant support

-- Add landing_page_id column to qr_codes table
ALTER TABLE public.qr_codes 
ADD COLUMN IF NOT EXISTS landing_page_id UUID REFERENCES public.campaign_landing_pages(id) ON DELETE SET NULL;

-- Add qr_variant column for A/B testing
ALTER TABLE public.qr_codes 
ADD COLUMN IF NOT EXISTS qr_variant TEXT CHECK (qr_variant IS NULL OR qr_variant IN ('A', 'B'));

-- Create index for landing_page_id lookups
CREATE INDEX IF NOT EXISTS idx_qr_codes_landing_page_id ON public.qr_codes(landing_page_id) WHERE landing_page_id IS NOT NULL;

-- Create index for qr_variant lookups
CREATE INDEX IF NOT EXISTS idx_qr_codes_variant ON public.qr_codes(qr_variant) WHERE qr_variant IS NOT NULL;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.qr_codes.landing_page_id IS 'Foreign key to campaign_landing_pages table for linking QR codes to landing pages';
COMMENT ON COLUMN public.qr_codes.qr_variant IS 'A/B test variant: A or B (nullable)';



