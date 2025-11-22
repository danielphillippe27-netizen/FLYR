-- Migration: Create farm_leads table
-- Created: 2025-01-26
-- Purpose: Store leads generated from farm touches

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- farm_leads table
-- Stores leads generated from farm touches (QR scans, door knocks, etc.)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.farm_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    touch_id UUID REFERENCES public.farm_touches(id) ON DELETE SET NULL,
    lead_source TEXT NOT NULL,
    name TEXT,
    phone TEXT,
    email TEXT,
    address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for farm_leads
CREATE INDEX IF NOT EXISTS idx_farm_leads_farm_id 
    ON public.farm_leads(farm_id);

CREATE INDEX IF NOT EXISTS idx_farm_leads_touch_id 
    ON public.farm_leads(touch_id) WHERE touch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_farm_leads_created_at 
    ON public.farm_leads(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_farm_leads_lead_source 
    ON public.farm_leads(lead_source);

CREATE INDEX IF NOT EXISTS idx_farm_leads_farm_created 
    ON public.farm_leads(farm_id, created_at DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.farm_leads ENABLE ROW LEVEL SECURITY;

-- Users can only read/write leads for their own farms
CREATE POLICY "Users can read their own farm leads"
    ON public.farm_leads
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_leads.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert their own farm leads"
    ON public.farm_leads
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_leads.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update their own farm leads"
    ON public.farm_leads
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_leads.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete their own farm leads"
    ON public.farm_leads
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_leads.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.farm_leads IS 'Leads generated from farm touches (QR scans, door knocks, events, etc.)';
COMMENT ON COLUMN public.farm_leads.lead_source IS 'Source of the lead: qr_scan, door_knock, flyer, event, newsletter, ad, custom';
COMMENT ON COLUMN public.farm_leads.touch_id IS 'Optional link to the farm_touch that generated this lead';



