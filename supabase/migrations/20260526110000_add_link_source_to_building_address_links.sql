BEGIN;

ALTER TABLE public.building_address_links
  ADD COLUMN IF NOT EXISTS link_source TEXT NOT NULL DEFAULT 'auto';

ALTER TABLE public.building_address_links
  ALTER COLUMN link_source SET DEFAULT 'auto';

UPDATE public.building_address_links
SET link_source = CASE
  WHEN LOWER(COALESCE(link_source, '')) = 'manual' THEN 'manual'
  WHEN LOWER(COALESCE(match_type, '')) = 'manual' THEN 'manual'
  ELSE 'auto'
END
WHERE link_source IS DISTINCT FROM CASE
  WHEN LOWER(COALESCE(link_source, '')) = 'manual' THEN 'manual'
  WHEN LOWER(COALESCE(match_type, '')) = 'manual' THEN 'manual'
  ELSE 'auto'
END;

ALTER TABLE public.building_address_links
  ALTER COLUMN link_source SET NOT NULL;

ALTER TABLE public.building_address_links
  DROP CONSTRAINT IF EXISTS building_address_links_link_source_check;

ALTER TABLE public.building_address_links
  ADD CONSTRAINT building_address_links_link_source_check
  CHECK (link_source IN ('auto', 'manual'));

ALTER TABLE public.building_address_links
  DROP CONSTRAINT IF EXISTS building_address_links_match_type_check;

ALTER TABLE public.building_address_links
  ADD CONSTRAINT building_address_links_match_type_check
  CHECK (
    match_type IS NULL
    OR match_type IN (
      'containment_verified',
      'containment_suspect',
      'point_on_surface',
      'parcel_verified',
      'proximity_verified',
      'proximity_fallback',
      'nearest_building_15m',
      'client_auto',
      'manual',
      'orphan'
    )
  );

CREATE OR REPLACE FUNCTION public.set_building_address_link_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF LOWER(COALESCE(NEW.match_type, '')) = 'manual' THEN
    NEW.link_source := 'manual';
  ELSIF NEW.link_source IS NULL THEN
    NEW.link_source := 'auto';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_building_address_link_source
ON public.building_address_links;

CREATE TRIGGER set_building_address_link_source
BEFORE INSERT OR UPDATE OF match_type, link_source
ON public.building_address_links
FOR EACH ROW
EXECUTE FUNCTION public.set_building_address_link_source();

ALTER TABLE public.campaigns
  DROP CONSTRAINT IF EXISTS campaigns_provision_phase_check;

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_provision_phase_check
  CHECK (provision_phase IN (
    'created',
    'source_probed',
    'addresses_loading',
    'addresses_ready',
    'map_ready',
    'optimizing',
    'linked',
    'optimized',
    'failed'
  ));

COMMENT ON COLUMN public.building_address_links.link_source IS
'Source of the building-address assignment. auto rows may be refreshed by backend linking; manual rows are user overrides and must not be overwritten.';

COMMENT ON FUNCTION public.set_building_address_link_source() IS
'Keeps manual building-address assignments protected when manual-link RPCs write match_type = manual.';

COMMENT ON COLUMN public.campaigns.provision_phase IS
'Fine-grained provisioning lifecycle phase. linked means backend auto-linking completed; provision_status remains the backward-compatible ready/failed gate.';

NOTIFY pgrst, 'reload schema';

COMMIT;
