-- Migration: Create address_statuses table
-- This table stores visit/door status for campaign addresses, keyed by address_id + campaign_id
-- Supports the architecture: Supabase = logical state, Mapbox = geometry + coloring
-- Table has id UUID PRIMARY KEY; iOS client supports address_id as fallback for id when decoding.

-- Drop existing view if it exists
DROP VIEW IF EXISTS public.address_statuses CASCADE;

-- Create address_statuses table
CREATE TABLE IF NOT EXISTS public.address_statuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'none' CHECK (status IN (
        'none',
        'no_answer',
        'delivered',
        'talked',
        'appointment',
        'do_not_knock',
        'future_seller',
        'hot_lead'
    )),
    last_visited_at TIMESTAMPTZ,
    notes TEXT,
    visit_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint: one status per address per campaign
    CONSTRAINT unique_address_campaign_status UNIQUE (address_id, campaign_id)
);

-- Create indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_address_statuses_address_id 
    ON public.address_statuses(address_id);

CREATE INDEX IF NOT EXISTS idx_address_statuses_campaign_id 
    ON public.address_statuses(campaign_id);

CREATE INDEX IF NOT EXISTS idx_address_statuses_status 
    ON public.address_statuses(status);

CREATE INDEX IF NOT EXISTS idx_address_statuses_campaign_status 
    ON public.address_statuses(campaign_id, status);

CREATE INDEX IF NOT EXISTS idx_address_statuses_last_visited 
    ON public.address_statuses(last_visited_at DESC) WHERE last_visited_at IS NOT NULL;

-- Enable Row Level Security
ALTER TABLE public.address_statuses ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access statuses for campaigns they own
CREATE POLICY "Users can view statuses for their own campaigns"
    ON public.address_statuses
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = address_statuses.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert statuses for their own campaigns"
    ON public.address_statuses
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = address_statuses.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update statuses for their own campaigns"
    ON public.address_statuses
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = address_statuses.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete statuses for their own campaigns"
    ON public.address_statuses
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = address_statuses.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_address_statuses_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_address_statuses_updated_at
    BEFORE UPDATE ON public.address_statuses
    FOR EACH ROW
    EXECUTE FUNCTION update_address_statuses_updated_at();

-- Add comments
COMMENT ON TABLE public.address_statuses IS 'Stores visit/door status for campaign addresses. Keyed by address_id + campaign_id. Drives Mapbox building colors via feature-state.';
COMMENT ON COLUMN public.address_statuses.address_id IS 'Foreign key to campaign_addresses.id - the stable key linking Supabase state to Mapbox features';
COMMENT ON COLUMN public.address_statuses.campaign_id IS 'Foreign key to campaigns.id - allows same address to have different statuses in different campaigns';
COMMENT ON COLUMN public.address_statuses.status IS 'Visit/door status enum: none, no_answer, delivered, talked, appointment, do_not_knock, future_seller, hot_lead';
COMMENT ON COLUMN public.address_statuses.last_visited_at IS 'Timestamp of most recent visit';
COMMENT ON COLUMN public.address_statuses.notes IS 'Optional notes about the visit/status';
COMMENT ON COLUMN public.address_statuses.visit_count IS 'Number of times this address has been visited';

