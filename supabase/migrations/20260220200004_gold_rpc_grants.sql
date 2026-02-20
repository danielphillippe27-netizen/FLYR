-- Grants for all Gold RPCs and spatial indexes cleanup.

BEGIN;

-- Gold polygon query RPCs (SECURITY DEFINER, but explicit grants for clarity).
GRANT EXECUTE ON FUNCTION public.get_gold_addresses_in_polygon_geojson(text, text)
    TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_gold_buildings_in_polygon_geojson(text)
    TO authenticated, service_role;

-- Gold linker (called by provision backend with service role).
GRANT EXECUTE ON FUNCTION public.link_campaign_addresses_gold(uuid, text)
    TO service_role;

-- Ensure Gold table direct access is available to service role for ingest scripts.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ref_buildings_gold TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ref_addresses_gold TO service_role;
GRANT SELECT ON public.ref_buildings_gold TO authenticated;
GRANT SELECT ON public.ref_addresses_gold TO authenticated;

-- Sequence grants for idx SERIAL columns (only if sequences exist; tables created elsewhere may not have them).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname = 'public' AND c.relname = 'ref_buildings_gold_idx_seq') THEN
    EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE public.ref_buildings_gold_idx_seq TO service_role';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname = 'public' AND c.relname = 'ref_addresses_gold_idx_seq') THEN
    EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE public.ref_addresses_gold_idx_seq TO service_role';
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
