BEGIN;

CREATE OR REPLACE FUNCTION public.get_addresses_in_polygon(
    p_polygon_geojson text
)
RETURNS TABLE (
    id uuid,
    campaign_id uuid,
    formatted text,
    postal_code text,
    source text,
    seq integer,
    visited boolean,
    geom_json jsonb,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_polygon geometry;
BEGIN
    v_polygon := ST_SetSRID(ST_GeomFromGeoJSON(p_polygon_geojson), 4326);

    RETURN QUERY
    SELECT
        ca.id,
        ca.campaign_id,
        ca.formatted,
        ca.postal_code,
        ca.source,
        ca.seq,
        ca.visited,
        ST_AsGeoJSON(ca.geom, 6)::jsonb AS geom_json,
        ca.created_at
    FROM public.campaign_addresses ca
    WHERE ca.geom IS NOT NULL
      AND ST_Covers(v_polygon, ca.geom)
    ORDER BY ca.seq NULLS LAST, ca.created_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_campaign_addresses_in_polygon(
    p_polygon_geojson text,
    p_campaign_id uuid
)
RETURNS TABLE (
    id uuid,
    campaign_id uuid,
    formatted text,
    postal_code text,
    source text,
    seq integer,
    visited boolean,
    geom_json jsonb,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_polygon geometry;
BEGIN
    v_polygon := ST_SetSRID(ST_GeomFromGeoJSON(p_polygon_geojson), 4326);

    RETURN QUERY
    SELECT
        ca.id,
        ca.campaign_id,
        ca.formatted,
        ca.postal_code,
        ca.source,
        ca.seq,
        ca.visited,
        ST_AsGeoJSON(ca.geom, 6)::jsonb AS geom_json,
        ca.created_at
    FROM public.campaign_addresses ca
    WHERE ca.geom IS NOT NULL
      AND ca.campaign_id = p_campaign_id
      AND ST_Covers(v_polygon, ca.geom)
    ORDER BY ca.seq NULLS LAST, ca.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_addresses_in_polygon(text) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.get_campaign_addresses_in_polygon(text, uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.get_addresses_in_polygon(text) IS
'Returns campaign address rows inside a GeoJSON polygon for farm and territory workflows. Output matches the iOS CampaignAddressViewRow contract.';

COMMENT ON FUNCTION public.get_campaign_addresses_in_polygon(text, uuid) IS
'Returns campaign address rows for a single campaign inside a GeoJSON polygon. Output matches the iOS CampaignAddressViewRow contract.';

COMMIT;
