BEGIN;

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
  v_manual_link_count INTEGER := 0;
  v_address_updated_at TIMESTAMPTZ;
  v_building_updated_at TIMESTAMPTZ;
  v_snapshot_updated_at TIMESTAMPTZ;
  v_polished_updated_at TIMESTAMPTZ;
  v_parcel_updated_at TIMESTAMPTZ;
  v_manual_link_updated_at TIMESTAMPTZ;
  v_effective_building_count INTEGER := 0;
  v_effective_building_updated_at TIMESTAMPTZ;
  v_payload JSONB;
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
      'counts', jsonb_build_object('addresses', 0, 'buildings', 0, 'parcels', 0, 'manual_links', 0),
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

  SELECT COUNT(*), MAX(COALESCE(bal.modified_at, bal.matched_at))
  INTO v_manual_link_count, v_manual_link_updated_at
  FROM public.building_address_links bal
  WHERE bal.campaign_id = p_campaign_id
    AND COALESCE(bal.link_source, bal.match_type, '') = 'manual';

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

  v_payload := jsonb_build_object(
    'campaign_id', p_campaign_id,
    'campaign_updated_at', v_campaign.updated_at,
    'addresses_ready_at', v_campaign.addresses_ready_at,
    'map_ready_at', v_campaign.map_ready_at,
    'optimized_at', v_campaign.optimized_at,
    'territory_boundary', v_campaign.territory_boundary,
    'provision_source', v_campaign.provision_source,
    'provision_phase', v_campaign.provision_phase,
    'bundle_cache_version', 'canonical-map-bundle-v3',
    'map_mode', v_campaign.map_mode,
    'has_parcels', v_campaign.has_parcels,
    'building_link_confidence', v_campaign.building_link_confidence,
    'address_count', COALESCE(v_address_count, 0),
    'building_count', v_effective_building_count,
    'parcel_count', COALESCE(v_parcel_count, 0),
    'manual_link_count', COALESCE(v_manual_link_count, 0),
    'address_updated_at', v_address_updated_at,
    'building_updated_at', v_effective_building_updated_at,
    'snapshot_building_count', COALESCE(v_snapshot_building_count, 0),
    'snapshot_updated_at', v_snapshot_updated_at,
    'polished_building_count', COALESCE(v_polished_building_count, 0),
    'polished_updated_at', v_polished_updated_at,
    'parcel_updated_at', v_parcel_updated_at,
    'manual_link_updated_at', v_manual_link_updated_at
  );

  RETURN jsonb_build_object(
    'source_version', md5(v_payload::TEXT),
    'source', v_payload,
    'counts', jsonb_build_object(
      'addresses', COALESCE(v_address_count, 0),
      'buildings', v_effective_building_count,
      'parcels', COALESCE(v_parcel_count, 0),
      'manual_links', COALESCE(v_manual_link_count, 0),
      'bundle_cache_version', 'canonical-map-bundle-v3',
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
      COALESCE(v_manual_link_updated_at, '-infinity'::timestamptz)
    )
  );
END;
$$;

UPDATE public.campaign_map_bundles
SET
  is_current = FALSE,
  expires_at = NOW(),
  updated_at = NOW()
WHERE COALESCE(counts->>'bundle_cache_version', '') <> 'canonical-map-bundle-v3';

COMMENT ON FUNCTION public.rpc_get_campaign_map_source_version(UUID) IS
'Computes a lightweight pull-based campaign map source version from campaign metadata, source table counts, latest timestamps, and polished building cache writes.';

NOTIFY pgrst, 'reload schema';

COMMIT;
