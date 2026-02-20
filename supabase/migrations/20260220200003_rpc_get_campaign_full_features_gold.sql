-- Replaces rpc_get_campaign_full_features with a Gold-first unified implementation.
--
-- Priority order:
--   1. Gold path  — campaign_addresses have building_id → ref_buildings_gold polygons.
--   2. Silver path — building_address_links + buildings table rows (Overture/Lambda).
--   3. address_point fallback — no building links; emit address centroids as Point features.
--
-- iOS MapFeaturesService partitions the response:
--   Polygon/MultiPolygon features  → buildings layer (3D extrusion)
--   Point features (address_point) → addresses layer (coloured circles)

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_full_features(
    p_campaign_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_has_gold    BOOLEAN;
    v_has_silver  BOOLEAN;
    v_result      JSONB;
BEGIN
    -- Check which path applies.
    SELECT EXISTS (
        SELECT 1 FROM public.campaign_addresses
        WHERE campaign_id = p_campaign_id AND building_id IS NOT NULL
        LIMIT 1
    ) INTO v_has_gold;

    IF NOT v_has_gold THEN
        SELECT EXISTS (
            SELECT 1 FROM public.building_address_links
            WHERE campaign_id = p_campaign_id
            LIMIT 1
        ) INTO v_has_silver;
    END IF;

    -- -------------------------------------------------------------------------
    -- Gold path: ref_buildings_gold polygons, one feature per building.
    -- Multi-address buildings: address_id = NULL, address_count > 1.
    -- Single-address buildings: address_id = the linked address UUID.
    -- -------------------------------------------------------------------------
    IF v_has_gold THEN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
        )
        INTO v_result
        FROM (
            SELECT jsonb_build_object(
                'type',       'Feature',
                'id',         b.id::text,
                'geometry',   ST_AsGeoJSON(b.geom, 6)::jsonb,
                'properties', jsonb_build_object(
                    'id',            b.id::text,
                    'building_id',   b.id::text,
                    'source',        'gold',
                    'address_count', COUNT(ca.id),
                    'address_id',    CASE WHEN COUNT(ca.id) = 1
                                         THEN MIN(ca.id)::text
                                         ELSE NULL END,
                    'address_text',  CASE WHEN COUNT(ca.id) = 1
                                         THEN MIN(ca.formatted)
                                         ELSE NULL END,
                    'height',        COALESCE(b.height_m, 10),
                    'height_m',      COALESCE(b.height_m, 10),
                    'min_height',    0,
                    'area_sqm',      b.area_sqm,
                    'building_type', b.building_type,
                    'feature_type',  'matched_house',
                    'feature_status','matched',
                    'status',        COALESCE(
                        MIN(s.status),
                        'not_visited'
                    ),
                    'scans_today',   COALESCE(SUM(s.scans_today), 0),
                    'scans_total',   COALESCE(SUM(s.scans_total), 0)
                )
            ) AS feature
            FROM public.campaign_addresses ca
            JOIN public.ref_buildings_gold b ON b.id = ca.building_id
            LEFT JOIN public.building_stats s ON s.gers_id = b.id::text
            WHERE ca.campaign_id = p_campaign_id
              AND ca.building_id IS NOT NULL
            GROUP BY b.id, b.geom, b.height_m, b.area_sqm, b.building_type
        ) f;

    -- -------------------------------------------------------------------------
    -- Silver path: building_address_links + buildings table.
    -- -------------------------------------------------------------------------
    ELSIF v_has_silver THEN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
        )
        INTO v_result
        FROM (
            SELECT jsonb_build_object(
                'type',       'Feature',
                'id',         l.building_id,
                'geometry',   ST_AsGeoJSON(b.geom, 6)::jsonb,
                'properties', jsonb_build_object(
                    'id',            l.building_id,
                    'building_id',   l.building_id,
                    'gers_id',       l.building_id,
                    'source',        'silver',
                    'address_id',    ca.id::text,
                    'address_text',  ca.formatted,
                    'house_number',  ca.house_number,
                    'street_name',   ca.street_name,
                    'height',        COALESCE(b.height_m, b.height, 10),
                    'height_m',      COALESCE(b.height_m, b.height, 10),
                    'min_height',    0,
                    'is_townhome',   COALESCE(b.is_townhome_row, false),
                    'units_count',   COALESCE(b.units_count, 1),
                    'match_method',  l.match_type,
                    'feature_type',  'matched_house',
                    'feature_status','matched',
                    'status',        COALESCE(
                        s.status,
                        CASE b.latest_status
                            WHEN 'interested' THEN 'visited'
                            WHEN 'default'    THEN 'not_visited'
                            ELSE 'not_visited'
                        END
                    ),
                    'scans_today',   COALESCE(s.scans_today, 0),
                    'scans_total',   COALESCE(s.scans_total, 0)
                )
            ) AS feature
            FROM public.building_address_links l
            JOIN public.campaign_addresses ca ON ca.id = l.address_id
            LEFT JOIN public.buildings b ON b.gers_id = l.building_id
                                        AND b.campaign_id = p_campaign_id
            LEFT JOIN public.building_stats s ON s.gers_id = l.building_id
            WHERE l.campaign_id = p_campaign_id
              AND b.id IS NOT NULL  -- only emit when polygon exists in buildings table
        ) f;

    -- -------------------------------------------------------------------------
    -- address_point fallback: no building links at all.
    -- -------------------------------------------------------------------------
    ELSE
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', COALESCE(jsonb_agg(f.feature), '[]'::jsonb)
        )
        INTO v_result
        FROM (
            SELECT jsonb_build_object(
                'type',       'Feature',
                'id',         ca.id::text,
                'geometry',   ST_AsGeoJSON(ca.geom, 6)::jsonb,
                'properties', jsonb_build_object(
                    'id',            ca.id::text,
                    'address_id',    ca.id::text,
                    'source',        'address_point',
                    'feature_type',  'address_point',
                    'feature_status','address_point',
                    'address_text',  ca.formatted,
                    'house_number',  ca.house_number,
                    'street_name',   ca.street_name,
                    'height',        5,
                    'height_m',      5,
                    'min_height',    0,
                    'status',        'not_visited',
                    'scans_today',   0,
                    'scans_total',   0
                )
            ) AS feature
            FROM public.campaign_addresses ca
            WHERE ca.campaign_id = p_campaign_id
              AND ca.geom IS NOT NULL
        ) f;
    END IF;

    -- Guard: if no addresses at all return empty collection.
    IF v_result IS NULL THEN
        v_result := '{"type":"FeatureCollection","features":[]}'::jsonb;
    END IF;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_full_features(uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_campaign_full_features(uuid) IS
'Returns a GeoJSON FeatureCollection for a campaign. Gold path (building_id set) → Silver path (building_address_links + buildings) → address_point fallback. source property = ''gold'' | ''silver'' | ''address_point''.';

NOTIFY pgrst, 'reload schema';
