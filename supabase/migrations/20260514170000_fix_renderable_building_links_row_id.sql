BEGIN;

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
          'is_townhome', COUNT(ca.id) > 1,
          'units_count', GREATEST(COUNT(ca.id), 1),
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
      ON b.id = l.building_id
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
        'id', COALESCE(b.gers_id, b.id::text),
        'geometry', ST_AsGeoJSON(b.geom, 6)::jsonb,
        'properties', jsonb_build_object(
          'id', COALESCE(b.gers_id, b.id::text),
          'building_id', b.id::text,
          'gers_id', COALESCE(b.gers_id, b.id::text),
          'source', 'silver',
          'address_count', COUNT(ca.id),
          'address_id', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.id)::text ELSE NULL END,
          'address_text', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.formatted) ELSE NULL END,
          'house_number', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.house_number) ELSE NULL END,
          'street_name', CASE WHEN COUNT(ca.id) = 1 THEN MIN(ca.street_name) ELSE NULL END,
          'height', COALESCE(b.height_m, b.height, 10),
          'height_m', COALESCE(b.height_m, b.height, 10),
          'min_height', 0,
          'is_townhome', COUNT(ca.id) > 1 OR COALESCE(b.is_townhome_row, false),
          'units_count', GREATEST(COUNT(ca.id), COALESCE(b.units_count, 1), 1),
          'match_method', (ARRAY_AGG(l.match_type ORDER BY l.confidence DESC NULLS LAST))[1],
          'confidence', MAX(l.confidence),
          'feature_type', 'matched_house',
          'feature_status', 'matched',
          'is_linked', true,
          'status', COALESCE(
            MIN(s.status),
            CASE b.latest_status
              WHEN 'interested' THEN 'visited'
              WHEN 'default' THEN 'not_visited'
              ELSE 'not_visited'
            END
          ),
          'scans_today', COALESCE(SUM(s.scans_today), 0),
          'scans_total', COALESCE(SUM(s.scans_total), 0)
        )
      ) AS feature
      FROM public.building_address_links l
      JOIN public.campaign_addresses ca
        ON ca.id = l.address_id
      JOIN public.buildings b
        ON b.id = l.building_id
       AND b.campaign_id = p_campaign_id
      LEFT JOIN public.building_stats s
        ON s.gers_id = COALESCE(b.gers_id, b.id::text)
      WHERE l.campaign_id = p_campaign_id
      GROUP BY b.id, b.gers_id, b.geom, b.height_m, b.height, b.is_townhome_row, b.units_count, b.latest_status
    ) f;
  END IF;

  RETURN COALESCE(v_result, jsonb_build_object('type', 'FeatureCollection', 'features', '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_renderable_buildings(uuid) TO authenticated, anon, service_role;

COMMIT;
