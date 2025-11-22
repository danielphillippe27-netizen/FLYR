-- Migration: Create farm_touches table
-- Created: 2025-01-26
-- Purpose: Store planned and executed touches for farms

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- farm_touches table
-- Stores individual touches (flyers, door knocks, events, etc.) for farms
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.farm_touches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID NOT NULL REFERENCES public.farms(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('flyer', 'door_knock', 'event', 'newsletter', 'ad', 'custom')),
    title TEXT NOT NULL,
    notes TEXT,
    order_index INTEGER,
    completed BOOLEAN DEFAULT false,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    batch_id UUID REFERENCES public.batches(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for farm_touches
CREATE INDEX IF NOT EXISTS idx_farm_touches_farm_id 
    ON public.farm_touches(farm_id);

CREATE INDEX IF NOT EXISTS idx_farm_touches_date 
    ON public.farm_touches(date);

CREATE INDEX IF NOT EXISTS idx_farm_touches_completed 
    ON public.farm_touches(completed);

CREATE INDEX IF NOT EXISTS idx_farm_touches_campaign_id 
    ON public.farm_touches(campaign_id) WHERE campaign_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_farm_touches_batch_id 
    ON public.farm_touches(batch_id) WHERE batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_farm_touches_farm_date 
    ON public.farm_touches(farm_id, date);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.farm_touches ENABLE ROW LEVEL SECURITY;

-- Users can only read/write touches for their own farms
CREATE POLICY "Users can read their own farm touches"
    ON public.farm_touches
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_touches.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert their own farm touches"
    ON public.farm_touches
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_touches.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update their own farm touches"
    ON public.farm_touches
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_touches.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete their own farm touches"
    ON public.farm_touches
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.farms
            WHERE farms.id = farm_touches.farm_id
            AND farms.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.farm_touches IS 'Individual touches (flyers, door knocks, events, etc.) planned and executed for farms';
COMMENT ON COLUMN public.farm_touches.type IS 'Type of touch: flyer, door_knock, event, newsletter, ad, custom';
COMMENT ON COLUMN public.farm_touches.order_index IS 'Order within the same date for sorting';
COMMENT ON COLUMN public.farm_touches.campaign_id IS 'Optional link to a campaign for this touch';
COMMENT ON COLUMN public.farm_touches.batch_id IS 'Optional link to a batch for this touch';



