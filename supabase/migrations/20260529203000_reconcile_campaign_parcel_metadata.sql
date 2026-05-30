WITH parcel_counts AS (
  SELECT
    campaign_id,
    COUNT(*)::integer AS parcel_count
  FROM public.campaign_parcels
  GROUP BY campaign_id
),
updated_campaigns AS (
  UPDATE public.campaigns c
  SET
    has_parcels = pc.parcel_count > 0,
    parcel_count = pc.parcel_count,
    parcel_enrichment_status = CASE
      WHEN pc.parcel_count > 0
       AND c.parcel_enrichment_status IN ('not_started', 'queued', 'processing', 'failed', 'skipped')
        THEN 'ready'
      ELSE c.parcel_enrichment_status
    END,
    parcel_source_id = COALESCE(c.parcel_source_id, 'campaign_parcels'),
    parcel_enriched_at = CASE
      WHEN pc.parcel_count > 0 THEN COALESCE(c.parcel_enriched_at, NOW())
      ELSE c.parcel_enriched_at
    END,
    parcel_enrichment_error = CASE
      WHEN pc.parcel_count > 0 THEN NULL
      ELSE c.parcel_enrichment_error
    END,
    parcel_enrichment_debug = COALESCE(c.parcel_enrichment_debug, '{}'::jsonb) || jsonb_build_object(
      'metadata_reconciled_at', NOW(),
      'metadata_reconciled_source', 'campaign_parcels',
      'metadata_reconciled_count', pc.parcel_count
    )
  FROM parcel_counts pc
  WHERE c.id = pc.campaign_id
    AND pc.parcel_count > 0
    AND (
      c.has_parcels IS DISTINCT FROM TRUE
      OR c.parcel_count IS DISTINCT FROM pc.parcel_count
      OR c.parcel_enrichment_status IN ('not_started', 'queued', 'processing', 'failed', 'skipped')
      OR c.parcel_source_id IS NULL
    )
  RETURNING c.id
)
UPDATE public.campaign_map_bundles cmb
SET
  is_current = FALSE,
  expires_at = NOW(),
  updated_at = NOW()
FROM parcel_counts pc
WHERE cmb.campaign_id = pc.campaign_id
  AND cmb.is_current = TRUE
  AND pc.parcel_count > 0
  AND (
    COALESCE(cmb.counts->>'parcel_source', '') <> 'campaign_parcels'
    OR COALESCE((cmb.counts->>'parcels')::integer, 0) < pc.parcel_count
    OR cmb.campaign_id IN (SELECT id FROM updated_campaigns)
  );
