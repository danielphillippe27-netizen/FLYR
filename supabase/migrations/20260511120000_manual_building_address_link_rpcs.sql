-- Transaction-safe manual building/address assignment helpers.
-- PostgreSQL functions run atomically; any exception rolls back all side effects.

CREATE OR REPLACE FUNCTION public.assign_address_to_building_manual(
  p_campaign_id UUID,
  p_address_id UUID,
  p_building_row_id UUID,
  p_building_public_id TEXT,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_assigned_by UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_previous_building_ids UUID[] := ARRAY[]::UUID[];
  v_building_id UUID;
  v_linked_address_ids UUID[] := ARRAY[]::UUID[];
  v_unit_count INTEGER := 1;
BEGIN
  PERFORM 1
  FROM public.campaign_addresses
  WHERE campaign_id = p_campaign_id
    AND id = p_address_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Address % not found in campaign %', p_address_id, p_campaign_id;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT building_id), ARRAY[]::UUID[])
  INTO v_previous_building_ids
  FROM public.building_address_links
  WHERE campaign_id = p_campaign_id
    AND address_id = p_address_id;

  INSERT INTO public.building_address_links (
    campaign_id,
    building_id,
    address_id,
    match_type,
    confidence,
    distance_meters,
    street_match_score,
    is_multi_unit,
    unit_count,
    unit_arrangement
  )
  VALUES (
    p_campaign_id,
    p_building_row_id,
    p_address_id,
    'manual',
    1,
    0,
    1,
    false,
    1,
    'single'
  )
  ON CONFLICT (campaign_id, address_id) DO UPDATE
  SET building_id = EXCLUDED.building_id,
      match_type = EXCLUDED.match_type,
      confidence = EXCLUDED.confidence,
      distance_meters = EXCLUDED.distance_meters,
      street_match_score = EXCLUDED.street_match_score,
      unit_arrangement = EXCLUDED.unit_arrangement;

  UPDATE public.campaign_addresses
  SET building_id = p_building_row_id,
      building_gers_id = p_building_public_id,
      match_source = 'manual',
      confidence = 1,
      geom = CASE
        WHEN p_lon IS NOT NULL AND p_lat IS NOT NULL
        THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)
        ELSE geom
      END
  WHERE campaign_id = p_campaign_id
    AND id = p_address_id;

  IF to_regclass('public.address_orphans') IS NOT NULL THEN
    UPDATE public.address_orphans
    SET status = 'assigned',
        assigned_building_id = p_building_row_id,
        assigned_by = p_assigned_by,
        assigned_at = NOW()
    WHERE campaign_id = p_campaign_id
      AND address_id = p_address_id;
  END IF;

  FOREACH v_building_id IN ARRAY array_append(v_previous_building_ids, p_building_row_id)
  LOOP
    WITH linked AS (
      SELECT address_id
      FROM public.building_address_links
      WHERE campaign_id = p_campaign_id
        AND building_id = v_building_id
    ),
    counts AS (
      SELECT GREATEST(COUNT(*), 1)::INTEGER AS unit_count FROM linked
    )
    UPDATE public.building_address_links bal
    SET is_multi_unit = counts.unit_count > 1,
        unit_count = counts.unit_count,
        unit_arrangement = CASE WHEN counts.unit_count > 1 THEN 'horizontal' ELSE 'single' END
    FROM counts
    WHERE bal.campaign_id = p_campaign_id
      AND bal.building_id = v_building_id;
  END LOOP;

  SELECT COALESCE(array_agg(address_id ORDER BY address_id), ARRAY[]::UUID[])
  INTO v_linked_address_ids
  FROM (
    SELECT address_id
    FROM public.building_address_links
    WHERE campaign_id = p_campaign_id
      AND building_id = p_building_row_id
    UNION
    SELECT id AS address_id
    FROM public.campaign_addresses
    WHERE campaign_id = p_campaign_id
      AND (
        building_id::TEXT = p_building_row_id::TEXT
        OR building_id::TEXT = p_building_public_id
        OR building_gers_id = p_building_public_id
      )
  ) linked;

  v_unit_count := GREATEST(array_length(v_linked_address_ids, 1), 1);

  RETURN jsonb_build_object(
    'linked_address_ids', COALESCE(to_jsonb(v_linked_address_ids), '[]'::jsonb),
    'unit_count', v_unit_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.unassign_address_from_building_manual(
  p_campaign_id UUID,
  p_address_id UUID,
  p_building_row_id UUID,
  p_building_public_id TEXT,
  p_delete_manual_address BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_address_source TEXT;
  v_linked_address_ids UUID[] := ARRAY[]::UUID[];
  v_unit_count INTEGER := 1;
BEGIN
  SELECT source
  INTO v_address_source
  FROM public.campaign_addresses
  WHERE campaign_id = p_campaign_id
    AND id = p_address_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Address % not found in campaign %', p_address_id, p_campaign_id;
  END IF;

  DELETE FROM public.building_address_links
  WHERE campaign_id = p_campaign_id
    AND address_id = p_address_id
    AND building_id = p_building_row_id;

  IF p_delete_manual_address THEN
    IF COALESCE(v_address_source, '') <> 'manual' THEN
      RAISE EXCEPTION 'Only manual addresses can be deleted as units';
    END IF;

    DELETE FROM public.campaign_addresses
    WHERE campaign_id = p_campaign_id
      AND id = p_address_id
      AND source = 'manual';
  ELSE
    UPDATE public.campaign_addresses
    SET building_id = NULL,
        building_gers_id = NULL,
        match_source = NULL,
        confidence = NULL
    WHERE campaign_id = p_campaign_id
      AND id = p_address_id;

    IF to_regclass('public.address_orphans') IS NOT NULL THEN
      UPDATE public.address_orphans
      SET status = 'pending_review',
          assigned_building_id = NULL,
          assigned_by = NULL,
          assigned_at = NULL
      WHERE campaign_id = p_campaign_id
        AND address_id = p_address_id;
    END IF;
  END IF;

  WITH linked AS (
    SELECT address_id
    FROM public.building_address_links
    WHERE campaign_id = p_campaign_id
      AND building_id = p_building_row_id
  ),
  counts AS (
    SELECT GREATEST(COUNT(*), 1)::INTEGER AS unit_count FROM linked
  )
  UPDATE public.building_address_links bal
  SET is_multi_unit = counts.unit_count > 1,
      unit_count = counts.unit_count,
      unit_arrangement = CASE WHEN counts.unit_count > 1 THEN 'horizontal' ELSE 'single' END
  FROM counts
  WHERE bal.campaign_id = p_campaign_id
    AND bal.building_id = p_building_row_id;

  SELECT COALESCE(array_agg(address_id ORDER BY address_id), ARRAY[]::UUID[])
  INTO v_linked_address_ids
  FROM (
    SELECT address_id
    FROM public.building_address_links
    WHERE campaign_id = p_campaign_id
      AND building_id = p_building_row_id
    UNION
    SELECT id AS address_id
    FROM public.campaign_addresses
    WHERE campaign_id = p_campaign_id
      AND (
        building_id::TEXT = p_building_row_id::TEXT
        OR building_id::TEXT = p_building_public_id
        OR building_gers_id = p_building_public_id
      )
  ) linked;

  v_unit_count := GREATEST(array_length(v_linked_address_ids, 1), 1);

  RETURN jsonb_build_object(
    'linked_address_ids', COALESCE(to_jsonb(v_linked_address_ids), '[]'::jsonb),
    'unit_count', v_unit_count,
    'deleted_address_id', CASE WHEN p_delete_manual_address THEN p_address_id::TEXT ELSE NULL::TEXT END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_address_to_building_manual(UUID, UUID, UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.unassign_address_from_building_manual(UUID, UUID, UUID, TEXT, BOOLEAN) TO service_role;

NOTIFY pgrst, 'reload schema';
