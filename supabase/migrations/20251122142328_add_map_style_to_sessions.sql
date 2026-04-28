-- Migration: Add map_style column to sessions table
-- Created: 2025-11-22
-- Purpose: Store the map style selected for each session

-- ============================================================================
-- Add map_style column to sessions table
-- ============================================================================

ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS map_style TEXT;

-- ============================================================================
-- Add CHECK constraint for valid map style values
-- ============================================================================

ALTER TABLE public.sessions
ADD CONSTRAINT sessions_map_style_check 
CHECK (map_style IS NULL OR map_style IN ('standard', 'dark', 'light', 'clean', 'satellite'));

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.sessions.map_style IS 'Map style used during this session: standard, dark, light, clean, or satellite';

