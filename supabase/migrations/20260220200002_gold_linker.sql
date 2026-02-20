-- Gold address linker: link_campaign_addresses_gold(campaign_id, polygon_geojson)
-- Sets campaign_addresses.building_id to the matching ref_buildings_gold.id for each address.
-- Pass 1: exact containment (point inside polygon). confidence = 1.0.
-- Pass 2: proximity within 30 m for still-unlinked addresses. confidence = 1 - (distance_m / 30).

BEGIN;

CREATE OR REPLACE FUNCTION public.link_campaign_addresses_gold(
    p_campaign_id     UUID,
    p_polygon_geojson TEXT
)
RETURNS TABLE(linked_exact INTEGER, linked_proximity INTEGER, total_linked INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_exact_count     INTEGER := 0;
    v_proximity_count INTEGER := 0;
BEGIN
    -- -------------------------------------------------------------------------
    -- Pass 1: Exact — address point is ST_Within a Gold building polygon.
    -- -------------------------------------------------------------------------
    WITH exact AS (
        UPDATE public.campaign_addresses ca
        SET
            building_id  = b.id,
            match_source = 'gold_exact',
            confidence   = 1.0
        FROM public.ref_buildings_gold b
        WHERE ca.campaign_id  = p_campaign_id
          AND ca.building_id  IS NULL
          AND ca.geom         IS NOT NULL
          AND b.geom          IS NOT NULL
          AND ST_Within(ca.geom, b.geom)
        RETURNING ca.id
    )
    SELECT COUNT(*) INTO v_exact_count FROM exact;

    -- -------------------------------------------------------------------------
    -- Pass 2: Proximity — nearest Gold building within 30 m for still-unlinked.
    -- -------------------------------------------------------------------------
    WITH proximity AS (
        UPDATE public.campaign_addresses ca
        SET
            building_id  = nearest.id,
            match_source = 'gold_proximity',
            confidence   = GREATEST(0, 1.0 - (nearest.dist_m / 30.0))
        FROM (
            SELECT DISTINCT ON (ca2.id)
                ca2.id       AS address_id,
                b2.id        AS id,
                ST_Distance(
                    ST_Transform(ca2.geom, 3857),
                    ST_Transform(b2.geom,  3857)
                )            AS dist_m
            FROM public.campaign_addresses ca2
            CROSS JOIN LATERAL (
                SELECT b3.id, b3.geom
                FROM public.ref_buildings_gold b3
                WHERE b3.geom IS NOT NULL
                  AND ST_DWithin(
                        ST_Transform(ca2.geom, 3857),
                        ST_Transform(b3.geom,  3857),
                        30.0
                  )
                ORDER BY ST_Distance(
                    ST_Transform(ca2.geom, 3857),
                    ST_Transform(b3.geom,  3857)
                )
                LIMIT 1
            ) b2
            WHERE ca2.campaign_id = p_campaign_id
              AND ca2.building_id IS NULL
              AND ca2.geom        IS NOT NULL
        ) nearest
        WHERE ca.id = nearest.address_id
        RETURNING ca.id
    )
    SELECT COUNT(*) INTO v_proximity_count FROM proximity;

    RETURN QUERY SELECT v_exact_count, v_proximity_count, v_exact_count + v_proximity_count;
END;
$$;

COMMENT ON FUNCTION public.link_campaign_addresses_gold(uuid, text) IS
'Links campaign_addresses to ref_buildings_gold. Pass 1: exact containment (confidence=1.0). Pass 2: nearest within 30 m (confidence scaled). Sets building_id, match_source, confidence on each address row.';

COMMIT;
