-- Migration: Create function to update farm polygon from GeoJSON
-- Created: 2025-01-26
-- Purpose: Convert GeoJSON string to PostGIS geometry and update farm polygon

-- Function to update farm polygon from GeoJSON
CREATE OR REPLACE FUNCTION public.update_farm_polygon(
    p_farm_id uuid,
    p_polygon_geojson text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.farms
    SET polygon = ST_SetSRID(ST_GeomFromGeoJSON(p_polygon_geojson), 4326)::geometry(Polygon, 4326)
    WHERE id = p_farm_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.update_farm_polygon(uuid, text) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.update_farm_polygon(uuid, text) IS 'Updates farm polygon from GeoJSON string, converting to PostGIS geometry';



