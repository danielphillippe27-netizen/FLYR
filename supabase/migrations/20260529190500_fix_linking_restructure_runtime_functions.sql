BEGIN;

ALTER TABLE public.building_address_links
  ADD COLUMN IF NOT EXISTS source_version TEXT,
  ADD COLUMN IF NOT EXISTS matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS modified_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_map_source_version(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign RECORD;
  v_address_count INTEGER := 0;
  v_building_count INTEGER := 0;
  v_snapshot_building_count INTEGER := 0;
  v_polished_building_count INTEGER := 0;
  v_parcel_count INTEGER := 0;
  v_link_count INTEGER := 0;
  v_manual_link_count INTEGER := 0;
  v_address_updated_at TIMESTAMPTZ;
  v_building_updated_at TIMESTAMPTZ;
  v_snapshot_updated_at TIMESTAMPTZ;
  v_polished_updated_at TIMESTAMPTZ;
  v_parcel_updated_at TIMESTAMPTZ;
  v_link_updated_at TIMESTAMPTZ;
  v_manual_link_updated_at TIMESTAMPTZ;
  v_effective_building_count INTEGER := 0;
  v_effective_building_updated_at TIMESTAMPTZ;
  v_linker_payload JSONB;
  v_bundle_payload JSONB;
BEGIN
  SELECT
    c.id,
    c.updated_at,
    c.addresses_ready_at,
    c.map_ready_at,
    c.optimized_at,
    c.territory_boundary,
    c.provision_source,
    c.provision_phase,
    c.map_mode,
    c.has_parcels,
    c.building_link_confidence
  INTO v_campaign
  FROM public.campaigns c
  WHERE c.id = p_campaign_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'source_version', md5(('missing:' || p_campaign_id::TEXT)::TEXT),
      'link_source_version', md5(('missing-linker:' || p_campaign_id::TEXT)::TEXT),
      'counts', jsonb_build_object('addresses', 0, 'buildings', 0, 'parcels', 0, 'links', 0, 'manual_links', 0),
      'updated_at', NOW()
    );
  END IF;

  SELECT COUNT(*), MAX(ca.created_at)
  INTO v_address_count, v_address_updated_at
  FROM public.campaign_addresses ca
  WHERE ca.campaign_id = p_campaign_id;

  SELECT COUNT(*), MAX(COALESCE(b.updated_at, b.created_at))
  INTO v_building_count, v_building_updated_at
  FROM public.buildings b
  WHERE b.campaign_id = p_campaign_id;

  IF to_regclass('public.campaign_snapshots') IS NOT NULL THEN
    SELECT
      COALESCE(MAX(
        GREATEST(
          COALESCE(cs.buildings_count, 0),
          CASE
            WHEN COALESCE(cs.tile_metrics->>'campaign_buildings_count', '') ~ '^[0-9]+$'
              THEN (cs.tile_metrics->>'campaign_buildings_count')::INTEGER
            ELSE 0
          END
        )
      ), 0),
      MAX(cs.created_at)
    INTO v_snapshot_building_count, v_snapshot_updated_at
    FROM public.campaign_snapshots cs
    WHERE cs.campaign_id = p_campaign_id;
  END IF;

  IF to_regclass('public.campaign_polished_building_features') IS NOT NULL THEN
    SELECT
      COALESCE(MAX(cpbf.feature_count), 0),
      MAX(COALESCE(cpbf.updated_at, cpbf.created_at))
    INTO v_polished_building_count, v_polished_updated_at
    FROM public.campaign_polished_building_features cpbf
    WHERE cpbf.campaign_id = p_campaign_id;
  END IF;

  IF to_regclass('public.campaign_parcels') IS NOT NULL THEN
    SELECT COUNT(*), MAX(cp.created_at)
    INTO v_parcel_count, v_parcel_updated_at
    FROM public.campaign_parcels cp
    WHERE cp.campaign_id = p_campaign_id;
  END IF;

  SELECT
    COUNT(*),
    MAX(COALESCE(bal.modified_at, bal.matched_at)),
    COUNT(*) FILTER (WHERE COALESCE(bal.link_source, bal.match_type, '') = 'manual'),
    MAX(COALESCE(bal.modified_at, bal.matched_at)) FILTER (
      WHERE COALESCE(bal.link_source, bal.match_type, '') = 'manual'
    )
  INTO v_link_count, v_link_updated_at, v_manual_link_count, v_manual_link_updated_at
  FROM public.building_address_links bal
  WHERE bal.campaign_id = p_campaign_id;

  v_effective_building_count := GREATEST(
    COALESCE(v_building_count, 0),
    COALESCE(v_snapshot_building_count, 0),
    COALESCE(v_polished_building_count, 0)
  );
  v_effective_building_updated_at := GREATEST(
    COALESCE(v_building_updated_at, '-infinity'::timestamptz),
    COALESCE(v_snapshot_updated_at, '-infinity'::timestamptz),
    COALESCE(v_polished_updated_at, '-infinity'::timestamptz)
  );

  v_linker_payload := jsonb_build_object(
    'campaign_id', p_campaign_id,
    'campaign_updated_at', v_campaign.updated_at,
    'addresses_ready_at', v_campaign.addresses_ready_at,
    'map_ready_at', v_campaign.map_ready_at,
    'optimized_at', v_campaign.optimized_at,
    'territory_boundary', v_campaign.territory_boundary,
    'provision_source', v_campaign.provision_source,
    'provision_phase', v_campaign.provision_phase,
    'bundle_cache_version', 'canonical-map-bundle-v5',
    'map_mode', v_campaign.map_mode,
    'has_parcels', v_campaign.has_parcels,
    'building_link_confidence', v_campaign.building_link_confidence,
    'address_count', COALESCE(v_address_count, 0),
    'building_count', v_effective_building_count,
    'parcel_count', COALESCE(v_parcel_count, 0),
    'address_updated_at', v_address_updated_at,
    'building_updated_at', v_effective_building_updated_at,
    'snapshot_building_count', COALESCE(v_snapshot_building_count, 0),
    'snapshot_updated_at', v_snapshot_updated_at,
    'polished_building_count', COALESCE(v_polished_building_count, 0),
    'polished_updated_at', v_polished_updated_at,
    'parcel_updated_at', v_parcel_updated_at
  );

  v_bundle_payload := v_linker_payload || jsonb_build_object(
    'link_count', COALESCE(v_link_count, 0),
    'manual_link_count', COALESCE(v_manual_link_count, 0),
    'link_updated_at', v_link_updated_at,
    'manual_link_updated_at', v_manual_link_updated_at
  );

  RETURN jsonb_build_object(
    'source_version', md5(v_bundle_payload::TEXT),
    'link_source_version', md5(v_linker_payload::TEXT),
    'source', v_bundle_payload,
    'counts', jsonb_build_object(
      'addresses', COALESCE(v_address_count, 0),
      'buildings', v_effective_building_count,
      'parcels', COALESCE(v_parcel_count, 0),
      'links', COALESCE(v_link_count, 0),
      'manual_links', COALESCE(v_manual_link_count, 0),
      'bundle_cache_version', 'canonical-map-bundle-v5',
      'polished_buildings', COALESCE(v_polished_building_count, 0)
    ),
    'updated_at', GREATEST(
      COALESCE(v_campaign.updated_at, '-infinity'::timestamptz),
      COALESCE(v_campaign.addresses_ready_at, '-infinity'::timestamptz),
      COALESCE(v_campaign.map_ready_at, '-infinity'::timestamptz),
      COALESCE(v_campaign.optimized_at, '-infinity'::timestamptz),
      COALESCE(v_address_updated_at, '-infinity'::timestamptz),
      v_effective_building_updated_at,
      COALESCE(v_parcel_updated_at, '-infinity'::timestamptz),
      COALESCE(v_link_updated_at, '-infinity'::timestamptz)
    )
  );
END;
$$;

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
      building_height DOUBLE PRECISION,
      source_version TEXT
    )
  ),
  clean_links AS (
    SELECT
      p_campaign_id AS campaign_id,
      address_id,
      building_id,
      COALESCE(NULLIF(match_type, ''), 'nearest_building_15m') AS match_type,
      CASE
        WHEN link_source IN ('auto', 'auto_parcel', 'client_auto_expired') THEN link_source
        ELSE 'auto'
      END AS link_source,
      GREATEST(0.0, LEAST(1.0, COALESCE(confidence, 0.0))) AS confidence,
      distance_meters,
      building_height,
      NULLIF(source_version, '') AS source_version
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
      building_height,
      source_version
    )
    SELECT
      campaign_id,
      address_id,
      building_id,
      match_type,
      link_source,
      confidence,
      distance_meters,
      building_height,
      source_version
    FROM clean_links
    ON CONFLICT (campaign_id, address_id) DO UPDATE
    SET
      building_id = EXCLUDED.building_id,
      match_type = EXCLUDED.match_type,
      link_source = EXCLUDED.link_source,
      confidence = EXCLUDED.confidence,
      distance_meters = EXCLUDED.distance_meters,
      building_height = EXCLUDED.building_height,
      source_version = EXCLUDED.source_version
    WHERE building_address_links.link_source IN ('auto', 'auto_parcel', 'client_auto_expired')
    RETURNING address_id
  )
  SELECT COUNT(*)
  INTO v_inserted
  FROM upserted;

  RETURN jsonb_build_object('upserted', v_inserted);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_map_source_version(UUID)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bulk_upsert_auto_building_links(UUID, JSONB)
TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
