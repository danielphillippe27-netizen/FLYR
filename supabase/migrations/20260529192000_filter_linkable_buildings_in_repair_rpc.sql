CREATE OR REPLACE FUNCTION public.rpc_refresh_campaign_map_links(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_containment INTEGER := 0;
  v_parcel INTEGER := 0;
  v_nearest INTEGER := 0;
  v_total INTEGER := 0;
  v_source_version TEXT;
BEGIN
  SELECT COALESCE(
    public.rpc_get_campaign_map_source_version(p_campaign_id)->>'link_source_version',
    public.rpc_get_campaign_map_source_version(p_campaign_id)->>'source_version'
  )
  INTO v_source_version;

  SELECT COUNT(*)
  INTO v_total
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id
    AND ca.geom IS NOT NULL;

  WITH expired AS (
    UPDATE public.campaign_addresses ca
    SET match_source = 'client_auto_expired'
    WHERE ca.campaign_id = p_campaign_id
      AND ca.match_source = 'client_auto'
      AND ca.client_link_expires_at < NOW()
    RETURNING ca.id
  )
  UPDATE public.building_address_links bal
  SET link_source = 'client_auto_expired'
  WHERE bal.campaign_id = p_campaign_id
    AND bal.link_source = 'client_auto'
    AND bal.address_id IN (SELECT id FROM expired);

  DELETE FROM public.building_address_links bal
  WHERE bal.campaign_id = p_campaign_id
    AND bal.link_source IN ('auto', 'auto_parcel', 'client_auto_expired');

  WITH candidates AS (
    SELECT DISTINCT ON (ca.id)
      ca.id AS address_id,
      b.id AS building_uuid,
      b.gers_id::TEXT AS building_public_id,
      'containment_verified'::TEXT AS match_type,
      'auto'::TEXT AS link_source,
      1.0::DOUBLE PRECISION AS confidence,
      0.0::DOUBLE PRECISION AS distance_meters
    FROM public.campaign_addresses ca
    JOIN public.buildings b
      ON b.campaign_id = p_campaign_id
     AND b.geom IS NOT NULL
     AND ST_Area(b.geom::geography) >= 45.0
     AND ST_Covers(b.geom, ca.geom)
    WHERE ca.campaign_id = p_campaign_id
      AND ca.geom IS NOT NULL
      AND NULLIF(BTRIM(COALESCE(b.gers_id::TEXT, '')), '') IS NOT NULL
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
    ORDER BY ca.id, ST_Area(b.geom::geography) ASC, b.id
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id, address_id, building_id, match_type, link_source,
      confidence, distance_meters, source_version
    )
    SELECT p_campaign_id, address_id, building_uuid, match_type, link_source,
      confidence, distance_meters, v_source_version
    FROM candidates
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET building_id = EXCLUDED.building_id,
        match_type = EXCLUDED.match_type,
        link_source = EXCLUDED.link_source,
        confidence = EXCLUDED.confidence,
        distance_meters = EXCLUDED.distance_meters,
        source_version = EXCLUDED.source_version
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
    RETURNING address_id
  ),
  updated_addresses AS (
    UPDATE public.campaign_addresses ca
    SET building_gers_id = candidates.building_public_id,
        match_source = 'auto',
        confidence = candidates.confidence
    FROM candidates
    JOIN upserted ON upserted.address_id = candidates.address_id
    WHERE ca.id = candidates.address_id
      AND ca.campaign_id = p_campaign_id
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
    RETURNING ca.id
  )
  SELECT COUNT(*) INTO v_containment FROM updated_addresses;

  IF to_regclass('public.campaign_parcels') IS NOT NULL THEN
    WITH unlinked_addresses AS (
      SELECT ca.*
      FROM public.campaign_addresses ca
      WHERE ca.campaign_id = p_campaign_id
        AND ca.geom IS NOT NULL
        AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
        AND NOT EXISTS (
          SELECT 1 FROM public.building_address_links bal
          WHERE bal.campaign_id = p_campaign_id
            AND bal.address_id = ca.id
        )
    ),
    candidates AS (
      SELECT DISTINCT ON (ca.id)
        ca.id AS address_id,
        b.id AS building_uuid,
        b.gers_id::TEXT AS building_public_id,
        'parcel_bridge'::TEXT AS match_type,
        'auto_parcel'::TEXT AS link_source,
        0.90::DOUBLE PRECISION AS confidence,
        ST_Distance(ca.geom::geography, b.geom::geography) AS distance_meters
      FROM unlinked_addresses ca
      JOIN public.campaign_parcels cp
        ON cp.campaign_id = p_campaign_id
       AND cp.geom IS NOT NULL
       AND ST_Covers(cp.geom, ca.geom)
      JOIN public.buildings b
        ON b.campaign_id = p_campaign_id
       AND b.geom IS NOT NULL
       AND ST_Area(b.geom::geography) >= 45.0
       AND ST_Intersects(b.geom, cp.geom)
      WHERE NULLIF(BTRIM(COALESCE(b.gers_id::TEXT, '')), '') IS NOT NULL
      ORDER BY ca.id, ST_Distance(ca.geom::geography, b.geom::geography), b.id
    ),
    upserted AS (
      INSERT INTO public.building_address_links (
        campaign_id, address_id, building_id, match_type, link_source,
        confidence, distance_meters, source_version
      )
      SELECT p_campaign_id, address_id, building_uuid, match_type, link_source,
        confidence, distance_meters, v_source_version
      FROM candidates
      ON CONFLICT (campaign_id, address_id) DO UPDATE
      SET building_id = EXCLUDED.building_id,
          match_type = EXCLUDED.match_type,
          link_source = EXCLUDED.link_source,
          confidence = EXCLUDED.confidence,
          distance_meters = EXCLUDED.distance_meters,
          source_version = EXCLUDED.source_version
      WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
      RETURNING address_id
    ),
    updated_addresses AS (
      UPDATE public.campaign_addresses ca
      SET building_gers_id = candidates.building_public_id,
          match_source = 'auto',
          confidence = candidates.confidence
      FROM candidates
      JOIN upserted ON upserted.address_id = candidates.address_id
      WHERE ca.id = candidates.address_id
        AND ca.campaign_id = p_campaign_id
        AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
      RETURNING ca.id
    )
    SELECT COUNT(*) INTO v_parcel FROM updated_addresses;
  END IF;

  WITH unlinked_addresses AS (
    SELECT ca.*
    FROM public.campaign_addresses ca
    WHERE ca.campaign_id = p_campaign_id
      AND ca.geom IS NOT NULL
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
      AND NOT EXISTS (
        SELECT 1 FROM public.building_address_links bal
        WHERE bal.campaign_id = p_campaign_id
          AND bal.address_id = ca.id
      )
  ),
  candidates AS (
    SELECT
      ca.id AS address_id,
      nearest.building_uuid,
      nearest.building_public_id,
      'nearest_building_15m'::TEXT AS match_type,
      'auto'::TEXT AS link_source,
      GREATEST(0.0, LEAST(1.0, 1.0 - (nearest.distance_meters / 15.0)))::DOUBLE PRECISION AS confidence,
      nearest.distance_meters
    FROM unlinked_addresses ca
    CROSS JOIN LATERAL (
      SELECT
        ranked.building_uuid,
        ranked.building_public_id,
        ranked.distance_meters
      FROM (
        SELECT
          b.id AS building_uuid,
          b.gers_id::TEXT AS building_public_id,
          COALESCE(b.units_count, 1) AS units_count,
          COALESCE(b.is_townhome_row, false) AS is_townhome_row,
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
          AND ST_Area(b.geom::geography) >= 45.0
          AND NULLIF(BTRIM(COALESCE(b.gers_id::TEXT, '')), '') IS NOT NULL
          AND ST_DWithin(ca.geom::geography, b.geom::geography, 15.0)
          AND (
            COALESCE(b.units_count, 1) > 1
            OR COALESCE(b.is_townhome_row, false)
            OR NOT EXISTS (
              SELECT 1
              FROM public.building_address_links existing
              WHERE existing.campaign_id = p_campaign_id
                AND existing.building_id = b.id::TEXT
                AND existing.address_id <> ca.id
            )
          )
      ) ranked
      WHERE ranked.link_rank = 1
        AND (
          ranked.next_distance_meters IS NULL
          OR ranked.next_distance_meters - ranked.distance_meters >= 3.0
        )
    ) nearest
  ),
  upserted AS (
    INSERT INTO public.building_address_links (
      campaign_id, address_id, building_id, match_type, link_source,
      confidence, distance_meters, source_version
    )
    SELECT p_campaign_id, address_id, building_uuid, match_type, link_source,
      confidence, distance_meters, v_source_version
    FROM candidates
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET building_id = EXCLUDED.building_id,
        match_type = EXCLUDED.match_type,
        link_source = EXCLUDED.link_source,
        confidence = EXCLUDED.confidence,
        distance_meters = EXCLUDED.distance_meters,
        source_version = EXCLUDED.source_version
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
    RETURNING address_id
  ),
  updated_addresses AS (
    UPDATE public.campaign_addresses ca
    SET building_gers_id = candidates.building_public_id,
        match_source = 'auto',
        confidence = candidates.confidence
    FROM candidates
    JOIN upserted ON upserted.address_id = candidates.address_id
    WHERE ca.id = candidates.address_id
      AND ca.campaign_id = p_campaign_id
      AND COALESCE(ca.match_source, '') NOT IN ('manual', 'client_auto')
    RETURNING ca.id
  )
  SELECT COUNT(*) INTO v_nearest FROM updated_addresses;

  RETURN jsonb_build_object(
    'total_addresses', v_total,
    'containment', v_containment,
    'parcel', v_parcel,
    'nearest', v_nearest,
    'nearest_radius_meters', 15,
    'nearest_disambiguation_gap_meters', 3,
    'linked', v_containment + v_parcel + v_nearest,
    'source_version', v_source_version
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_refresh_campaign_map_links(UUID) TO service_role;
NOTIFY pgrst, 'reload schema';
