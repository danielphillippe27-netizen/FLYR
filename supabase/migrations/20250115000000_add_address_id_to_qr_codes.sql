-- Migration: Add address_id to qr_codes table
-- Created: 2025-01-15
-- Purpose: Support per-address QR codes with address-specific URLs

-- Add address_id column to qr_codes table
ALTER TABLE public.qr_codes 
ADD COLUMN IF NOT EXISTS address_id UUID REFERENCES public.campaign_addresses(id) ON DELETE CASCADE;

-- Create index for address_id lookups
CREATE INDEX IF NOT EXISTS idx_qr_codes_address_id ON public.qr_codes(address_id);

-- Update unique constraint to allow one QR code per address
-- Remove old unique indexes
DROP INDEX IF EXISTS idx_qr_codes_campaign_url_unique;
DROP INDEX IF EXISTS idx_qr_codes_farm_url_unique;

-- Create new unique index for address-based QR codes
CREATE UNIQUE INDEX IF NOT EXISTS idx_qr_codes_address_id_unique 
    ON public.qr_codes(address_id) 
    WHERE address_id IS NOT NULL;

-- Update constraint to allow address_id OR (campaign_id/farm_id)
-- Drop old constraint
ALTER TABLE public.qr_codes 
DROP CONSTRAINT IF EXISTS chk_qr_codes_entity_check;

-- Add new constraint: Either address_id OR (campaign_id OR farm_id) must be set
ALTER TABLE public.qr_codes 
ADD CONSTRAINT chk_qr_codes_entity_check CHECK (
    (address_id IS NOT NULL AND campaign_id IS NULL AND farm_id IS NULL) OR
    (address_id IS NULL AND campaign_id IS NOT NULL AND farm_id IS NULL) OR
    (address_id IS NULL AND campaign_id IS NULL AND farm_id IS NOT NULL)
);

COMMENT ON COLUMN public.qr_codes.address_id IS 'Foreign key to campaign_addresses for address-specific QR codes';



