BEGIN;

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS provision_timings JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.campaigns.provision_timings IS
'Versioned timing and count metadata captured during campaign provisioning for source scans, DB writes, materialization, and linker stages.';

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
      'auto'::TEXT AS link_source,
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
    WHERE building_address_links.link_source = 'auto'
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

COMMENT ON FUNCTION public.bulk_upsert_auto_building_links(UUID, JSONB) IS
'Set-based bulk upsert for backend-generated automatic building-address links. Manual links are never overwritten.';

NOTIFY pgrst, 'reload schema';

COMMIT;
