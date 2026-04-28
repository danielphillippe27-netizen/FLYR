-- Migration: Add flyers_delivered to session_events
-- Created: 2025-11-22
-- Purpose: Track number of flyers delivered per event for flyer drop sessions

-- ============================================================================
-- Add flyers_delivered column to session_events table
-- ============================================================================

ALTER TABLE public.session_events
ADD COLUMN IF NOT EXISTS flyers_delivered INTEGER;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.session_events.flyers_delivered IS 'Number of flyers delivered at this address/event (for flyer drop sessions)';

