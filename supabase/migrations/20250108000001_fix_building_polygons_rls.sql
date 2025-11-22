-- Fix RLS and permissions for building_polygons table
-- Ensures service role can INSERT/UPDATE and adds diagnostic capabilities

-- 1. Grant INSERT/UPDATE to service_role explicitly (bypasses RLS)
-- Service role should bypass RLS, but explicit grants ensure it works
GRANT INSERT, UPDATE ON public.building_polygons TO service_role;

-- 2. Add a policy for service_role INSERT/UPDATE (explicit, though service_role bypasses RLS)
-- This is redundant but makes the intent clear
DROP POLICY IF EXISTS "building_polygons_service_role_all" ON public.building_polygons;
CREATE POLICY "building_polygons_service_role_all"
  ON public.building_polygons
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- 3. Verify the table structure is correct
DO $$
BEGIN
  -- Check if geom column exists and is JSONB
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'building_polygons' 
      AND column_name = 'geom'
      AND data_type = 'jsonb'
  ) THEN
    RAISE EXCEPTION 'building_polygons.geom column is not JSONB type';
  END IF;
  
  -- Check if address_id has FK constraint
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu 
      ON tc.constraint_name = kcu.constraint_name
    WHERE tc.table_schema = 'public'
      AND tc.table_name = 'building_polygons'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND kcu.column_name = 'address_id'
  ) THEN
    RAISE WARNING 'building_polygons.address_id may not have FK constraint to campaign_addresses';
  END IF;
END $$;

-- 4. Add comment documenting the setup
COMMENT ON TABLE public.building_polygons IS 
  'Cached building polygons from Mapbox MVT decode. RLS enabled: SELECT for authenticated, INSERT/UPDATE for service_role only.';






