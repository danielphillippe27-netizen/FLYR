BEGIN;

ALTER TABLE public.buildings
  DROP CONSTRAINT IF EXISTS buildings_gers_id_key;

ALTER TABLE public.buildings
  ALTER COLUMN geom TYPE GEOMETRY(MultiPolygon, 4326)
  USING ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))::GEOMETRY(MultiPolygon, 4326);

CREATE UNIQUE INDEX IF NOT EXISTS idx_buildings_campaign_gers_id_unique
  ON public.buildings(campaign_id, gers_id)
  WHERE campaign_id IS NOT NULL
    AND gers_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.materialize_campaign_buildings_from_geojson(
  p_campaign_id UUID,
  p_features JSONB,
  p_source TEXT DEFAULT 'campaign_snapshot'
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_workspace_id UUID;
BEGIN
  SELECT c.workspace_id
  INTO v_workspace_id
  FROM public.campaigns c
  WHERE c.id = p_campaign_id;

  WITH raw_features AS (
    SELECT value AS feature
    FROM jsonb_array_elements(
      CASE
        WHEN jsonb_typeof(p_features) = 'array' THEN p_features
        WHEN jsonb_typeof(p_features -> 'features') = 'array' THEN p_features -> 'features'
        ELSE '[]'::jsonb
      END
    )
  ),
  parsed AS (
    SELECT
      NULLIF(
        BTRIM(
          COALESCE(
            feature -> 'properties' ->> 'public_building_id',
            feature -> 'properties' ->> 'canonical_building_id',
            feature -> 'properties' ->> 'building_id',
            feature -> 'properties' ->> 'gers_id',
            feature -> 'properties' ->> 'id',
            feature ->> 'id'
          )
        ),
        ''
      ) AS external_id,
      CASE
        WHEN feature ? 'geometry'
          AND (feature -> 'geometry' ->> 'type') IN ('Polygon', 'MultiPolygon')
        THEN ST_Multi(
          ST_CollectionExtract(
            ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON((feature -> 'geometry')::TEXT), 4326)),
            3
          )
        )::GEOMETRY(MultiPolygon, 4326)
        ELSE NULL::GEOMETRY(MultiPolygon, 4326)
      END AS geom,
      CASE
        WHEN COALESCE(
          feature -> 'properties' ->> 'height_m',
          feature -> 'properties' ->> 'height'
        ) ~ '^-?[0-9]+(\.[0-9]+)?$'
        THEN COALESCE(
          feature -> 'properties' ->> 'height_m',
          feature -> 'properties' ->> 'height'
        )::NUMERIC
        ELSE NULL::NUMERIC
      END AS height_m,
      CASE
        WHEN feature -> 'properties' ->> 'units_count' ~ '^[0-9]+$'
        THEN GREATEST((feature -> 'properties' ->> 'units_count')::INTEGER, 1)
        WHEN feature -> 'properties' ->> 'unit_count' ~ '^[0-9]+$'
        THEN GREATEST((feature -> 'properties' ->> 'unit_count')::INTEGER, 1)
        ELSE 1
      END AS units_count
    FROM raw_features
  ),
  clean AS (
    SELECT DISTINCT ON (external_id)
      external_id,
      geom,
      height_m,
      units_count
    FROM parsed
    WHERE external_id IS NOT NULL
      AND geom IS NOT NULL
      AND NOT ST_IsEmpty(geom)
    ORDER BY external_id, ST_Area(geom::geography) DESC NULLS LAST
  ),
  upserted AS (
    INSERT INTO public.buildings (
      campaign_id,
      gers_id,
      geom,
      centroid,
      height_m,
      height,
      is_townhome_row,
      units_count,
      workspace_id,
      updated_at
    )
    SELECT
      p_campaign_id,
      external_id,
      geom,
      ST_Centroid(geom),
      height_m,
      height_m,
      units_count > 1,
      units_count,
      v_workspace_id,
      NOW()
    FROM clean
    ON CONFLICT (campaign_id, gers_id)
      WHERE campaign_id IS NOT NULL
        AND gers_id IS NOT NULL
    DO UPDATE
    SET
      geom = EXCLUDED.geom,
      centroid = EXCLUDED.centroid,
      height_m = EXCLUDED.height_m,
      height = EXCLUDED.height,
      is_townhome_row = EXCLUDED.is_townhome_row,
      units_count = EXCLUDED.units_count,
      updated_at = NOW()
    RETURNING id
  )
  SELECT COUNT(*)
  INTO v_count
  FROM upserted;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.materialize_campaign_buildings_from_geojson(UUID, JSONB, TEXT)
TO service_role;

COMMENT ON FUNCTION public.materialize_campaign_buildings_from_geojson(UUID, JSONB, TEXT) IS
'Materializes campaign-scoped Diamond/Bedrock building GeoJSON into public.buildings so backend PostGIS linking can join campaign_addresses to canonical building rows.';

NOTIFY pgrst, 'reload schema';

COMMIT;
