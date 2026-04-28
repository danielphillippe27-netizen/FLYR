-- Migration: Create campaign_buildings table
-- Created: 2025-01-25
-- Purpose: Cache building polygons per campaign address (1:1 relationship)
--          Buildings are synced once via Edge Function, then rendered from cached geometry

-- Enable PostGIS if not already enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create campaign_buildings table
CREATE TABLE IF NOT EXISTS public.campaign_buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    building_id TEXT, -- Optional Mapbox building identifier
    geometry GEOMETRY(Polygon, 4326) NOT NULL,
    height_m DOUBLE PRECISION, -- Optional building height in meters
    min_height_m DOUBLE PRECISION, -- Optional minimum height (base) in meters
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure one building per address (1:1 relationship)
    CONSTRAINT unique_campaign_building_address UNIQUE (address_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_campaign_buildings_campaign_id 
    ON public.campaign_buildings(campaign_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_campaign_buildings_address_id 
    ON public.campaign_buildings(address_id);

CREATE INDEX IF NOT EXISTS idx_campaign_buildings_geometry 
    ON public.campaign_buildings USING GIST(geometry);

-- Trigger for updated_at
CREATE TRIGGER update_campaign_buildings_updated_at
    BEFORE UPDATE ON public.campaign_buildings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================
-- Mirror campaigns table policy: users can only access buildings for campaigns they own

ALTER TABLE public.campaign_buildings ENABLE ROW LEVEL SECURITY;

-- Users can read buildings for campaigns they own
CREATE POLICY "Users can read buildings for their own campaigns"
    ON public.campaign_buildings
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_buildings.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can insert buildings for campaigns they own
CREATE POLICY "Users can insert buildings for their own campaigns"
    ON public.campaign_buildings
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_buildings.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can update buildings for campaigns they own
CREATE POLICY "Users can update buildings for their own campaigns"
    ON public.campaign_buildings
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_buildings.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- Users can delete buildings for campaigns they own
CREATE POLICY "Users can delete buildings for their own campaigns"
    ON public.campaign_buildings
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns c
            WHERE c.id = campaign_buildings.campaign_id
            AND c.owner_id = auth.uid()
        )
    );

-- ============================================================================
-- Grants
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_buildings TO authenticated;

-- ============================================================================
-- RPC Function: Upsert campaign building with PostGIS geometry conversion
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_upsert_campaign_building(
    p_campaign_id UUID,
    p_address_id UUID,
    p_geom_json JSONB,
    p_building_id TEXT DEFAULT NULL,
    p_height_m DOUBLE PRECISION DEFAULT NULL,
    p_min_height_m DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_geometry GEOMETRY(Polygon, 4326);
BEGIN
    -- Convert GeoJSON geometry to PostGIS geometry
    -- Handle both Polygon and MultiPolygon (take first polygon from MultiPolygon)
    IF p_geom_json->>'type' = 'Polygon' THEN
        v_geometry := ST_SetSRID(ST_GeomFromGeoJSON(p_geom_json::text), 4326);
    ELSIF p_geom_json->>'type' = 'MultiPolygon' THEN
        -- Extract first polygon from MultiPolygon
        v_geometry := ST_SetSRID(
            ST_GeomFromGeoJSON(
                jsonb_build_object(
                    'type', 'Polygon',
                    'coordinates', (p_geom_json->'coordinates'->0)
                )::text
            ),
            4326
        );
    ELSE
        RAISE EXCEPTION 'Unsupported geometry type: %', p_geom_json->>'type';
    END IF;

    -- Ensure it's a Polygon (not MultiPolygon)
    IF ST_GeometryType(v_geometry) != 'ST_Polygon' THEN
        RAISE EXCEPTION 'Geometry must be a Polygon, got: %', ST_GeometryType(v_geometry);
    END IF;

    -- Upsert into campaign_buildings
    INSERT INTO public.campaign_buildings (
        campaign_id,
        address_id,
        building_id,
        geometry,
        height_m,
        min_height_m
    )
    VALUES (
        p_campaign_id,
        p_address_id,
        p_building_id,
        v_geometry,
        p_height_m,
        p_min_height_m
    )
    ON CONFLICT (address_id) DO UPDATE
    SET
        building_id = EXCLUDED.building_id,
        geometry = EXCLUDED.geometry,
        height_m = EXCLUDED.height_m,
        min_height_m = EXCLUDED.min_height_m,
        updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_upsert_campaign_building(UUID, UUID, JSONB, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.campaign_buildings IS 'Cached building polygons for campaign addresses. One building per address (1:1). Synced via Edge Function campaign-sync-buildings.';
COMMENT ON COLUMN public.campaign_buildings.address_id IS 'Foreign key to campaign_addresses. UNIQUE constraint ensures 1:1 relationship.';
COMMENT ON COLUMN public.campaign_buildings.building_id IS 'Optional Mapbox building identifier from tilequery API';
COMMENT ON COLUMN public.campaign_buildings.geometry IS 'PostGIS Polygon geometry in WGS84 (SRID 4326)';
COMMENT ON COLUMN public.campaign_buildings.height_m IS 'Building height in meters (for 3D extrusion)';
COMMENT ON COLUMN public.campaign_buildings.min_height_m IS 'Building base/minimum height in meters (for 3D extrusion)';
COMMENT ON FUNCTION public.fn_upsert_campaign_building IS 'Upserts a campaign building with PostGIS geometry conversion from GeoJSON. Used by campaign-sync-buildings Edge Function.';

