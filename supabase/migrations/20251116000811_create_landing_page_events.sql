-- Migration: Create landing_page_events table
-- Created: 2025-11-16
-- Purpose: Track QR scan, page view, and CTA click events for landing pages

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- landing_page_events table
-- Tracks QR scan, view, and click events
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.landing_page_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    landing_page_id UUID NOT NULL REFERENCES public.landing_pages(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL, -- 'scan', 'view', 'click'
    device TEXT, -- device type/identifier
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for landing_page_events
CREATE INDEX IF NOT EXISTS idx_landing_page_events_landing_page_id ON public.landing_page_events(landing_page_id);
CREATE INDEX IF NOT EXISTS idx_landing_page_events_event_type ON public.landing_page_events(event_type);
CREATE INDEX IF NOT EXISTS idx_landing_page_events_timestamp ON public.landing_page_events(timestamp DESC);

-- Composite index for analytics queries
CREATE INDEX IF NOT EXISTS idx_landing_page_events_page_type_timestamp ON public.landing_page_events(landing_page_id, event_type, timestamp DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.landing_page_events ENABLE ROW LEVEL SECURITY;

-- Anyone can insert events (public tracking)
CREATE POLICY "Anyone can insert landing page events"
    ON public.landing_page_events
    FOR INSERT
    WITH CHECK (true);

-- Users can read events for their own landing pages
CREATE POLICY "Users can read events for their landing pages"
    ON public.landing_page_events
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.landing_pages lp
            WHERE lp.id = landing_page_events.landing_page_id
            AND (
                lp.user_id = auth.uid() OR
                (lp.campaign_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM public.campaigns c
                    WHERE c.id = lp.campaign_id
                    AND c.owner_id = auth.uid()
                ))
            )
        )
    );

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.landing_page_events IS 'Tracks QR scan, page view, and CTA click events for landing pages';
COMMENT ON COLUMN public.landing_page_events.event_type IS 'Event type: scan (QR scanned), view (page viewed), click (CTA clicked)';
COMMENT ON COLUMN public.landing_page_events.device IS 'Device type or identifier for analytics';

