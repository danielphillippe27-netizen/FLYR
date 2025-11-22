-- Migration: Create farm_phases table
-- Created: 2025-01-26
-- Purpose: Store phases (Awareness, Relationship Building, Lead Harvesting, Conversion) for farms

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- farm_phases table
-- Stores phases for farms with results and metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.farm_phases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    phase_name TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    results JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for farm_phases
CREATE INDEX IF NOT EXISTS idx_farm_phases_farm_id 
    ON public.farm_phases(farm_id);

CREATE INDEX IF NOT EXISTS idx_farm_phases_start_date 
    ON public.farm_phases(start_date);

CREATE INDEX IF NOT EXISTS idx_farm_phases_farm_dates 
    ON public.farm_phases(farm_id, start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_farm_phases_campaign_id 
    ON public.farm_phases(campaign_id) WHERE campaign_id IS NOT NULL;

-- Add check constraint for date validity
ALTER TABLE public.farm_phases
    ADD CONSTRAINT chk_farm_phases_date_range 
    CHECK (end_date >= start_date);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.farm_phases ENABLE ROW LEVEL SECURITY;

-- Users can only read/write phases for their own farms
CREATE POLICY "Users can read their own farm phases"
    ON public.farm_phases
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_phases.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert their own farm phases"
    ON public.farm_phases
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_phases.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update their own farm phases"
    ON public.farm_phases
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_phases.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete their own farm phases"
    ON public.farm_phases
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_phases.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.farm_phases IS 'Phases (Awareness, Relationship Building, Lead Harvesting, Conversion) for farms';
COMMENT ON COLUMN public.farm_phases.phase_name IS 'Name of the phase (e.g., Awareness, Relationship Building, Lead Harvesting, Conversion)';
COMMENT ON COLUMN public.farm_phases.results IS 'JSONB object containing phase results: flyers_delivered, knocks, scans, leads, conversions, spend, roi';



