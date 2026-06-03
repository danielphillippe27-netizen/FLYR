BEGIN;

DO $$
BEGIN
  IF to_regclass('public.campaign_parcels') IS NULL THEN
    RETURN;
  END IF;

  WITH duplicate_rows AS (
    SELECT ctid
    FROM (
      SELECT
        ctid,
        row_number() OVER (
          PARTITION BY campaign_id, external_id
          ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
        ) AS duplicate_rank
      FROM public.campaign_parcels
    ) ranked
    WHERE duplicate_rank > 1
  )
  DELETE FROM public.campaign_parcels parcels
  USING duplicate_rows
  WHERE parcels.ctid = duplicate_rows.ctid;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'campaign_parcels_campaign_external_id_uidx'
  ) THEN
    EXECUTE
      'CREATE UNIQUE INDEX campaign_parcels_campaign_external_id_uidx ON public.campaign_parcels (campaign_id, external_id)';
  END IF;
END;
$$;

COMMIT;
