-- Migration: Create session_events table
-- Created: 2025-02-22
-- Purpose: Store address interaction events during sessions (taps, conversations, notes, etc.)

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- session_events table
-- Stores individual address interactions during a session
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.session_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL DEFAULT 'address_tap' CHECK (event_type IN ('address_tap', 'conversation', 'flyer_left')),
    conversation_type TEXT CHECK (conversation_type IN (
        'none',
        'no_answer',
        'delivered',
        'talked',
        'appointment',
        'do_not_knock',
        'future_seller',
        'hot_lead'
    )),
    notes TEXT,
    outcome TEXT CHECK (outcome IN (
        'none',
        'no_answer',
        'delivered',
        'talked',
        'appointment',
        'do_not_knock',
        'future_seller',
        'hot_lead'
    )),
    left_flyer BOOLEAN NOT NULL DEFAULT false,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for session_events
CREATE INDEX IF NOT EXISTS idx_session_events_session_id ON public.session_events(session_id);
CREATE INDEX IF NOT EXISTS idx_session_events_address_id ON public.session_events(address_id);
CREATE INDEX IF NOT EXISTS idx_session_events_timestamp ON public.session_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_session_events_event_type ON public.session_events(event_type);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.session_events ENABLE ROW LEVEL SECURITY;

-- Users can read events for their own sessions
DROP POLICY IF EXISTS "Users can read events for their own sessions" ON public.session_events;
CREATE POLICY "Users can read events for their own sessions"
    ON public.session_events
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE sessions.id = session_events.session_id
            AND sessions.user_id = auth.uid()
        )
    );

-- Users can insert events for their own sessions
DROP POLICY IF EXISTS "Users can insert events for their own sessions" ON public.session_events;
CREATE POLICY "Users can insert events for their own sessions"
    ON public.session_events
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE sessions.id = session_events.session_id
            AND sessions.user_id = auth.uid()
        )
    );

-- Users can update events for their own sessions
DROP POLICY IF EXISTS "Users can update events for their own sessions" ON public.session_events;
CREATE POLICY "Users can update events for their own sessions"
    ON public.session_events
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE sessions.id = session_events.session_id
            AND sessions.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE sessions.id = session_events.session_id
            AND sessions.user_id = auth.uid()
        )
    );

-- Users can delete events for their own sessions
DROP POLICY IF EXISTS "Users can delete events for their own sessions" ON public.session_events;
CREATE POLICY "Users can delete events for their own sessions"
    ON public.session_events
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.sessions
            WHERE sessions.id = session_events.session_id
            AND sessions.user_id = auth.uid()
        )
    );

-- Comments
COMMENT ON TABLE public.session_events IS 'Stores address interaction events during sessions';
COMMENT ON COLUMN public.session_events.session_id IS 'Foreign key to sessions table';
COMMENT ON COLUMN public.session_events.address_id IS 'Foreign key to campaign_addresses table';
COMMENT ON COLUMN public.session_events.event_type IS 'Type of event: address_tap, conversation, flyer_left';
COMMENT ON COLUMN public.session_events.conversation_type IS 'Type of conversation using AddressStatus enum values';
COMMENT ON COLUMN public.session_events.outcome IS 'Outcome of the interaction using AddressStatus enum values';
COMMENT ON COLUMN public.session_events.left_flyer IS 'Whether a flyer was left at this address';









