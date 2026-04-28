-- Migration: Create/Adapt address_buildings table for stylized polygons
-- Created: 2025-01-23
-- Purpose: Store one stylized rectangle polygon per campaign address
--          Replaces Mapbox building layer dependencies with simple 12m x 10m rectangles

-- Enable PostGIS if not already enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- Drop existing address_buildings table if it exists with old schema
-- We'll recreate it with the new schema
DROP TABLE IF EXISTS public.address_buildings CASCADE;

-- Create address_buildings table with new schema
CREATE TABLE public.address_buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address_id UUID NOT NULL REFERENCES public.campaign_addresses(id) ON DELETE CASCADE,
    geom GEOMETRY(Polygon, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Ensure one polygon per address
    CONSTRAINT unique_address_buildings_address_id UNIQUE (address_id)
);

-- Create indexes for performance
CREATE INDEX idx_address_buildings_address_id 
    ON public.address_buildings(address_id);

CREATE INDEX idx_address_buildings_geom 
    ON public.address_buildings USING GIST(geom);

-- Enable Row Level Security
ALTER TABLE public.address_buildings ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access buildings for addresses in their campaigns
CREATE POLICY "Users can view buildings for their campaign addresses"
    ON public.address_buildings
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.campaign_addresses ca
            JOIN public.campaigns c ON c.id = ca.campaign_id
            WHERE ca.id = address_buildings.address_id
            AND c.owner_id = auth.uid()
        )
    );

-- INSERT/UPDATE/DELETE only via service role (Edge Functions)
-- No direct user INSERT/UPDATE/DELETE policies needed

-- Grant SELECT to authenticated users (via RLS policy above)
GRANT SELECT ON public.address_buildings TO authenticated;

-- RPC function to insert/update stylized polygon for an address
CREATE OR REPLACE FUNCTION public.fn_upsert_address_building(
    p_address_id UUID,
    p_geojson JSONB
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
    IF p_geojson->>'type' != 'Polygon' THEN
        RAISE EXCEPTION 'Geometry must be a Polygon, got: %', p_geojson->>'type';
    END IF;

    v_geometry := ST_SetSRID(ST_GeomFromGeoJSON(p_geojson::text), 4326);

    -- Ensure it's a Polygon
    IF ST_GeometryType(v_geometry) != 'ST_Polygon' THEN
        RAISE EXCEPTION 'Geometry must be a Polygon, got: %', ST_GeometryType(v_geometry);
    END IF;

    -- Upsert into address_buildings
    INSERT INTO public.address_buildings (
        address_id,
        geom
    )
    VALUES (
        p_address_id,
        v_geometry
    )
    ON CONFLICT (address_id) DO UPDATE
    SET
        geom = EXCLUDED.geom,
        created_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_upsert_address_building(UUID, JSONB) TO authenticated;









