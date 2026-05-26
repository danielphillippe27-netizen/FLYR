BEGIN;

UPDATE public.campaigns
SET provision_status = 'ready'
WHERE provision_status = 'complete';

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_renderable_buildings(
  p_campaign_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_gold boolean := false;
  v_has_silver boolean := false;
  v_result jsonb := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.campaign_addresses ca
    JOIN public.ref_buildings_gold b
      ON b.id::text = COALESCE(ca.building_id::text, ca.building_gers_id::text)
    WHERE ca.campaign_id = p_campaign_id
    LIMIT 1
  )
  INTO v_has_gold;

  IF v_has_gold THEN
    SELECT jsonb_build_object(
      'type', 'FeatureCollection',
      'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
    )
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'type', 'Feature',
        'id', b.id::text,
        'geometry', ST_AsGeoJSON(b.geom, 6)::jsonb,
        'properties', jsonb_build_object(
          'id', b.id::text,
          'building_id', b.id::text,
          'gers_id', b.id::text,
          'source', 'gold',
          'address_count', COUNT(ca.id),
          'address_id', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.id)::text ELSE NULL END,
          'address_text', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.formatted) ELSE NULL END,
          'house_number', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.house_number) ELSE NULL END,
          'street_name', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.street_name) ELSE NULL END,
          'height', COALESCE(b.height_m, 10),
          'height_m', COALESCE(b.height_m, 10),
          'min_height', 0,
          'area_sqm', CASE
            WHEN b.area_sqm IS NULL OR b.area_sqm < 30
              THEN ROUND(ST_Area(b.geom::geography)::numeric, 2)
            ELSE b.area_sqm
          END,
          'building_type', b.building_type,
          'feature_type', 'matched_house',
          'feature_status', 'matched',
          'is_linked', true,
          'status', COALESCE(MIN(s.status), 'not_visited'),
          'scans_today', COALESCE(SUM(s.scans_today), 0),
          'scans_total', COALESCE(SUM(s.scans_total), 0)
        )
      ) AS feature
      FROM public.campaign_addresses ca
      JOIN public.ref_buildings_gold b
        ON b.id::text = COALESCE(ca.building_id::text, ca.building_gers_id::text)
      LEFT JOIN public.building_stats s
        ON s.gers_id = b.id::text
      WHERE ca.campaign_id = p_campaign_id
      GROUP BY b.id, b.geom, b.height_m, b.area_sqm, b.building_type
    ) f;

    RETURN COALESCE(v_result, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb));
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.building_address_links l
    JOIN public.buildings b
      ON b.gers_id = l.building_id
     AND b.campaign_id = p_campaign_id
    WHERE l.campaign_id = p_campaign_id
    LIMIT 1
  )
  INTO v_has_silver;

  IF v_has_silver THEN
    SELECT jsonb_build_object(
      'type', 'FeatureCollection',
      'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
    )
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'type', 'Feature',
        'id', l.building_id,
        'geometry', ST_AsGeoJSON(b.geom, 6)::jsonb,
        'properties', jsonb_build_object(
          'id', l.building_id,
          'building_id', l.building_id,
          'gers_id', l.building_id,
          'source', 'silver',
          'address_id', ca.id::text,
          'address_text', ca.formatted,
          'house_number', ca.house_number,
          'street_name', ca.street_name,
          'height', COALESCE(b.height_m, b.height, 10),
          'height_m', COALESCE(b.height_m, b.height, 10),
          'min_height', 0,
          'is_townhome', COALESCE(b.is_townhome_row, false),
          'units_count', COALESCE(b.units_count, 1),
          'match_method', l.match_type,
          'feature_type', 'matched_house',
          'feature_status', 'matched',
          'is_linked', true,
          'status', COALESCE(
            s.status,
            CASE b.latest_status
              WHEN 'interested' THEN 'visited'
              WHEN 'default' THEN 'not_visited'
              ELSE 'not_visited'
            END
          ),
          'scans_today', COALESCE(s.scans_today, 0),
          'scans_total', COALESCE(s.scans_total, 0)
        )
      ) AS feature
      FROM public.building_address_links l
      JOIN public.campaign_addresses ca
        ON ca.id = l.address_id
      JOIN public.buildings b
        ON b.gers_id = l.building_id
       AND b.campaign_id = p_campaign_id
      LEFT JOIN public.building_stats s
        ON s.gers_id = l.building_id
      WHERE l.campaign_id = p_campaign_id
    ) f;
  END IF;

  RETURN COALESCE(v_result, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_renderable_buildings(uuid) TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_full_features(
  p_campaign_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buildings jsonb := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  v_building_count integer := 0;
  v_result jsonb;
BEGIN
  v_buildings := COALESCE(public.rpc_get_campaign_renderable_buildings(p_campaign_id), v_buildings);
  v_building_count := COALESCE(jsonb_array_length(v_buildings->'features'), 0);

  IF v_building_count > 0 THEN
    RETURN v_buildings;
  END IF;

  SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
  )
  INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'type', 'Feature',
      'id', ca.id::text,
      'geometry', ST_AsGeoJSON(ca.geom, 6)::jsonb,
      'properties', jsonb_build_object(
        'id', ca.id::text,
        'address_id', ca.id::text,
        'source', 'address_point',
        'feature_type', 'address_point',
        'feature_status', 'address_point',
        'address_text', ca.formatted,
        'house_number', ca.house_number,
        'street_name', ca.street_name,
        'height', 5,
        'height_m', 5,
        'min_height', 0,
        'status', 'not_visited',
        'scans_today', 0,
        'scans_total', 0
      )
    ) AS feature
    FROM public.campaign_addresses ca
    WHERE ca.campaign_id = p_campaign_id
      AND ca.geom IS NOT NULL
  ) f;

  RETURN COALESCE(v_result, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_full_features(uuid) TO authenticated, service_role, anon;

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_map_bundle(p_campaign_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign record;
  v_addresses jsonb := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  v_buildings jsonb := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  v_parcels jsonb := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  v_roads jsonb := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  v_address_count integer := 0;
  v_building_count integer := 0;
  v_parcel_count integer := 0;
  v_road_count integer := 0;
  v_updated_at timestamptz;
BEGIN
  SELECT
    c.id,
    c.provision_status,
    c.provision_phase,
    c.provision_source,
    c.region,
    c.updated_at,
    c.addresses_ready_at,
    c.map_ready_at,
    c.optimized_at
  INTO v_campaign
  FROM public.campaigns c
  WHERE c.id = p_campaign_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'campaign_id', p_campaign_id,
      'status', 'not_found',
      'phase', 'not_found',
      'map_ready', false,
      'addresses', v_addresses,
      'buildings', v_buildings,
      'parcels', v_parcels,
      'roads', v_roads,
      'counts', jsonb_build_object('addresses', 0, 'buildings', 0, 'parcels', 0, 'roads', 0),
      'updated_at', now()
    );
  END IF;

  BEGIN
    v_addresses := COALESCE(public.rpc_get_campaign_addresses(p_campaign_id), v_addresses);
  EXCEPTION WHEN OTHERS THEN
    v_addresses := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  END;

  BEGIN
    v_buildings := COALESCE(public.rpc_get_campaign_renderable_buildings(p_campaign_id), v_buildings);
  EXCEPTION WHEN OTHERS THEN
    v_buildings := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  END;

  BEGIN
    v_parcels := COALESCE(public.rpc_get_campaign_parcels(p_campaign_id), v_parcels);
  EXCEPTION WHEN OTHERS THEN
    v_parcels := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  END;

  BEGIN
    v_roads := COALESCE(public.rpc_get_campaign_roads_v2(p_campaign_id), v_roads);
  EXCEPTION WHEN OTHERS THEN
    v_roads := jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb);
  END;

  v_address_count := COALESCE(jsonb_array_length(v_addresses->'features'), 0);
  v_building_count := COALESCE(jsonb_array_length(v_buildings->'features'), 0);
  v_parcel_count := COALESCE(jsonb_array_length(v_parcels->'features'), 0);
  v_road_count := COALESCE(jsonb_array_length(v_roads->'features'), 0);

  SELECT GREATEST(
    COALESCE(v_campaign.updated_at, '-infinity'::timestamptz),
    COALESCE(v_campaign.addresses_ready_at, '-infinity'::timestamptz),
    COALESCE(v_campaign.map_ready_at, '-infinity'::timestamptz),
    COALESCE(v_campaign.optimized_at, '-infinity'::timestamptz),
    COALESCE((SELECT max(ca.created_at) FROM public.campaign_addresses ca WHERE ca.campaign_id = p_campaign_id), '-infinity'::timestamptz),
    COALESCE((SELECT max(cp.created_at) FROM public.campaign_parcels cp WHERE cp.campaign_id = p_campaign_id), '-infinity'::timestamptz)
  )
  INTO v_updated_at;

  IF v_updated_at = '-infinity'::timestamptz THEN
    v_updated_at := now();
  END IF;

  RETURN jsonb_build_object(
    'campaign_id', p_campaign_id,
    'status', COALESCE(v_campaign.provision_status::text, 'pending'),
    'phase', COALESCE(v_campaign.provision_phase::text, v_campaign.provision_status::text, 'pending'),
    'source', COALESCE(v_campaign.provision_source::text, 'unknown'),
    'region', v_campaign.region,
    'map_ready', v_address_count > 0 OR v_building_count > 0 OR v_parcel_count > 0 OR COALESCE(v_campaign.map_ready_at, v_campaign.optimized_at) IS NOT NULL,
    'addresses', v_addresses,
    'buildings', v_buildings,
    'parcels', v_parcels,
    'roads', v_roads,
    'counts', jsonb_build_object(
      'addresses', v_address_count,
      'buildings', v_building_count,
      'parcels', v_parcel_count,
      'roads', v_road_count
    ),
    'updated_at', v_updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_map_bundle(uuid) TO authenticated, anon, service_role;

COMMENT ON FUNCTION public.rpc_get_campaign_renderable_buildings(uuid) IS
'Returns only renderable Polygon/MultiPolygon campaign building GeoJSON. Gold links may come from campaign_addresses.building_id or legacy building_gers_id.';

COMMENT ON FUNCTION public.rpc_get_campaign_full_features(uuid) IS
'Returns renderable campaign building polygons when linked, otherwise address-point features for legacy direct callers.';

COMMENT ON FUNCTION public.rpc_get_campaign_map_bundle(uuid) IS
'Unified campaign map bundle. The buildings collection is renderable building geometry only; address points are returned in addresses.';

NOTIFY pgrst, 'reload schema';

COMMIT;
