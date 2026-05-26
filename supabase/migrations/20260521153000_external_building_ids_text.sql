-- Support municipal/snapshot building identifiers such as `durham_buildings:226859`.
-- Earlier migrations created these columns/checks for UUID-only Gold linking, but
-- Silver/Diamond campaign edits persist external ids on campaign_addresses.

DROP INDEX IF EXISTS public.idx_campaign_addresses_gers_id;
DROP INDEX IF EXISTS public.idx_campaign_addresses_building_gers_id;
DROP INDEX IF EXISTS public.idx_buildings_gers_id;
DROP INDEX IF EXISTS public.idx_building_stats_gers_id;
DROP INDEX IF EXISTS public.idx_building_stats_gers_id_lower;

ALTER TABLE public.campaign_addresses
  ALTER COLUMN gers_id TYPE TEXT USING gers_id::TEXT,
  ALTER COLUMN building_gers_id TYPE TEXT USING building_gers_id::TEXT;

ALTER TABLE public.buildings
  ALTER COLUMN gers_id TYPE TEXT USING gers_id::TEXT;

ALTER TABLE public.building_stats
  ALTER COLUMN gers_id TYPE TEXT USING gers_id::TEXT;

CREATE INDEX IF NOT EXISTS idx_campaign_addresses_gers_id
  ON public.campaign_addresses(gers_id)
  WHERE gers_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_addresses_building_gers_id
  ON public.campaign_addresses(building_gers_id)
  WHERE building_gers_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_buildings_gers_id
  ON public.buildings(gers_id)
  WHERE gers_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_building_stats_gers_id
  ON public.building_stats(gers_id)
  WHERE gers_id IS NOT NULL;

ALTER TABLE public.campaign_addresses
  ADD COLUMN IF NOT EXISTS match_source TEXT,
  ADD COLUMN IF NOT EXISTS confidence DOUBLE PRECISION CHECK (confidence >= 0 AND confidence <= 1);

ALTER TABLE public.campaign_addresses
  DROP CONSTRAINT IF EXISTS campaign_addresses_match_source_check;

COMMENT ON COLUMN public.campaign_addresses.gers_id IS
'External/source address identifier. May be UUID for Gold data or municipal/snapshot text ids.';

COMMENT ON COLUMN public.campaign_addresses.building_gers_id IS
'Public building identifier used by map features. May be UUID for Gold data or municipal/snapshot text ids.';

COMMENT ON COLUMN public.buildings.gers_id IS
'Public/source building identifier used by map features. May be UUID text for Gold/Overture or municipal/snapshot text ids.';

COMMENT ON COLUMN public.building_stats.gers_id IS
'Denormalized public building identifier for map state lookup. May be UUID text or municipal/snapshot text ids.';

NOTIFY pgrst, 'reload schema';
