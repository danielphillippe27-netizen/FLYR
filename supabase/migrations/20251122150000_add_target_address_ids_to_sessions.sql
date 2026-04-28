-- Migration: Add target_address_ids to sessions table
-- Created: 2025-11-22
-- Purpose: Store array of target address IDs for campaign-specific sessions

-- ============================================================================
-- Add target_address_ids column to sessions table
-- ============================================================================

ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS target_address_ids UUID[];

-- ============================================================================
-- Create index for query performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sessions_target_address_ids 
ON public.sessions USING GIN (target_address_ids);

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.sessions.target_address_ids IS 'Array of target address UUIDs for this session (subset of campaign addresses to focus on)';









