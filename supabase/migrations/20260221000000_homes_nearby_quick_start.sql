-- Quick Start: nearby homes RPC for loading homes around current location.
-- Uses Gold reference addresses and PostGIS distance query.

CREATE OR REPLACE FUNCTION public.homes_nearby(
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    radius_m INTEGER DEFAULT 500,
    limit_n INTEGER DEFAULT 300,
    p_workspace_id UUID DEFAULT NULL
)
RETURNS TABLE (
    address_id UUID,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    display_address TEXT,
    distance_m DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    WITH args AS (
        SELECT
            ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography AS center_geog,
            GREATEST(COALESCE(radius_m, 500), 1)::DOUBLE PRECISION AS radius_limit,
            LEAST(GREATEST(COALESCE(limit_n, 300), 1), 1000)::INTEGER AS row_limit
    )
    SELECT
        a.id AS address_id,
        ST_Y(a.geom::geometry) AS lat,
        ST_X(a.geom::geometry) AS lng,
        COALESCE(
            NULLIF(
                concat_ws(', ',
                    NULLIF(trim(concat_ws(' ',
                        NULLIF(a.street_number, ''),
                        NULLIF(a.street_name, ''),
                        NULLIF(a.unit, '')
                    )), ''),
                    NULLIF(a.city, ''),
                    NULLIF(a.province, ''),
                    NULLIF(a.country, '')
                ),
                ''
            ),
            a.source_id,
            a.id::text
        ) AS display_address,
        ST_Distance(a.geom::geography, args.center_geog) AS distance_m
    FROM public.ref_addresses_gold a
    CROSS JOIN args
    WHERE auth.uid() IS NOT NULL
      AND (p_workspace_id IS NULL OR public.is_workspace_member(p_workspace_id))
      AND a.geom IS NOT NULL
      AND ST_DWithin(a.geom::geography, args.center_geog, args.radius_limit)
    ORDER BY distance_m ASC, a.id
    LIMIT (SELECT row_limit FROM args);
$$;

GRANT EXECUTE ON FUNCTION public.homes_nearby(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, INTEGER, UUID)
    TO authenticated, service_role;

COMMENT ON FUNCTION public.homes_nearby(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, INTEGER, UUID)
IS 'Returns nearby homes from ref_addresses_gold within a radius (meters), sorted by distance, for Quick Start.';

NOTIFY pgrst, 'reload schema';
