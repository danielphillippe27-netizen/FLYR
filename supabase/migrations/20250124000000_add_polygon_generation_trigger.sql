-- Migration: Add automatic polygon generation trigger for campaign addresses
-- Created: 2025-01-24
-- Purpose: Automatically generate stylized rectangle polygons (12m x 10m) when addresses are inserted
--          This ensures every address gets a polygon without manual intervention

-- Function to create a rectangle polygon around a point (same logic as Edge Function)
-- Parameters: point geometry, width_meters (default 12), height_meters (default 10)
CREATE OR REPLACE FUNCTION public.create_rectangle_around_point(
    p_point GEOMETRY(POINT, 4326),
    p_width_meters DOUBLE PRECISION DEFAULT 12.0,
    p_height_meters DOUBLE PRECISION DEFAULT 10.0
)
RETURNS GEOMETRY(POLYGON, 4326)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_lat DOUBLE PRECISION;
    v_lng DOUBLE PRECISION;
    v_meters_per_degree_lat CONSTANT DOUBLE PRECISION := 111320.0;
    v_meters_per_degree_lon_base CONSTANT DOUBLE PRECISION := 111320.0;
    v_meters_per_degree_lon DOUBLE PRECISION;
    v_half_width_deg DOUBLE PRECISION;
    v_half_height_deg DOUBLE PRECISION;
    v_top_left GEOMETRY(POINT, 4326);
    v_top_right GEOMETRY(POINT, 4326);
    v_bottom_right GEOMETRY(POINT, 4326);
    v_bottom_left GEOMETRY(POINT, 4326);
BEGIN
    -- Extract lat/lng from point
    v_lat := ST_Y(p_point);
    v_lng := ST_X(p_point);
    
    -- Convert meters to degrees
    -- Latitude: constant conversion
    v_half_height_deg := (p_height_meters / 2.0) / v_meters_per_degree_lat;
    
    -- Longitude: varies by latitude
    v_meters_per_degree_lon := v_meters_per_degree_lon_base * cos(radians(v_lat));
    v_half_width_deg := (p_width_meters / 2.0) / v_meters_per_degree_lon;
    
    -- Create 4 corner points
    v_top_left := ST_SetSRID(ST_MakePoint(v_lng - v_half_width_deg, v_lat + v_half_height_deg), 4326);
    v_top_right := ST_SetSRID(ST_MakePoint(v_lng + v_half_width_deg, v_lat + v_half_height_deg), 4326);
    v_bottom_right := ST_SetSRID(ST_MakePoint(v_lng + v_half_width_deg, v_lat - v_half_height_deg), 4326);
    v_bottom_left := ST_SetSRID(ST_MakePoint(v_lng - v_half_width_deg, v_lat - v_half_height_deg), 4326);
    
    -- Create polygon from 4 corners (closed ring)
    RETURN ST_MakePolygon(ST_MakeLine(ARRAY[
        v_top_left,
        v_top_right,
        v_bottom_right,
        v_bottom_left,
        v_top_left  -- Close the ring
    ]));
END;
$$;

-- Trigger function to generate polygon when address is inserted
CREATE OR REPLACE FUNCTION public.trigger_generate_address_polygon()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_polygon GEOMETRY(POLYGON, 4326);
BEGIN
    -- Only generate if geom is not null
    IF NEW.geom IS NULL THEN
        RAISE WARNING 'Address % has no geometry, skipping polygon generation', NEW.id;
        RETURN NEW;
    END IF;
    
    -- Generate rectangle polygon around the point
    v_polygon := public.create_rectangle_around_point(NEW.geom, 12.0, 10.0);
    
    -- Insert into address_buildings (upsert via unique constraint)
    INSERT INTO public.address_buildings (address_id, geom)
    VALUES (NEW.id, v_polygon)
    ON CONFLICT (address_id) DO UPDATE
    SET
        geom = EXCLUDED.geom,
        created_at = now();
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail address insertion
        RAISE WARNING 'Failed to generate polygon for address %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$;

-- Create trigger that fires AFTER INSERT on campaign_addresses
DROP TRIGGER IF EXISTS trigger_auto_generate_address_polygon ON public.campaign_addresses;
CREATE TRIGGER trigger_auto_generate_address_polygon
    AFTER INSERT ON public.campaign_addresses
    FOR EACH ROW
    WHEN (NEW.geom IS NOT NULL)
    EXECUTE FUNCTION public.trigger_generate_address_polygon();

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.create_rectangle_around_point(GEOMETRY, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
GRANT EXECUTE ON FUNCTION public.trigger_generate_address_polygon() TO authenticated;

-- Comment for documentation
COMMENT ON FUNCTION public.create_rectangle_around_point IS 'Creates a stylized rectangle polygon around a point. Default size: 12m x 10m. Used for automatic polygon generation.';
COMMENT ON FUNCTION public.trigger_generate_address_polygon IS 'Trigger function that automatically generates a stylized rectangle polygon when a campaign address is inserted.';









