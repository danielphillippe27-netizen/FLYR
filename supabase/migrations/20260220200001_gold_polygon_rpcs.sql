-- Gold polygon query RPCs: address and building lookup by polygon.
-- SECURITY DEFINER so callers don't need direct table access.
-- get_gold_addresses_in_polygon_geojson: called by provision backend (service role).
-- get_gold_buildings_in_polygon_geojson: called by provision backend (service role).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. get_gold_addresses_in_polygon_geojson
-- Returns ref_addresses_gold rows within a GeoJSON polygon as a JSON array.
-- Optional province filter to reduce scan range on large datasets.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_gold_addresses_in_polygon_geojson(text, text);
CREATE OR REPLACE FUNCTION public.get_gold_addresses_in_polygon_geojson(
    p_polygon_geojson TEXT,
    p_province        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_polygon GEOMETRY;
    v_result  JSONB;
BEGIN
    v_polygon := ST_GeomFromGeoJSON(p_polygon_geojson);

    SELECT COALESCE(jsonb_agg(row_to_json(a)::jsonb), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            id,
            source_id,
            street_number,
            street_name,
            unit,
            city,
            zip,
            province,
            country,
            address_type,
            precision,
            street_number_normalized,
            street_name_normalized,
            zip_normalized,
            ST_AsGeoJSON(geom)::jsonb AS geom_geojson
        FROM public.ref_addresses_gold
        WHERE ST_Within(geom, v_polygon)
          AND (p_province IS NULL OR province = p_province)
        ORDER BY street_name_normalized, street_number_normalized
    ) a;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_gold_addresses_in_polygon_geojson(text, text) IS
'Returns ref_addresses_gold rows inside a GeoJSON polygon as a JSON array. Used by provision to decide Gold vs Lambda path.';

-- ---------------------------------------------------------------------------
-- 2. get_gold_buildings_in_polygon_geojson
-- Returns ref_buildings_gold rows intersecting a GeoJSON polygon as a
-- GeoJSON FeatureCollection. Each feature has source: ''gold''.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_gold_buildings_in_polygon_geojson(text);
CREATE OR REPLACE FUNCTION public.get_gold_buildings_in_polygon_geojson(
    p_polygon_geojson TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_polygon GEOMETRY;
    v_result  JSONB;
BEGIN
    v_polygon := ST_GeomFromGeoJSON(p_polygon_geojson);

    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
    )
    INTO v_result
    FROM (
        SELECT jsonb_build_object(
            'type',       'Feature',
            'id',         b.id,
            'geometry',   ST_AsGeoJSON(b.geom)::jsonb,
            'properties', jsonb_build_object(
                'id',                    b.id,
                'source_id',             b.source_id,
                'external_id',           b.external_id,
                'area_sqm',              b.area_sqm,
                'height_m',              b.height_m,
                'floors',                b.floors,
                'year_built',            b.year_built,
                'building_type',         b.building_type,
                'subtype',               b.subtype,
                'primary_address',       b.primary_address,
                'primary_street_number', b.primary_street_number,
                'primary_street_name',   b.primary_street_name,
                'source',                'gold'
            )
        ) AS feature
        FROM public.ref_buildings_gold b
        WHERE ST_Intersects(b.geom, v_polygon)
    ) f;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_gold_buildings_in_polygon_geojson(text) IS
'Returns ref_buildings_gold features intersecting a GeoJSON polygon as a FeatureCollection. Used by provision (Gold path) and BuildingAdapter.fromGoldRows.';

COMMIT;
