-- Migration: Add batch_id to qr_codes table
-- Created: 2025-01-24
-- Purpose: Link QR codes to batches for proper grouping and management

-- Add batch_id column to qr_codes table
ALTER TABLE public.qr_codes 
ADD COLUMN IF NOT EXISTS batch_id UUID REFERENCES public.batches(id) ON DELETE SET NULL;

-- Create index for batch_id lookups
CREATE INDEX IF NOT EXISTS idx_qr_codes_batch_id ON public.qr_codes(batch_id) WHERE batch_id IS NOT NULL;

-- Update unique constraints to allow batch grouping
-- Note: The existing unique indexes on address_id, campaign_id, and farm_id remain
-- QR codes can now be grouped by batch_id without violating uniqueness

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.qr_codes.batch_id IS 'Foreign key to batches table for grouping QR codes into batches';



