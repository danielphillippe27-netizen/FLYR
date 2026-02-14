-- =====================================================
-- Campaign Snapshots and Building Units (Lambda + S3)
--
-- campaign_snapshots: metadata for S3 snapshot files produced by
--   provision (Tile Lambda writes buildings/addresses GeoJSON to S3;
--   backend stores bucket/keys here).
-- building_units: townhouse/split unit polygons per address, filled by
--   TownhouseSplitterService; map merges with S3 building GeoJSON for extrusion.
-- =====================================================

-- =====================================================
-- 1. campaign_snapshots
-- =====================================================

CREATE TABLE IF NOT EXISTS public.campaign_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    bucket TEXT NOT NULL,
    buildings_key TEXT,
    addresses_key TEXT,
    buildings_count INTEGER,
    addresses_count INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_campaign_snapshot UNIQUE (campaign_id)
);

CREATE INDEX IF NOT EXISTS idx_campaign_snapshots_campaign ON public.campaign_snapshots(campaign_id);

ALTER TABLE public.campaign_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view snapshots for their campaigns"
    ON public.campaign_snapshots
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_snapshots.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Service role can manage campaign_snapshots"
    ON public.campaign_snapshots
    FOR ALL
    USING (auth.role() = 'service_role');

COMMENT ON TABLE public.campaign_snapshots IS 'Metadata for S3 snapshot files (buildings, addresses) produced by provision Lambda. Building geometry lives in S3; this table stores bucket and keys for GET /api/campaigns/[id]/buildings.';

-- =====================================================
-- 2. building_units (townhouse/split units per address)
-- =====================================================

CREATE TABLE IF NOT EXISTS public.building_units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    parent_building_id TEXT NOT NULL,  -- GERS ID of parent building (from S3/Overture)
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    unit_geometry GEOMETRY(Polygon, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_building_units_campaign ON public.building_units(campaign_id);
CREATE INDEX IF NOT EXISTS idx_building_units_parent ON public.building_units(parent_building_id);
CREATE INDEX IF NOT EXISTS idx_building_units_address ON public.building_units(address_id);
CREATE INDEX IF NOT EXISTS idx_building_units_geom ON public.building_units USING GIST(unit_geometry);

ALTER TABLE public.building_units ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view building_units for their campaigns"
    ON public.building_units
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = building_units.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

CREATE POLICY "Service role can manage building_units"
    ON public.building_units
    FOR ALL
    USING (auth.role() = 'service_role');

COMMENT ON TABLE public.building_units IS 'Townhouse/split unit polygons per address; filled by TownhouseSplitterService. Map merges with S3 building GeoJSON for extruded units.';
COMMENT ON COLUMN public.building_units.parent_building_id IS 'GERS ID of parent building (from S3 snapshot).';
