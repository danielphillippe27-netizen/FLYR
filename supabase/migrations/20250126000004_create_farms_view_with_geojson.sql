-- Migration: Create farms view with GeoJSON polygon
-- Created: 2025-01-26
-- Purpose: Provide a view that returns polygon as GeoJSON string for easier querying

-- Create view that includes polygon as GeoJSON
CREATE OR REPLACE VIEW public.farms_with_geojson AS
SELECT 
    id,
    owner_id,
    name,
    CASE 
        WHEN polygon IS NOT NULL THEN ST_AsGeoJSON(polygon)::text
        ELSE NULL
    END as polygon,
    start_date,
    end_date,
    frequency,
    created_at,
    area_label
FROM public.farms;

-- Grant access to authenticated users
GRANT SELECT ON public.farms_with_geojson TO authenticated;

-- Add comment
COMMENT ON VIEW public.farms_with_geojson IS 'Farms view with polygon converted to GeoJSON string for easier querying';



