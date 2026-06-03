BEGIN;

CREATE OR REPLACE FUNCTION public.flyr_normalized_map_address_part(
  p_value TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_value TEXT;
BEGIN
  IF p_value IS NULL OR BTRIM(p_value) = '' THEN
    RETURN NULL;
  END IF;

  v_value := LOWER(BTRIM(p_value));
  v_value := REGEXP_REPLACE(v_value, '\mavenue\.?\M', 'ave', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mave\.?\M', 'ave', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mstreet\.?\M', 'st', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mst\.?\M', 'st', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mdrive\.?\M', 'dr', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mdr\.?\M', 'dr', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mboulevard\.?\M', 'blvd', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mblvd\.?\M', 'blvd', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mroad\.?\M', 'rd', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mrd\.?\M', 'rd', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mlane\.?\M', 'ln', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mln\.?\M', 'ln', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mcourt\.?\M', 'ct', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mct\.?\M', 'ct', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mplace\.?\M', 'pl', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mpl\.?\M', 'pl', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mcircle\.?\M', 'cir', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mcir\.?\M', 'cir', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mparkway\.?\M', 'pkwy', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mpkwy\.?\M', 'pkwy', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mhighway\.?\M', 'hwy', 'g');
  v_value := REGEXP_REPLACE(v_value, '\mhwy\.?\M', 'hwy', 'g');
  v_value := REPLACE(v_value, '&', ' and ');
  v_value := REGEXP_REPLACE(v_value, '[^a-z0-9#-]+', ' ', 'g');
  v_value := REGEXP_REPLACE(v_value, '\s+', ' ', 'g');

  RETURN NULLIF(BTRIM(v_value), '');
END;
$$;

CREATE OR REPLACE FUNCTION public.flyr_map_address_display_identity(
  p_house_number TEXT,
  p_street_name TEXT,
  p_formatted TEXT,
  p_locality TEXT,
  p_postal_code TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_formatted TEXT := NULLIF(BTRIM(COALESCE(p_formatted, '')), '');
  v_line TEXT;
  v_unit_match TEXT[];
  v_house TEXT;
  v_street_source TEXT;
  v_street TEXT;
  v_unit TEXT;
  v_fallback TEXT;
BEGIN
  v_line := NULLIF(BTRIM(SPLIT_PART(COALESCE(v_formatted, ''), ',', 1)), '');
  v_unit_match := REGEXP_MATCH(COALESCE(v_line, v_formatted, ''), '(\m(unit|apt|apartment|suite|ste)\s*|#\s*)([a-z0-9-]+)', 'i');

  v_house := COALESCE(
    public.flyr_normalized_map_address_part(p_house_number),
    public.flyr_normalized_map_address_part(SUBSTRING(COALESCE(v_line, '') FROM '^\s*([0-9]+[a-z0-9-]*)'))
  );
  v_unit := public.flyr_normalized_map_address_part(v_unit_match[3]);
  v_street_source := COALESCE(
    NULLIF(BTRIM(p_street_name), ''),
    REGEXP_REPLACE(
      REGEXP_REPLACE(COALESCE(v_line, ''), '^\s*[0-9]+[a-z0-9-]*\s*', '', 'i'),
      '(\m(unit|apt|apartment|suite|ste)\s*|#\s*)[a-z0-9-]+\M',
      ' ',
      'gi'
    )
  );
  v_street := public.flyr_normalized_map_address_part(v_street_source);
  IF v_house IS NOT NULL AND v_street IS NOT NULL THEN
    RETURN CONCAT_WS(
      '|',
      'h:' || v_house,
      's:' || v_street,
      'u:' || COALESCE(v_unit, '')
    );
  END IF;

  v_fallback := public.flyr_normalized_map_address_part(v_formatted);
  IF v_fallback IS NOT NULL THEN
    RETURN 'f:' || v_fallback;
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_grouped_building_link_classifications(
  p_campaign_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buildings INTEGER := 0;
  v_rows INTEGER := 0;
BEGIN
  WITH link_display_addresses AS (
    SELECT
      bal.building_id,
      bal.address_id,
      COALESCE(
        public.flyr_map_address_display_identity(
          ca.house_number,
          ca.street_name,
          ca.formatted,
          ca.locality,
          ca.postal_code
        ),
        bal.address_id::TEXT
      ) AS display_address_key
    FROM public.building_address_links bal
    LEFT JOIN public.campaign_addresses ca
      ON ca.id = bal.address_id
     AND ca.campaign_id = bal.campaign_id
    WHERE bal.campaign_id = p_campaign_id
      AND bal.building_id IS NOT NULL
      AND bal.address_id IS NOT NULL
  ),
  counts AS (
    SELECT
      building_id,
      GREATEST(COUNT(DISTINCT display_address_key), 1)::INTEGER AS unit_count
    FROM link_display_addresses
    GROUP BY building_id
  ),
  updated AS (
    UPDATE public.building_address_links AS bal
    SET
      is_multi_unit = counts.unit_count > 1,
      unit_count = counts.unit_count,
      unit_arrangement = CASE WHEN counts.unit_count > 1 THEN 'horizontal' ELSE 'single' END,
      building_class = CASE WHEN counts.unit_count > 1 THEN COALESCE(bal.building_class, 'multi_unit') ELSE NULL END
    FROM counts
    WHERE bal.campaign_id = p_campaign_id
      AND bal.building_id = counts.building_id
    RETURNING 1
  )
  SELECT
    (SELECT COUNT(*) FROM counts),
    (SELECT COUNT(*) FROM updated)
  INTO v_buildings, v_rows;

  RETURN jsonb_build_object(
    'buildings_classified', v_buildings,
    'rows_updated', v_rows
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.flyr_normalized_map_address_part(TEXT)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.flyr_map_address_display_identity(TEXT, TEXT, TEXT, TEXT, TEXT)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.refresh_grouped_building_link_classifications(UUID)
TO authenticated, service_role;

COMMENT ON FUNCTION public.flyr_map_address_display_identity(TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Normalizes campaign address display identity for bundle/link dedupe. Units parsed from formatted labels remain distinct.';

COMMENT ON FUNCTION public.refresh_grouped_building_link_classifications(UUID) IS
  'Bulk-refreshes unit_count/is_multi_unit/building_class using display-distinct campaign addresses, preserving raw address rows and manual links.';

NOTIFY pgrst, 'reload schema';

COMMIT;
