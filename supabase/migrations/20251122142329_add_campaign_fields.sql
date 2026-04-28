-- Migration: Add total_homes and default_map_style to campaigns table
-- Created: 2025-11-22
-- Purpose: Store total homes count and default map style for campaigns

-- ============================================================================
-- Add total_homes column to campaigns table
-- ============================================================================

ALTER TABLE public.campaigns
ADD COLUMN IF NOT EXISTS total_homes INTEGER;

-- ============================================================================
-- Add default_map_style column to campaigns table
-- ============================================================================

ALTER TABLE public.campaigns
ADD COLUMN IF NOT EXISTS default_map_style TEXT DEFAULT 'clean';

-- ============================================================================
-- Add CHECK constraint for valid map style values
-- ============================================================================

ALTER TABLE public.campaigns
ADD CONSTRAINT campaigns_default_map_style_check 
CHECK (default_map_style IS NULL OR default_map_style IN ('standard', 'dark', 'light', 'clean', 'satellite'));

-- ============================================================================
-- Update existing campaigns: set total_homes based on address count
-- ============================================================================

-- This would require a function or manual update, but for now we'll leave it
-- as nullable. The app can compute it from campaign_addresses count.

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON COLUMN public.campaigns.total_homes IS 'Total number of homes/addresses in this campaign (can be computed from campaign_addresses)';
COMMENT ON COLUMN public.campaigns.default_map_style IS 'Default map style for sessions in this campaign: standard, dark, light, clean, or satellite';

