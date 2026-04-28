-- Migration: Add source column to campaign_buildings table
-- Purpose: Track whether building polygon came from Mapbox directly or was auto-split generated
-- This enables the auto-splitting feature for large buildings covering multiple addresses

-- Add source column to campaign_buildings table
ALTER TABLE public.campaign_buildings
  ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'mapbox' NOT NULL;

-- Add CHECK constraint to ensure valid source values
ALTER TABLE public.campaign_buildings
  ADD CONSTRAINT check_source_valid
  CHECK (source IN ('mapbox', 'split-generated'));

-- Add comment
COMMENT ON COLUMN public.campaign_buildings.source IS 'Source of building polygon: mapbox (from Mapbox tiles) or split-generated (auto-split from large building)';

-- Update RPC function to accept p_source parameter
CREATE OR REPLACE FUNCTION public.fn_upsert_campaign_building(
    p_campaign_id UUID,
    p_address_id UUID,
    p_geom_json JSONB,
    p_building_id TEXT DEFAULT NULL,
    p_height_m DOUBLE PRECISION DEFAULT NULL,
    p_min_height_m DOUBLE PRECISION DEFAULT NULL,
    p_source TEXT DEFAULT 'mapbox'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_geometry GEOMETRY(Polygon, 4326);
BEGIN
    -- Validate source parameter
    IF p_source NOT IN ('mapbox', 'split-generated') THEN
        RAISE EXCEPTION 'Invalid source value: %. Must be ''mapbox'' or ''split-generated''', p_source;
    END IF;

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
        min_height_m,
        source
    )
    VALUES (
        p_campaign_id,
        p_address_id,
        p_building_id,
        v_geometry,
        p_height_m,
        p_min_height_m,
        p_source
    )
    ON CONFLICT (address_id) DO UPDATE
    SET
        building_id = EXCLUDED.building_id,
        geometry = EXCLUDED.geometry,
        height_m = EXCLUDED.height_m,
        min_height_m = EXCLUDED.min_height_m,
        source = EXCLUDED.source,
        updated_at = now();
END;
$$;

-- Update grant statement for new function signature
GRANT EXECUTE ON FUNCTION public.fn_upsert_campaign_building(UUID, UUID, JSONB, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;

-- Update comment
COMMENT ON FUNCTION public.fn_upsert_campaign_building IS 'Upserts a campaign building with PostGIS geometry conversion from GeoJSON. Supports source tracking (mapbox or split-generated). Used by campaign-sync-buildings Edge Function.';









