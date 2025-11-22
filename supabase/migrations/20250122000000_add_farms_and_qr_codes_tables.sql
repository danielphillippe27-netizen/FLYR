-- Migration: Add Farms and QR Codes tables
-- Created: 2025-01-22
-- Purpose: Support QR code creation for Campaigns and Farms with duplicate prevention

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- farms table
-- Stores farm/territory management data
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.farms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    area_label TEXT,
    frequency_days INTEGER DEFAULT 30,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for farms
CREATE INDEX IF NOT EXISTS idx_farms_owner_id ON public.farms(owner_id);
CREATE INDEX IF NOT EXISTS idx_farms_created_at ON public.farms(created_at DESC);

-- Trigger for updated_at on farms
CREATE TRIGGER update_farms_updated_at
    BEFORE UPDATE ON public.farms
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- qr_codes table
-- Stores QR codes tied to Campaigns or Farms
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.qr_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE CASCADE,
    farm_id UUID REFERENCES public.farms(id) ON DELETE CASCADE,
    qr_url TEXT NOT NULL,
    qr_image TEXT, -- Base64 encoded PNG
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB DEFAULT '{}'::jsonb, -- e.g., address_count, entity_name, device_info
    
    -- Constraint: Either campaign_id OR farm_id must be set (never both)
    CONSTRAINT chk_qr_codes_entity_check CHECK (
        (campaign_id IS NOT NULL AND farm_id IS NULL) OR
        (campaign_id IS NULL AND farm_id IS NOT NULL)
    )
);

-- Indexes for qr_codes
CREATE INDEX IF NOT EXISTS idx_qr_codes_campaign_id ON public.qr_codes(campaign_id);
CREATE INDEX IF NOT EXISTS idx_qr_codes_farm_id ON public.qr_codes(farm_id);
CREATE INDEX IF NOT EXISTS idx_qr_codes_created_at ON public.qr_codes(created_at DESC);

-- Unique indexes to prevent duplicates
-- For campaigns: one QR code per campaign_id + qr_url combination
CREATE UNIQUE INDEX IF NOT EXISTS idx_qr_codes_campaign_url_unique 
    ON public.qr_codes(campaign_id, qr_url) 
    WHERE campaign_id IS NOT NULL;

-- For farms: one QR code per farm_id + qr_url combination
CREATE UNIQUE INDEX IF NOT EXISTS idx_qr_codes_farm_url_unique 
    ON public.qr_codes(farm_id, qr_url) 
    WHERE farm_id IS NOT NULL;

-- Trigger for updated_at on qr_codes
CREATE TRIGGER update_qr_codes_updated_at
    BEFORE UPDATE ON public.qr_codes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.farms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qr_codes ENABLE ROW LEVEL SECURITY;

-- Farms policies
-- Users can only read/write their own farms
CREATE POLICY "Users can read their own farms"
    ON public.farms
    FOR SELECT
    USING (owner_id = auth.uid());

CREATE POLICY "Users can insert their own farms"
    ON public.farms
    FOR INSERT
    WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Users can update their own farms"
    ON public.farms
    FOR UPDATE
    USING (owner_id = auth.uid());

CREATE POLICY "Users can delete their own farms"
    ON public.farms
    FOR DELETE
    USING (owner_id = auth.uid());

-- QR codes policies
-- Users can only read/write QR codes for their own campaigns/farms
CREATE POLICY "Users can read their own QR codes"
    ON public.qr_codes
    FOR SELECT
    USING (
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = qr_codes.campaign_id
            AND c.owner_id = auth.uid()
        )) OR
        (farm_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.farms f
            WHERE f.id = qr_codes.farm_id
            AND f.owner_id = auth.uid()
        ))
    );

CREATE POLICY "Users can insert their own QR codes"
    ON public.qr_codes
    FOR INSERT
    WITH CHECK (
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = qr_codes.campaign_id
            AND c.owner_id = auth.uid()
        )) OR
        (farm_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.farms f
            WHERE f.id = qr_codes.farm_id
            AND f.owner_id = auth.uid()
        ))
    );

CREATE POLICY "Users can update their own QR codes"
    ON public.qr_codes
    FOR UPDATE
    USING (
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = qr_codes.campaign_id
            AND c.owner_id = auth.uid()
        )) OR
        (farm_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.farms f
            WHERE f.id = qr_codes.farm_id
            AND f.owner_id = auth.uid()
        ))
    );

CREATE POLICY "Users can delete their own QR codes"
    ON public.qr_codes
    FOR DELETE
    USING (
        (campaign_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = qr_codes.campaign_id
            AND c.owner_id = auth.uid()
        )) OR
        (farm_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.farms f
            WHERE f.id = qr_codes.farm_id
            AND f.owner_id = auth.uid()
        ))
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.farms IS 'Farm/territory management for recurring campaigns';
COMMENT ON TABLE public.qr_codes IS 'QR codes tied to Campaigns or Farms with duplicate prevention';
COMMENT ON COLUMN public.qr_codes.qr_url IS 'The URL encoded in the QR code (e.g., https://flyr.app/qr/{campaign_id}/{uuid})';
COMMENT ON COLUMN public.qr_codes.qr_image IS 'Base64 encoded PNG image of the QR code';
COMMENT ON COLUMN public.qr_codes.metadata IS 'JSONB metadata (address_count, entity_name, device_info, etc.)';



