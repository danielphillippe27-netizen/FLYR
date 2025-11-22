-- Migration: Add default_website to user_settings table
-- Created: 2025-01-24
-- Purpose: Store user's default website URL for direct_link QR type

-- Add default_website column to user_settings table
ALTER TABLE public.user_settings
ADD COLUMN IF NOT EXISTS default_website TEXT;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.user_settings.default_website IS 'Default website URL for direct_link QR type. Falls back to https://flyr.app if not set.';



