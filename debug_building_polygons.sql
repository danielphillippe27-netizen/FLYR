-- Debug script for building_polygons table
-- Run this in Supabase SQL Editor to diagnose the issue

-- 1️⃣ Check if any rows exist at all
SELECT 
  COUNT(*) as total_rows,
  COUNT(DISTINCT address_id) as unique_addresses,
  MIN(created_at) as first_created,
  MAX(created_at) as last_created
FROM public.building_polygons;

-- 2️⃣ Check table structure and constraints
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'building_polygons'
ORDER BY ordinal_position;

-- 3️⃣ Check RLS policies
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'building_polygons';

-- 4️⃣ Check if geom column has valid JSONB structure (sample)
SELECT 
  id,
  address_id,
  source,
  jsonb_typeof(geom) as geom_type,
  geom->>'type' as feature_type,
  geom->'geometry'->>'type' as geometry_type,
  area_m2,
  created_at
FROM public.building_polygons
LIMIT 5;

-- 5️⃣ Check for foreign key constraint violations
-- This will show if address_id values don't exist in campaign_addresses
SELECT 
  bp.address_id,
  bp.id as polygon_id,
  CASE WHEN ca.id IS NULL THEN 'MISSING FK' ELSE 'OK' END as fk_status
FROM public.building_polygons bp
LEFT JOIN public.campaign_addresses ca ON ca.id = bp.address_id
LIMIT 10;

-- 6️⃣ Test insert with a sample (replace with real address_id)
-- Uncomment and run with a valid address_id to test:
/*
INSERT INTO public.building_polygons (address_id, source, geom, area_m2)
VALUES (
  'YOUR-ADDRESS-ID-HERE'::uuid,
  'mapbox_mvt',
  '{"type":"Feature","geometry":{"type":"Polygon","coordinates":[[[-78.622,43.987],[-78.621,43.987],[-78.621,43.988],[-78.622,43.988],[-78.622,43.987]]]}}'::jsonb,
  100.0
)
ON CONFLICT(address_id) DO UPDATE
SET geom = EXCLUDED.geom,
    area_m2 = EXCLUDED.area_m2,
    updated_at = now();
*/

-- 7️⃣ Check recent Edge Function activity (if you have access to logs table)
-- This query may not work depending on your Supabase setup
SELECT 
  function_name,
  COUNT(*) as call_count,
  MAX(created_at) as last_call
FROM edge_function_logs
WHERE function_name = 'tiledecode_buildings'
GROUP BY function_name;







