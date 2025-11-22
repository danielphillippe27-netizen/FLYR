-- Migration: Create building_touches table
-- Created: 2025-02-04
-- Purpose: Store building tap interactions for analytics and user tracking

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- building_touches table
-- Stores individual building tap interactions from the map
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.building_touches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    building_id TEXT NOT NULL,
    source_id TEXT,
    source_layer_id TEXT,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    touched_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for building_touches
CREATE INDEX IF NOT EXISTS idx_building_touches_user_id 
    ON public.building_touches(user_id);

CREATE INDEX IF NOT EXISTS idx_building_touches_building_id 
    ON public.building_touches(building_id);

CREATE INDEX IF NOT EXISTS idx_building_touches_touched_at 
    ON public.building_touches(touched_at DESC);

CREATE INDEX IF NOT EXISTS idx_building_touches_campaign_id 
    ON public.building_touches(campaign_id) WHERE campaign_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_building_touches_user_touched 
    ON public.building_touches(user_id, touched_at DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.building_touches ENABLE ROW LEVEL SECURITY;

-- Users can insert their own building touches
CREATE POLICY "Users can insert their own building touches"
    ON public.building_touches
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can read their own building touches
CREATE POLICY "Users can read their own building touches"
    ON public.building_touches
    FOR SELECT
    USING (auth.uid() = user_id);

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.building_touches IS 'Building tap interactions from the map for analytics and user tracking';
COMMENT ON COLUMN public.building_touches.building_id IS 'Mapbox building ID from the tapped feature';
COMMENT ON COLUMN public.building_touches.source_id IS 'Mapbox source ID (e.g., "composite", "campaign-buildings")';
COMMENT ON COLUMN public.building_touches.source_layer_id IS 'Mapbox source layer ID (e.g., "building", null for GeoJSON sources)';
COMMENT ON COLUMN public.building_touches.campaign_id IS 'Optional link to a campaign if building was tapped in campaign context';

