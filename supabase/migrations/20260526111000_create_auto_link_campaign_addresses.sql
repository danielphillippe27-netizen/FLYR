BEGIN;

CREATE OR REPLACE FUNCTION public.auto_link_campaign_addresses(
  p_campaign_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_linked INTEGER := 0;
  v_skipped_manual INTEGER := 0;
  v_total_addresses INTEGER := 0;
  v_unlinked INTEGER := 0;
BEGIN
  SELECT COUNT(*)
  INTO v_total_addresses
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL;

  SELECT COUNT(DISTINCT bal.address_id)
  INTO v_skipped_manual
  FROM public.building_address_links bal
  INNER JOIN public.campaign_addresses ca
    ON ca.id = bal.address_id
  WHERE bal.campaign_id = p_campaign_id
    AND ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL
    AND bal.link_source = 'manual';

  WITH candidates AS (
    SELECT
      ca.id AS address_id,
      nearest.building_id,
      nearest.distance_meters
    FROM public.campaign_addresses ca
    CROSS JOIN LATERAL (
      SELECT
        ranked.building_id,
        ranked.distance_meters
      FROM (
        SELECT
          b.id AS building_id,
          ST_Distance(ca.geom::geography, b.geom::geography) AS distance_meters,
          LEAD(ST_Distance(ca.geom::geography, b.geom::geography)) OVER (
            ORDER BY ST_Distance(ca.geom::geography, b.geom::geography), b.id
          ) AS next_distance_meters,
          ROW_NUMBER() OVER (
            ORDER BY ST_Distance(ca.geom::geography, b.geom::geography), b.id
          ) AS link_rank
        FROM public.buildings b
        WHERE b.campaign_id = p_campaign_id
          AND b.geom IS NOT NULL
          AND ST_DWithin(ca.geom::geography, b.geom::geography, 8.0)
      ) ranked
      WHERE ranked.link_rank = 1
        AND (
          ranked.next_distance_meters IS NULL
          OR ranked.next_distance_meters - ranked.distance_meters >= 3.0
        )
    ) nearest
    WHERE ca.campaign_id = p_campaign_id
      AND ca.geom IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.building_address_links manual_link
        WHERE manual_link.campaign_id = p_campaign_id
          AND manual_link.address_id = ca.id
          AND manual_link.link_source = 'manual'
      )
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id,
      address_id,
      building_id,
      match_type,
      link_source,
      confidence,
      distance_meters
    )
    SELECT
      p_campaign_id,
      candidates.address_id,
      candidates.building_id::TEXT,
      'nearest_building_15m',
      'auto',
      GREATEST(0.0, LEAST(1.0, 1.0 - (candidates.distance_meters / 8.0))),
      candidates.distance_meters
    FROM candidates
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET
      building_id = EXCLUDED.building_id,
      match_type = EXCLUDED.match_type,
      link_source = EXCLUDED.link_source,
      confidence = EXCLUDED.confidence,
      distance_meters = EXCLUDED.distance_meters
    WHERE building_address_links.link_source = 'auto'
    RETURNING address_id
  )
  SELECT COUNT(*)
  INTO v_linked
  FROM upserted;

  v_unlinked := GREATEST(v_total_addresses - v_skipped_manual - v_linked, 0);

  RETURN jsonb_build_object(
    'linked', v_linked,
    'skipped_manual', v_skipped_manual,
    'unlinked', v_unlinked
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.auto_link_campaign_addresses(UUID)
TO service_role;

COMMENT ON FUNCTION public.auto_link_campaign_addresses(UUID) IS
'Auto-links campaign addresses to the nearest unambiguous campaign building within 8 metres. Only auto links are refreshed; manual overrides are never overwritten.';

NOTIFY pgrst, 'reload schema';

COMMIT;
