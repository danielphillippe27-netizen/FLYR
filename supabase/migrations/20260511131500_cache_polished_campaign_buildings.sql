BEGIN;

CREATE TABLE IF NOT EXISTS public.campaign_polished_building_features (
  campaign_id UUID PRIMARY KEY REFERENCES public.campaigns(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('gold', 'silver', 'manual', 'mixed')),
  feature_count INTEGER NOT NULL DEFAULT 0 CHECK (feature_count >= 0),
  feature_collection JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_campaign_polished_building_features_updated_at
  ON public.campaign_polished_building_features(updated_at DESC);

ALTER TABLE public.campaign_polished_building_features ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campaign_polished_building_features_select_owner_or_member"
  ON public.campaign_polished_building_features;
CREATE POLICY "campaign_polished_building_features_select_owner_or_member"
  ON public.campaign_polished_building_features
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.campaigns c
      LEFT JOIN public.workspace_members wm
        ON wm.workspace_id = c.workspace_id
        AND wm.user_id = auth.uid()
      LEFT JOIN public.workspaces w
        ON w.id = c.workspace_id
      WHERE c.id = campaign_polished_building_features.campaign_id
        AND (
          c.owner_id = auth.uid()
          OR wm.user_id IS NOT NULL
          OR w.owner_id = auth.uid()
        )
    )
  );

DROP POLICY IF EXISTS "campaign_polished_building_features_service_manage"
  ON public.campaign_polished_building_features;
CREATE POLICY "campaign_polished_building_features_service_manage"
  ON public.campaign_polished_building_features
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

GRANT SELECT ON public.campaign_polished_building_features TO authenticated;
GRANT ALL ON public.campaign_polished_building_features TO service_role;

CREATE OR REPLACE FUNCTION public.touch_campaign_polished_building_features_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS touch_campaign_polished_building_features_updated_at
  ON public.campaign_polished_building_features;
CREATE TRIGGER touch_campaign_polished_building_features_updated_at
  BEFORE UPDATE ON public.campaign_polished_building_features
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_campaign_polished_building_features_updated_at();

CREATE OR REPLACE FUNCTION public.invalidate_campaign_polished_building_features()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign_id UUID;
BEGIN
  v_campaign_id := COALESCE(NEW.campaign_id, OLD.campaign_id);
  IF v_campaign_id IS NOT NULL THEN
    DELETE FROM public.campaign_polished_building_features
    WHERE campaign_id = v_campaign_id;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.invalidate_campaign_polished_building_features_from_campaign()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.campaign_polished_building_features
  WHERE campaign_id = NEW.id;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.campaign_addresses') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_campaign_addresses
      ON public.campaign_addresses;
    CREATE TRIGGER invalidate_polished_buildings_on_campaign_addresses
      AFTER INSERT OR UPDATE OR DELETE ON public.campaign_addresses
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;

  IF to_regclass('public.building_address_links') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_building_address_links
      ON public.building_address_links;
    CREATE TRIGGER invalidate_polished_buildings_on_building_address_links
      AFTER INSERT OR UPDATE OR DELETE ON public.building_address_links
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;

  IF to_regclass('public.building_units') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_building_units
      ON public.building_units;
    CREATE TRIGGER invalidate_polished_buildings_on_building_units
      AFTER INSERT OR UPDATE OR DELETE ON public.building_units
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;

  IF to_regclass('public.campaign_hidden_buildings') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_hidden_buildings
      ON public.campaign_hidden_buildings;
    CREATE TRIGGER invalidate_polished_buildings_on_hidden_buildings
      AFTER INSERT OR UPDATE OR DELETE ON public.campaign_hidden_buildings
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;

  IF to_regclass('public.campaign_snapshots') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_campaign_snapshots
      ON public.campaign_snapshots;
    CREATE TRIGGER invalidate_polished_buildings_on_campaign_snapshots
      AFTER INSERT OR UPDATE OR DELETE ON public.campaign_snapshots
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;

  IF to_regclass('public.campaign_parcels') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_campaign_parcels
      ON public.campaign_parcels;
    CREATE TRIGGER invalidate_polished_buildings_on_campaign_parcels
      AFTER INSERT OR UPDATE OR DELETE ON public.campaign_parcels
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features();
  END IF;

  IF to_regclass('public.campaigns') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS invalidate_polished_buildings_on_campaigns
      ON public.campaigns;
    CREATE TRIGGER invalidate_polished_buildings_on_campaigns
      AFTER UPDATE OF territory_boundary, provision_source, provision_phase, optimized_at, map_mode, has_parcels, building_link_confidence
      ON public.campaigns
      FOR EACH ROW
      EXECUTE FUNCTION public.invalidate_campaign_polished_building_features_from_campaign();
  END IF;
END;
$$;

COMMENT ON TABLE public.campaign_polished_building_features IS
'Per-campaign polished building GeoJSON returned by the buildings API after source selection, linking cleanup, hidden-building filtering, and render filtering. This avoids recomputing parcel/linker-derived cleanup on every campaign open.';

COMMENT ON FUNCTION public.invalidate_campaign_polished_building_features() IS
'Deletes the polished building cache for a campaign when source map/link/snapshot rows change.';

COMMIT;
