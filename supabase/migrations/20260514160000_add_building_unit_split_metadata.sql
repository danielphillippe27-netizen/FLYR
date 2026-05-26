BEGIN;

ALTER TABLE public.building_units
  ADD COLUMN IF NOT EXISTS unit_number TEXT,
  ADD COLUMN IF NOT EXISTS split_method TEXT,
  ADD COLUMN IF NOT EXISTS parent_type TEXT,
  ADD COLUMN IF NOT EXISTS validation_status TEXT;

COMMENT ON COLUMN public.building_units.unit_number IS
'Display label for a split townhome/small-multifamily unit, usually the linked house number.';

COMMENT ON COLUMN public.building_units.split_method IS
'Algorithm used by TownhouseSplitterService to create the unit polygon.';

COMMENT ON COLUMN public.building_units.parent_type IS
'TownhouseSplitterService classification for the parent building.';

COMMENT ON COLUMN public.building_units.validation_status IS
'Validation result for the generated unit polygon.';

COMMIT;
