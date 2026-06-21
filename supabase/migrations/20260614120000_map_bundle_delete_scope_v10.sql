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
  v_hidden_building_count INTEGER := 0;
  v_parcel_count INTEGER := 0;
  v_link_count INTEGER := 0;
  v_manual_link_count INTEGER := 0;
  v_address_updated_at TIMESTAMPTZ;
  v_building_updated_at TIMESTAMPTZ;
  v_snapshot_updated_at TIMESTAMPTZ;
  v_polished_updated_at TIMESTAMPTZ;
  v_hidden_building_updated_at TIMESTAMPTZ;
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
    c.provision_source
  INTO v_campaign
  FROM public.campaigns c
  WHERE c.id = p_campaign_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'source_version', md5(('missing:' || p_campaign_id::TEXT)::TEXT),
      'link_source_version', md5(('missing-linker:' || p_campaign_id::TEXT)::TEXT),
      'counts', jsonb_build_object('addresses', 0, 'buildings', 0, 'parcels', 0, 'links', 0, 'manual_links', 0, 'bundle_cache_version', 'canonical-map-bundle-v10'),
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

  IF to_regclass('public.campaign_hidden_buildings') IS NOT NULL THEN
    SELECT COUNT(*), MAX(chb.created_at)
    INTO v_hidden_building_count, v_hidden_building_updated_at
    FROM public.campaign_hidden_buildings chb
    WHERE chb.campaign_id = p_campaign_id;
  END IF;

  IF to_regclass('public.campaign_parcels') IS NOT NULL THEN
    SELECT COUNT(*), MAX(COALESCE(cp.updated_at, cp.created_at))
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
    COALESCE(v_polished_updated_at, '-infinity'::timestamptz),
    COALESCE(v_hidden_building_updated_at, '-infinity'::timestamptz)
  );

  v_linker_payload := jsonb_build_object(
    'campaign_id', p_campaign_id,
    'territory_boundary', v_campaign.territory_boundary,
    'provision_source', v_campaign.provision_source,
    'bundle_cache_version', 'canonical-map-bundle-v10',
    'address_count', COALESCE(v_address_count, 0),
    'building_count', v_effective_building_count,
    'hidden_building_count', COALESCE(v_hidden_building_count, 0),
    'parcel_count', COALESCE(v_parcel_count, 0),
    'address_updated_at', v_address_updated_at,
    'building_updated_at', v_effective_building_updated_at,
    'hidden_building_updated_at', v_hidden_building_updated_at,
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
      'hidden_buildings', COALESCE(v_hidden_building_count, 0),
      'parcels', COALESCE(v_parcel_count, 0),
      'links', COALESCE(v_link_count, 0),
      'manual_links', COALESCE(v_manual_link_count, 0),
      'bundle_cache_version', 'canonical-map-bundle-v10',
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
      COALESCE(v_link_updated_at, '-infinity'::timestamptz),
      COALESCE(v_manual_link_updated_at, '-infinity'::timestamptz)
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_map_source_version(UUID)
TO authenticated, anon, service_role;

UPDATE public.campaign_map_bundles
SET is_current = false,
    expires_at = NOW(),
    updated_at = NOW(),
    counts = COALESCE(counts, '{}'::jsonb) || jsonb_build_object('bundle_cache_version', 'canonical-map-bundle-v10')
WHERE COALESCE(counts->>'bundle_cache_version', '') <> 'canonical-map-bundle-v10';

COMMENT ON FUNCTION public.rpc_get_campaign_map_source_version(UUID) IS
'Computes the canonical campaign map source version, including delete-scope bundle cache v10 and hidden-building suppressions.';
