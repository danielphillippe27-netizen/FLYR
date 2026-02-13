-- Add building_gers_id to rpc_get_campaign_addresses so addresses that only have
-- building_gers_id (e.g. second address per building) can still link to the 3D building.
-- iOS uses gers_id or building_gers_id to call updateBuildingState(gersId).

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_addresses(
    p_campaign_id uuid
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', a.id,
            'geometry', ST_AsGeoJSON(a.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', a.id,
                'gers_id', a.gers_id,
                'building_gers_id', a.building_gers_id,
                'house_number', a.house_number,
                'street_name', a.street_name,
                'postal_code', a.postal_code,
                'locality', a.locality,
                'formatted', a.formatted
            )
        ) AS feature
        FROM public.campaign_addresses a
        WHERE a.campaign_id = p_campaign_id
    ) features;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_addresses(uuid) TO authenticated, service_role, anon;

COMMENT ON FUNCTION public.rpc_get_campaign_addresses IS
'Returns GeoJSON FeatureCollection of all addresses for a campaign. Properties include gers_id and building_gers_id so iOS can link every address to its building for status colors.';
