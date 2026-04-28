-- Migration: Add front_bearing columns and helper functions
-- Created: 2025-11-26
-- Purpose: Add front_bearing support to rotate 3D house models to face streets
--          Computes bearing from nearest road segment to building centroid

-- Enable PostGIS if not already enabled
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- Part 1: Add front_bearing columns to tables
-- ============================================================================

-- Add front_bearing to address_buildings
ALTER TABLE public.address_buildings
  ADD COLUMN IF NOT EXISTS front_bearing double precision DEFAULT 0;

-- Add front_bearing to campaign_buildings
ALTER TABLE public.campaign_buildings
  ADD COLUMN IF NOT EXISTS front_bearing double precision DEFAULT 0;

-- Add comments
COMMENT ON COLUMN public.address_buildings.front_bearing IS 'Bearing in degrees (0-360) that building front should face. 0=north, 90=east, 180=south, 270=west. Computed from nearest road segment.';
COMMENT ON COLUMN public.campaign_buildings.front_bearing IS 'Bearing in degrees (0-360) that building front should face. Copied from address_buildings.front_bearing.';

-- ============================================================================
-- Part 2: Helper function to compute front_bearing for a single address_building
-- ============================================================================

-- Note: This function assumes a 'roads' table exists with:
--   - id (primary key)
--   - geom (LineString, SRID 4326)
-- If the table name/structure differs, adapt accordingly.

CREATE OR REPLACE FUNCTION public.compute_front_bearing_for_address_building(p_building_id uuid)
RETURNS double precision
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_building_geom geometry;
    v_road_geom geometry;
    v_closest_point_on_road geometry;
    v_bearing double precision;
    v_road_exists boolean;
BEGIN
    -- Check if roads table exists
    SELECT EXISTS (
        SELECT 1 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'roads'
    ) INTO v_road_exists;

    IF NOT v_road_exists THEN
        -- Roads table doesn't exist, return 0 (no rotation)
        RAISE WARNING 'roads table does not exist, returning 0 for front_bearing';
        RETURN 0;
    END IF;

    -- Get building geometry
    SELECT geom
    INTO v_building_geom
    FROM public.address_buildings
    WHERE id = p_building_id;

    IF v_building_geom IS NULL THEN
        RETURN 0;
    END IF;

    -- Find nearest road to the building centroid
    SELECT r.geom
    INTO v_road_geom
    FROM public.roads r
    ORDER BY r.geom <-> ST_Centroid(v_building_geom)
    LIMIT 1;

    IF v_road_geom IS NULL THEN
        RETURN 0;
    END IF;

    -- Find closest point on the road to the building
    SELECT ST_ClosestPoint(v_road_geom, ST_Centroid(v_building_geom))
    INTO v_closest_point_on_road;

    -- Take a small segment of the road around that closest point for direction
    -- If the road is a LineString, we can interpolate a point slightly "ahead"
    -- along the line and compute the azimuth between them.
    v_bearing := degrees(
        ST_Azimuth(
            v_closest_point_on_road,
            ST_LineInterpolatePoint(
                v_road_geom,
                LEAST(1.0, GREATEST(0.0, ST_LineLocatePoint(v_road_geom, v_closest_point_on_road) + 0.001))
            )
        )
    );

    -- Normalize to 0–360
    IF v_bearing < 0 THEN
        v_bearing := v_bearing + 360;
    END IF;

    -- Persist on address_buildings
    UPDATE public.address_buildings
    SET front_bearing = v_bearing
    WHERE id = p_building_id;

    RETURN v_bearing;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.compute_front_bearing_for_address_building(uuid) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.compute_front_bearing_for_address_building(uuid) IS 
    'Computes front_bearing for an address_building by finding nearest road segment and calculating azimuth. Returns bearing in degrees (0-360).';

-- ============================================================================
-- Part 3: Helper function to sync front_bearing from address_buildings to campaign_buildings
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_campaign_building_front_bearing(p_campaign_building_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_address_id uuid;
    v_address_building_id uuid;
    v_bearing double precision;
BEGIN
    -- Get address_id from campaign_buildings
    SELECT address_id
    INTO v_address_id
    FROM public.campaign_buildings
    WHERE id = p_campaign_building_id;

    IF v_address_id IS NULL THEN
        RETURN;
    END IF;

    -- Get address_building_id from address_buildings
    SELECT id
    INTO v_address_building_id
    FROM public.address_buildings
    WHERE address_id = v_address_id
    LIMIT 1;

    IF v_address_building_id IS NULL THEN
        RETURN;
    END IF;

    -- Get bearing from address_buildings
    SELECT front_bearing
    INTO v_bearing
    FROM public.address_buildings
    WHERE id = v_address_building_id;

    -- If bearing is NULL or 0, try to compute it
    IF v_bearing IS NULL OR v_bearing = 0 THEN
        v_bearing := public.compute_front_bearing_for_address_building(v_address_building_id);
    END IF;

    -- Update campaign_buildings with the bearing
    UPDATE public.campaign_buildings
    SET front_bearing = v_bearing
    WHERE id = p_campaign_building_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.sync_campaign_building_front_bearing(uuid) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.sync_campaign_building_front_bearing(uuid) IS 
    'Syncs front_bearing from address_buildings to campaign_buildings. Computes bearing if missing.';

-- ============================================================================
-- Part 4: Backfill function to compute bearings for all existing address_buildings
-- ============================================================================

CREATE OR REPLACE FUNCTION public.backfill_address_buildings_front_bearing()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rec record;
    v_count integer := 0;
BEGIN
    FOR rec IN
        SELECT id
        FROM public.address_buildings
        WHERE front_bearing IS NULL OR front_bearing = 0
    LOOP
        PERFORM public.compute_front_bearing_for_address_building(rec.id);
        v_count := v_count + 1;
        
        -- Log progress every 100 records
        IF v_count % 100 = 0 THEN
            RAISE NOTICE 'Processed % address_buildings...', v_count;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Backfill complete. Processed % address_buildings.', v_count;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.backfill_address_buildings_front_bearing() TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.backfill_address_buildings_front_bearing() IS 
    'Backfills front_bearing for all address_buildings with NULL or 0 bearing. Run once manually after migration.';








