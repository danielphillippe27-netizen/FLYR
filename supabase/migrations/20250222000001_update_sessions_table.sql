-- Migration: Update sessions table
-- Created: 2025-02-22
-- Purpose: Add campaign_id, doors_hit, conversations, and summary_png_url columns

-- ============================================================================
-- Add new columns to sessions table
-- ============================================================================

-- Add campaign_id column (nullable - sessions can exist without campaigns)
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL;

-- Add doors_hit column (count of unique addresses interacted with)
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS doors_hit INTEGER NOT NULL DEFAULT 0;

-- Add conversations column (count of conversations during session)
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS conversations INTEGER NOT NULL DEFAULT 0;

-- Add summary_png_url column (URL to PNG export in Supabase Storage)
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS summary_png_url TEXT;

-- ============================================================================
-- Create indexes for new columns
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sessions_campaign_id ON public.sessions(campaign_id);
CREATE INDEX IF NOT EXISTS idx_sessions_doors_hit ON public.sessions(doors_hit DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_conversations ON public.sessions(conversations DESC);

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.sessions.campaign_id IS 'Foreign key to campaigns table - session can be associated with a campaign';
COMMENT ON COLUMN public.sessions.doors_hit IS 'Number of unique addresses interacted with during this session';
COMMENT ON COLUMN public.sessions.conversations IS 'Number of conversations logged during this session';
COMMENT ON COLUMN public.sessions.summary_png_url IS 'Public URL to session summary PNG in Supabase Storage';









