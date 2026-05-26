BEGIN;

CREATE TABLE IF NOT EXISTS public.campaign_parcels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  external_id TEXT NOT NULL,
  geom geometry(Geometry, 4326) NOT NULL,
  properties JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (campaign_id, external_id)
);

CREATE INDEX IF NOT EXISTS campaign_parcels_campaign_id_idx
  ON public.campaign_parcels (campaign_id);

CREATE INDEX IF NOT EXISTS campaign_parcels_geom_gix
  ON public.campaign_parcels USING GIST (geom);

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS parcel_enrichment_status TEXT NOT NULL DEFAULT 'not_started'
    CHECK (parcel_enrichment_status IN ('not_started', 'queued', 'processing', 'ready', 'failed', 'skipped')),
  ADD COLUMN IF NOT EXISTS parcel_source_id TEXT,
  ADD COLUMN IF NOT EXISTS parcel_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS parcel_enriched_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS parcel_enrichment_error TEXT,
  ADD COLUMN IF NOT EXISTS parcel_enrichment_debug JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON TABLE public.campaign_parcels IS
'Campaign-scoped parcel polygons used for map rendering and parcel-assisted building/address linking.';

COMMENT ON COLUMN public.campaigns.parcel_enrichment_status IS
'Lifecycle for parcel enrichment: not_started, queued, processing, ready, failed, or skipped.';

COMMENT ON COLUMN public.campaigns.parcel_count IS
'Number of parcel polygons persisted for this campaign.';

CREATE OR REPLACE FUNCTION public.set_campaign_parcels_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_campaign_parcels_updated_at
  ON public.campaign_parcels;

CREATE TRIGGER set_campaign_parcels_updated_at
  BEFORE UPDATE ON public.campaign_parcels
  FOR EACH ROW
  EXECUTE FUNCTION public.set_campaign_parcels_updated_at();

CREATE OR REPLACE FUNCTION public.bulk_upsert_auto_building_links(
  p_campaign_id UUID,
  p_links JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER := 0;
BEGIN
  WITH raw_links AS (
    SELECT *
    FROM jsonb_to_recordset(
      CASE
        WHEN jsonb_typeof(p_links) = 'array' THEN p_links
        ELSE '[]'::jsonb
      END
    ) AS link_row(
      campaign_id UUID,
      address_id UUID,
      building_id UUID,
      match_type TEXT,
      link_source TEXT,
      confidence DOUBLE PRECISION,
      distance_meters DOUBLE PRECISION,
      building_height DOUBLE PRECISION
    )
  ),
  clean_links AS (
    SELECT
      p_campaign_id AS campaign_id,
      address_id,
      building_id,
      COALESCE(NULLIF(match_type, ''), 'nearest_building_15m') AS match_type,
      CASE
        WHEN link_source IN ('auto', 'auto_parcel') THEN link_source
        ELSE 'auto'
      END AS link_source,
      GREATEST(0.0, LEAST(1.0, COALESCE(confidence, 0.0))) AS confidence,
      distance_meters,
      building_height
    FROM raw_links
    WHERE campaign_id = p_campaign_id
      AND address_id IS NOT NULL
      AND building_id IS NOT NULL
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id,
      address_id,
      building_id,
      match_type,
      link_source,
      confidence,
      distance_meters,
      building_height
    )
    SELECT
      campaign_id,
      address_id,
      building_id,
      match_type,
      link_source,
      confidence,
      distance_meters,
      building_height
    FROM clean_links
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET
      building_id = EXCLUDED.building_id,
      match_type = EXCLUDED.match_type,
      link_source = EXCLUDED.link_source,
      confidence = EXCLUDED.confidence,
      distance_meters = EXCLUDED.distance_meters,
      building_height = EXCLUDED.building_height
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel')
    RETURNING address_id
  )
  SELECT COUNT(*)
  INTO v_inserted
  FROM upserted;

  RETURN jsonb_build_object('upserted', v_inserted);
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_upsert_auto_building_links(UUID, JSONB)
TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
