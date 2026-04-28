-- Migration: Update get_buildings_by_address_ids RPC to return front_bearing
-- Created: 2025-11-26
-- Purpose: Add front_bearing column to RPC return so Swift client can decode it

-- Note: The Swift code expects a function that returns TABLE with:
--   address_id, geometry_geojson, height_m, min_height_m, building_id, front_bearing
-- This migration updates the function to query from campaign_buildings table
-- and return front_bearing along with other fields.

-- Drop existing function if it exists (there may be multiple overloads)
DROP FUNCTION IF EXISTS public.get_buildings_by_address_ids(p_address_ids uuid[]);
DROP FUNCTION IF EXISTS public.get_buildings_by_address_ids(p_address_ids text[]);

-- Create new function that returns explicit table columns including front_bearing
-- This queries from campaign_buildings table which has the front_bearing column
CREATE OR REPLACE FUNCTION public.get_buildings_by_address_ids(p_address_ids uuid[])
RETURNS TABLE (
  address_id uuid,
  geometry_geojson jsonb,
  height_m double precision,
  min_height_m double precision,
  building_id text,
  front_bearing double precision  -- NEW
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cb.address_id,
    ST_AsGeoJSON(cb.geometry)::jsonb AS geometry_geojson,
    cb.height_m,
    cb.min_height_m,
    cb.building_id,
    COALESCE(cb.front_bearing, 0.0) AS front_bearing  -- Default to 0 if NULL
  FROM public.campaign_buildings cb
  WHERE cb.address_id = ANY(p_address_ids)
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_buildings_by_address_ids(uuid[]) TO anon, authenticated;

-- Add comment
COMMENT ON FUNCTION public.get_buildings_by_address_ids(uuid[]) IS 
  'Returns table with address_id, geometry_geojson (ST_AsGeoJSON), height_m, min_height_m, building_id, and front_bearing for given address IDs from campaign_buildings table.';








