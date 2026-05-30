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
  WITH counts AS (
    SELECT
      building_id,
      GREATEST(COUNT(DISTINCT address_id), 1)::INTEGER AS unit_count
    FROM public.building_address_links
    WHERE campaign_id = p_campaign_id
      AND building_id IS NOT NULL
      AND address_id IS NOT NULL
    GROUP BY building_id
  ),
  updated AS (
    UPDATE public.building_address_links AS bal
    SET
      is_multi_unit = counts.unit_count > 1,
      unit_count = counts.unit_count,
      unit_arrangement = CASE WHEN counts.unit_count > 1 THEN 'horizontal' ELSE 'single' END,
      building_class = CASE WHEN counts.unit_count > 1 THEN 'multi_unit' ELSE NULL END
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

GRANT EXECUTE ON FUNCTION public.refresh_grouped_building_link_classifications(UUID)
TO authenticated, service_role;

COMMENT ON FUNCTION public.refresh_grouped_building_link_classifications(UUID) IS
  'Bulk-refreshes unit_count/is_multi_unit/building_class for all auto-linked building rows in one database update.';
