-- Migration: Create batches table
-- Created: 2025-01-24
-- Purpose: Store batch configurations for QR code generation with type, landing page, and export format

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- batches table
-- Stores batch configurations for QR code generation
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    qr_type TEXT NOT NULL CHECK (qr_type IN ('landing_page', 'direct_link', 'map', 'custom_url', 'variant')),
    landing_page_id UUID REFERENCES public.landing_pages(id) ON DELETE SET NULL,
    custom_url TEXT,
    export_format TEXT NOT NULL CHECK (export_format IN ('pdf', '3x3_label', 'png', 'canva')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure landing_page_id is set when qr_type is 'landing_page'
    CONSTRAINT chk_landing_page_required CHECK (
        (qr_type = 'landing_page' AND landing_page_id IS NOT NULL) OR
        (qr_type != 'landing_page')
    ),
    
    -- Ensure custom_url is set when qr_type is 'custom_url'
    CONSTRAINT chk_custom_url_required CHECK (
        (qr_type = 'custom_url' AND custom_url IS NOT NULL AND custom_url != '') OR
        (qr_type != 'custom_url')
    ),
    
    -- Future: variant URLs for A/B testing (commented for now)
    -- variant_a_url TEXT,
    -- variant_b_url TEXT
);

-- Indexes for batches
CREATE INDEX IF NOT EXISTS idx_batches_user_id ON public.batches(user_id);
CREATE INDEX IF NOT EXISTS idx_batches_created_at ON public.batches(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_batches_qr_type ON public.batches(qr_type);
CREATE INDEX IF NOT EXISTS idx_batches_landing_page_id ON public.batches(landing_page_id) WHERE landing_page_id IS NOT NULL;

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.batches ENABLE ROW LEVEL SECURITY;

-- Users can read their own batches
CREATE POLICY "Users can read their own batches"
    ON public.batches
    FOR SELECT
    USING (user_id = auth.uid());

-- Users can insert their own batches
CREATE POLICY "Users can insert their own batches"
    ON public.batches
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can update their own batches
CREATE POLICY "Users can update their own batches"
    ON public.batches
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can delete their own batches
CREATE POLICY "Users can delete their own batches"
    ON public.batches
    FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.batches IS 'Stores batch configurations for QR code generation';
COMMENT ON COLUMN public.batches.qr_type IS 'Type of QR code: landing_page, direct_link, map, custom_url, or variant (future)';
COMMENT ON COLUMN public.batches.landing_page_id IS 'Foreign key to landing_pages when qr_type is landing_page';
COMMENT ON COLUMN public.batches.custom_url IS 'Custom URL when qr_type is custom_url';
COMMENT ON COLUMN public.batches.export_format IS 'Export format: pdf, 3x3_label, png, or canva';



