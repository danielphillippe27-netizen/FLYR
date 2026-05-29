BEGIN;

ALTER TABLE public.building_address_links
  DROP CONSTRAINT IF EXISTS building_address_links_link_source_check;

ALTER TABLE public.building_address_links
  ADD CONSTRAINT building_address_links_link_source_check
  CHECK (link_source IN ('auto', 'auto_parcel', 'manual'));

ALTER TABLE public.building_address_links
  DROP CONSTRAINT IF EXISTS building_address_links_match_type_check;

ALTER TABLE public.building_address_links
  ADD CONSTRAINT building_address_links_match_type_check
  CHECK (
    match_type IS NULL
    OR match_type IN (
      'containment',
      'parcel_bridge',
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

COMMENT ON CONSTRAINT building_address_links_link_source_check
ON public.building_address_links IS
'Allows automatic building links from direct spatial matches, parcel-assisted matches, and manual user overrides.';

COMMENT ON CONSTRAINT building_address_links_match_type_check
ON public.building_address_links IS
'Allows current backend linker match types including direct containment and parcel_bridge evidence links.';

NOTIFY pgrst, 'reload schema';

COMMIT;
