BEGIN;

CREATE OR REPLACE FUNCTION public.get_campaign_confidence_hotspots(
    p_precision INTEGER DEFAULT 5,
    p_workspace_id UUID DEFAULT NULL
)
RETURNS TABLE (
    geohash TEXT,
    center_lat DOUBLE PRECISION,
    center_lon DOUBLE PRECISION,
    campaigns_count BIGINT,
    avg_confidence_score DOUBLE PRECISION,
    avg_linked_coverage DOUBLE PRECISION,
    low_count BIGINT,
    medium_count BIGINT,
    high_count BIGINT,
    gold_exact_total BIGINT,
    silver_total BIGINT,
    bronze_total BIGINT,
    lambda_total BIGINT,
    priority_score DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
WITH campaign_centers AS (
    SELECT
        c.id,
        c.workspace_id,
        c.data_confidence_score,
        c.data_confidence_label,
        c.data_confidence_summary,
        COALESCE(
            ST_Centroid(c.territory_boundary::geometry),
            addr.center_geom
        ) AS center_geom
    FROM public.campaigns c
    LEFT JOIN LATERAL (
        SELECT ST_Centroid(ST_Collect(ca.geom::geometry)) AS center_geom
        FROM public.campaign_addresses ca
        WHERE ca.campaign_id = c.id
          AND ca.geom IS NOT NULL
    ) addr ON TRUE
    WHERE c.data_confidence_score IS NOT NULL
      AND (p_workspace_id IS NULL OR c.workspace_id = p_workspace_id)
),
bucketed AS (
    SELECT
        ST_GeoHash(center_geom, GREATEST(1, LEAST(COALESCE(p_precision, 5), 12))) AS geohash,
        center_geom,
        data_confidence_score,
        data_confidence_label,
        data_confidence_summary
    FROM campaign_centers
    WHERE center_geom IS NOT NULL
)
SELECT
    b.geohash,
    ST_Y(ST_Centroid(ST_Collect(b.center_geom)))::double precision AS center_lat,
    ST_X(ST_Centroid(ST_Collect(b.center_geom)))::double precision AS center_lon,
    COUNT(*)::bigint AS campaigns_count,
    AVG(b.data_confidence_score)::double precision AS avg_confidence_score,
    AVG(COALESCE((b.data_confidence_summary -> 'metrics' ->> 'linked_coverage')::double precision, 0))::double precision AS avg_linked_coverage,
    COUNT(*) FILTER (WHERE b.data_confidence_label = 'low')::bigint AS low_count,
    COUNT(*) FILTER (WHERE b.data_confidence_label = 'medium')::bigint AS medium_count,
    COUNT(*) FILTER (WHERE b.data_confidence_label = 'high')::bigint AS high_count,
    COALESCE(SUM((b.data_confidence_summary -> 'metrics' ->> 'gold_exact_count')::bigint), 0)::bigint AS gold_exact_total,
    COALESCE(SUM((b.data_confidence_summary -> 'metrics' ->> 'silver_count')::bigint), 0)::bigint AS silver_total,
    COALESCE(SUM((b.data_confidence_summary -> 'metrics' ->> 'bronze_count')::bigint), 0)::bigint AS bronze_total,
    COALESCE(SUM((b.data_confidence_summary -> 'metrics' ->> 'lambda_count')::bigint), 0)::bigint AS lambda_total,
    (
        COUNT(*)::double precision *
        (1 - AVG(b.data_confidence_score))
    )::double precision AS priority_score
FROM bucketed b
GROUP BY b.geohash
ORDER BY priority_score DESC, campaigns_count DESC, geohash ASC;
$$;

COMMENT ON FUNCTION public.get_campaign_confidence_hotspots(integer, uuid) IS
'Groups accessible campaigns into geohash cells and summarizes confidence + source mix. Use priority_score to rank high-usage, low-confidence areas.';

GRANT EXECUTE ON FUNCTION public.get_campaign_confidence_hotspots(integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_campaign_confidence_hotspots(integer, uuid) TO service_role;

COMMIT;
