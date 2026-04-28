-- Migration: Add session type column
-- Created: 2025-11-22
-- Purpose: Add type column to distinguish between door knock and flyer drop sessions

-- ============================================================================
-- Add type column to sessions table
-- ============================================================================

-- Add type column with default value
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'doorKnocks';

-- Add CHECK constraint to ensure valid values
ALTER TABLE public.sessions
ADD CONSTRAINT sessions_type_check 
CHECK (type IN ('doorKnocks', 'flyers'));

-- Update existing rows based on goal_type
-- If goal_type is 'knocks', set type to 'doorKnocks'
-- If goal_type is 'flyers', set type to 'flyers'
-- This will update all existing rows since they all have the default 'doorKnocks' value
UPDATE public.sessions
SET type = CASE 
    WHEN goal_type = 'knocks' THEN 'doorKnocks'
    WHEN goal_type = 'flyers' THEN 'flyers'
    ELSE 'doorKnocks'  -- Default fallback
END;

-- ============================================================================
-- Add flyers_delivered column for flyer drop sessions
-- ============================================================================

ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS flyers_delivered INTEGER;

-- ============================================================================
-- Create index on type column
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sessions_type ON public.sessions(type);

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.sessions.type IS 'Session type: doorKnocks (door-to-door conversations) or flyers (pure flyer drop session)';
COMMENT ON COLUMN public.sessions.flyers_delivered IS 'Total number of flyers delivered during flyer drop sessions';

