-- =====================================================
-- Building Tables Migration
-- 
-- Creates the buildings, building_address_links, and 
-- building_stats tables for the iOS Linked Homes feature.
-- This migration supports the GERS ID-based architecture
-- for connecting map buildings to campaign addresses.
-- =====================================================

-- =====================================================
-- 1. Create buildings table
-- =====================================================

CREATE TABLE IF NOT EXISTS public.buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source TEXT NOT NULL DEFAULT 'overture',
    gers_id UUID UNIQUE,  -- Overture GERS ID (Global Entity Reference System)
    geom GEOMETRY(Polygon, 4326) NOT NULL,
    centroid GEOMETRY(Point, 4326) GENERATED ALWAYS AS (ST_Centroid(geom)) STORED,
    height_m NUMERIC,
    height NUMERIC,
    levels INTEGER,
    is_townhome_row BOOLEAN DEFAULT false,
    units_count INTEGER DEFAULT 1,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    latest_status TEXT DEFAULT 'default',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for buildings table
CREATE INDEX IF NOT EXISTS idx_buildings_gers_id ON public.buildings(gers_id) WHERE gers_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_buildings_campaign_id ON public.buildings(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_buildings_geom ON public.buildings USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_buildings_centroid ON public.buildings USING GIST(centroid);
CREATE INDEX IF NOT EXISTS idx_buildings_source ON public.buildings(source);

-- Enable RLS
ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;

-- RLS Policies for buildings
CREATE POLICY "Users can view buildings for their campaigns"
    ON public.buildings
    FOR SELECT
    USING (
        campaign_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = buildings.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert buildings for their campaigns"
    ON public.buildings
    FOR INSERT
    WITH CHECK (
        campaign_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = buildings.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update buildings for their campaigns"
    ON public.buildings
    FOR UPDATE
    USING (
        campaign_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = buildings.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Add comments
COMMENT ON TABLE public.buildings IS 'Building geometries from Overture Maps and other sources. Linked to campaign addresses via building_address_links.';
COMMENT ON COLUMN public.buildings.gers_id IS 'Global Entity Reference System ID from Overture Maps - unique building identifier';
COMMENT ON COLUMN public.buildings.geom IS 'Building footprint polygon (EPSG:4326)';
COMMENT ON COLUMN public.buildings.centroid IS 'Generated centroid point for fast spatial queries';
COMMENT ON COLUMN public.buildings.campaign_id IS 'Optional campaign association for campaign-specific buildings';

-- =====================================================
-- 2. Create building_address_links table
-- =====================================================

CREATE TABLE IF NOT EXISTS public.building_address_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    building_id UUID NOT NULL REFERENCES public.buildings(id) ON DELETE CASCADE,
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    method TEXT,  -- 'COVERS', 'NEAREST', 'MANUAL', 'HASH'
    is_primary BOOLEAN DEFAULT false,
    confidence_score NUMERIC CHECK (confidence_score >= 0 AND confidence_score <= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint: one link per building-address-campaign combo
    CONSTRAINT unique_building_address_campaign UNIQUE (building_id, address_id, campaign_id)
);

-- Create indexes for building_address_links
CREATE INDEX IF NOT EXISTS idx_building_address_links_building ON public.building_address_links(building_id);
CREATE INDEX IF NOT EXISTS idx_building_address_links_address ON public.building_address_links(address_id);
CREATE INDEX IF NOT EXISTS idx_building_address_links_campaign ON public.building_address_links(campaign_id);
CREATE INDEX IF NOT EXISTS idx_building_address_links_primary ON public.building_address_links(is_primary) WHERE is_primary = true;
CREATE INDEX IF NOT EXISTS idx_building_address_links_method ON public.building_address_links(method);

-- Enable RLS
ALTER TABLE public.building_address_links ENABLE ROW LEVEL SECURITY;

-- RLS Policies for building_address_links
CREATE POLICY "Users can view links for their campaigns"
    ON public.building_address_links
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_address_links.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert links for their campaigns"
    ON public.building_address_links
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_address_links.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update links for their campaigns"
    ON public.building_address_links
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_address_links.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete links for their campaigns"
    ON public.building_address_links
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_address_links.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Add comments
COMMENT ON TABLE public.building_address_links IS 'Stable linker between buildings and campaign addresses. Supports multiple linking methods with confidence scores.';
COMMENT ON COLUMN public.building_address_links.method IS 'Linking method: COVERS (building contains address), NEAREST (closest building), MANUAL (user-linked), HASH (MD5 key match)';
COMMENT ON COLUMN public.building_address_links.is_primary IS 'True if this is the primary link for this building in this campaign';
COMMENT ON COLUMN public.building_address_links.confidence_score IS 'Linking confidence (0-1), higher is better';

-- =====================================================
-- 3. Create building_stats table
-- =====================================================

CREATE TABLE IF NOT EXISTS public.building_stats (
    building_id UUID PRIMARY KEY REFERENCES public.buildings(id) ON DELETE CASCADE,
    campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
    gers_id UUID,  -- Denormalized for fast lookup
    status TEXT NOT NULL DEFAULT 'not_visited' CHECK (status IN ('not_visited', 'visited', 'hot')),
    scans_total INTEGER NOT NULL DEFAULT 0 CHECK (scans_total >= 0),
    scans_today INTEGER NOT NULL DEFAULT 0 CHECK (scans_today >= 0),
    last_scan_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for building_stats
CREATE INDEX IF NOT EXISTS idx_building_stats_gers_id ON public.building_stats(gers_id) WHERE gers_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_building_stats_campaign ON public.building_stats(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_building_stats_status ON public.building_stats(status);
CREATE INDEX IF NOT EXISTS idx_building_stats_scans_total ON public.building_stats(scans_total) WHERE scans_total > 0;
CREATE INDEX IF NOT EXISTS idx_building_stats_last_scan ON public.building_stats(last_scan_at DESC) WHERE last_scan_at IS NOT NULL;

-- Enable RLS
ALTER TABLE public.building_stats ENABLE ROW LEVEL SECURITY;

-- RLS Policies for building_stats
CREATE POLICY "Users can view stats for their campaign buildings"
    ON public.building_stats
    FOR SELECT
    USING (
        campaign_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_stats.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert stats for their campaign buildings"
    ON public.building_stats
    FOR INSERT
    WITH CHECK (
        campaign_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_stats.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Users can update stats for their campaign buildings"
    ON public.building_stats
    FOR UPDATE
    USING (
        campaign_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_stats.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- Add comments
COMMENT ON TABLE public.building_stats IS 'Real-time statistics for buildings. Updated by triggers when QR codes are scanned or visits logged.';
COMMENT ON COLUMN public.building_stats.gers_id IS 'Denormalized GERS ID for fast lookup without joining buildings table';
COMMENT ON COLUMN public.building_stats.status IS 'Building status: not_visited (red), visited (green), hot (blue). QR scanned overrides to yellow in UI.';
COMMENT ON COLUMN public.building_stats.scans_total IS 'Total number of QR code scans for this building';
COMMENT ON COLUMN public.building_stats.scans_today IS 'QR code scans today (resets daily)';

-- =====================================================
-- 4. Create trigger function for updated_at
-- =====================================================

CREATE OR REPLACE FUNCTION update_buildings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_buildings_updated_at
    BEFORE UPDATE ON public.buildings
    FOR EACH ROW
    EXECUTE FUNCTION update_buildings_updated_at();

CREATE TRIGGER update_building_stats_updated_at
    BEFORE UPDATE ON public.building_stats
    FOR EACH ROW
    EXECUTE FUNCTION update_buildings_updated_at();

-- =====================================================
-- 5. Grant permissions
-- =====================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.buildings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.building_address_links TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.building_stats TO authenticated;

-- Service role has full access
GRANT ALL ON public.buildings TO service_role;
GRANT ALL ON public.building_address_links TO service_role;
GRANT ALL ON public.building_stats TO service_role;

-- Anonymous users can view buildings (for public maps)
GRANT SELECT ON public.buildings TO anon;

-- =====================================================
-- Notify PostgREST to reload schema
-- =====================================================

NOTIFY pgrst, 'reload schema';
