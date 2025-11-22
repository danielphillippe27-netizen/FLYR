-- Migration: Add slug column to qr_codes table
-- Created: 2025-01-28
-- Purpose: Add unique slug column for QR code URL routing (https://flyrpro.app/q/<slug>)

-- Add slug column to qr_codes table
ALTER TABLE public.qr_codes 
ADD COLUMN IF NOT EXISTS slug TEXT;

-- Create unique index on slug (allows NULL values)
CREATE UNIQUE INDEX IF NOT EXISTS idx_qr_codes_slug_unique 
ON public.qr_codes(slug) 
WHERE slug IS NOT NULL;

-- Create index for slug lookups
CREATE INDEX IF NOT EXISTS idx_qr_codes_slug 
ON public.qr_codes(slug) 
WHERE slug IS NOT NULL;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.qr_codes.slug IS 'Unique URL-friendly identifier for QR code routing: https://flyrpro.app/q/<slug>';


