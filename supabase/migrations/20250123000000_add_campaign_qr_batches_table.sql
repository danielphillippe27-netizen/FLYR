-- Migration: Add campaign_qr_batches table for export metadata
-- Created: 2025-01-23

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- campaign_qr_batches table
-- Stores metadata about exported QR code batches
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.campaign_qr_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    batch_name TEXT NOT NULL,
    zip_url TEXT,
    pdf_grid_url TEXT,
    pdf_single_url TEXT,
    csv_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure batch names are unique per campaign
    CONSTRAINT unique_campaign_batch_name UNIQUE (campaign_id, batch_name)
);

-- Indexes for campaign_qr_batches
CREATE INDEX IF NOT EXISTS idx_campaign_qr_batches_campaign_id 
    ON public.campaign_qr_batches(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_qr_batches_created_at 
    ON public.campaign_qr_batches(created_at DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.campaign_qr_batches ENABLE ROW LEVEL SECURITY;

-- Users can only view their own batch exports
CREATE POLICY "Users can view own batch exports" 
    ON public.campaign_qr_batches
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_qr_batches.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Users can insert their own batch exports
CREATE POLICY "Users can insert own batch exports" 
    ON public.campaign_qr_batches
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_qr_batches.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Users can update their own batch exports
CREATE POLICY "Users can update own batch exports" 
    ON public.campaign_qr_batches
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_qr_batches.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Users can delete their own batch exports
CREATE POLICY "Users can delete own batch exports" 
    ON public.campaign_qr_batches
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_qr_batches.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

