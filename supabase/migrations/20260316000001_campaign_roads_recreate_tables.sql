-- =====================================================
-- Repair: Recreate campaign_roads and campaign_road_metadata
-- with correct schema (road_id, etc.)
--
-- Use this if you see: column "road_id" does not exist
-- (e.g. campaign_roads was created by an older migration with different columns)
-- =====================================================

-- 1. Drop RPCs that depend on the tables (so we can drop tables)
DROP FUNCTION IF EXISTS public.rpc_get_campaign_roads_v2(UUID);
DROP FUNCTION IF EXISTS public.rpc_get_campaign_road_metadata(UUID);
DROP FUNCTION IF EXISTS public.rpc_upsert_campaign_roads(UUID, JSONB, JSONB);
DROP FUNCTION IF EXISTS public.rpc_update_road_preparation_status(UUID, TEXT, TEXT);

-- 2. Drop tables (CASCADE removes policies, indexes, triggers)
DROP TABLE IF EXISTS public.campaign_roads CASCADE;
DROP TABLE IF EXISTS public.campaign_road_metadata CASCADE;

-- 3. Recreate campaign_roads with full schema
CREATE TABLE public.campaign_roads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    road_id TEXT NOT NULL,
    road_name TEXT,
    road_class TEXT,
    geom GEOMETRY(LineString, 4326) NOT NULL,
    bbox_min_lat DOUBLE PRECISION NOT NULL,
    bbox_min_lon DOUBLE PRECISION NOT NULL,
    bbox_max_lat DOUBLE PRECISION NOT NULL,
    bbox_max_lon DOUBLE PRECISION NOT NULL,
    source TEXT NOT NULL DEFAULT 'mapbox',
    source_version TEXT,
    cache_version INTEGER NOT NULL DEFAULT 1,
    corridor_build_version INTEGER NOT NULL DEFAULT 1,
    properties JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_campaign_roads_campaign_id ON public.campaign_roads(campaign_id);
CREATE INDEX idx_campaign_roads_geom ON public.campaign_roads USING GIST(geom);
CREATE INDEX idx_campaign_roads_road_id ON public.campaign_roads(campaign_id, road_id);
CREATE INDEX idx_campaign_roads_bbox ON public.campaign_roads(campaign_id, bbox_min_lat, bbox_max_lat, bbox_min_lon, bbox_max_lon);
CREATE UNIQUE INDEX idx_campaign_roads_unique ON public.campaign_roads(campaign_id, road_id);

ALTER TABLE public.campaign_roads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view campaign roads"
    ON public.campaign_roads FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_roads.campaign_id
            AND (campaigns.owner_id = auth.uid()
                 OR campaigns.workspace_id IN (
                     SELECT workspace_id FROM public.workspace_members
                     WHERE user_id = auth.uid()
                 ))
        )
    );

CREATE POLICY "Users can manage campaign roads"
    ON public.campaign_roads FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_roads.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_roads.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- 4. Recreate campaign_road_metadata
CREATE TABLE public.campaign_road_metadata (
    campaign_id UUID PRIMARY KEY REFERENCES public.campaigns(id) ON DELETE CASCADE,
    roads_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (roads_status IN ('pending', 'fetching', 'ready', 'failed')),
    road_count INTEGER NOT NULL DEFAULT 0,
    bounds JSONB,
    cache_version INTEGER NOT NULL DEFAULT 0,
    corridor_build_version INTEGER NOT NULL DEFAULT 1,
    fetched_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    last_refresh_at TIMESTAMPTZ,
    last_error_message TEXT,
    last_error_at TIMESTAMPTZ,
    retry_count INTEGER NOT NULL DEFAULT 0,
    source TEXT DEFAULT 'mapbox',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_campaign_road_metadata_status ON public.campaign_road_metadata(roads_status);
CREATE INDEX idx_campaign_road_metadata_expires ON public.campaign_road_metadata(expires_at) WHERE expires_at IS NOT NULL;

ALTER TABLE public.campaign_road_metadata ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view campaign road metadata"
    ON public.campaign_road_metadata FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_road_metadata.campaign_id
            AND (campaigns.owner_id = auth.uid()
                 OR campaigns.workspace_id IN (
                     SELECT workspace_id FROM public.workspace_members
                     WHERE user_id = auth.uid()
                 ))
        )
    );

CREATE POLICY "Users can manage campaign road metadata"
    ON public.campaign_road_metadata FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_road_metadata.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.campaigns
            WHERE campaigns.id = campaign_road_metadata.campaign_id
            AND campaigns.owner_id = auth.uid()
        )
    );

-- 5. Triggers for updated_at
CREATE OR REPLACE FUNCTION update_campaign_roads_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_campaign_roads_updated_at
    BEFORE UPDATE ON public.campaign_roads
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_roads_updated_at();

CREATE TRIGGER trigger_campaign_road_metadata_updated_at
    BEFORE UPDATE ON public.campaign_road_metadata
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_roads_updated_at();

-- 6. RPCs
CREATE OR REPLACE FUNCTION public.rpc_get_campaign_roads_v2(p_campaign_id UUID)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(jsonb_agg(features.feature ORDER BY features.road_name), '[]'::jsonb)
    ) INTO result
    FROM (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'id', r.road_id,
            'geometry', ST_AsGeoJSON(r.geom)::jsonb,
            'properties', jsonb_build_object(
                'id', r.road_id,
                'name', r.road_name,
                'class', r.road_class,
                'cache_version', r.cache_version,
                'corridor_build_version', r.corridor_build_version
            )
        ) AS feature,
            r.road_name
        FROM public.campaign_roads r
        WHERE r.campaign_id = p_campaign_id
    ) features;
    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_roads_v2(UUID) TO authenticated, service_role, anon;

CREATE OR REPLACE FUNCTION public.rpc_get_campaign_road_metadata(p_campaign_id UUID)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    v_metadata RECORD;
    v_age_days NUMERIC;
BEGIN
    SELECT * INTO v_metadata
    FROM public.campaign_road_metadata
    WHERE campaign_id = p_campaign_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'campaign_id', p_campaign_id,
            'roads_status', 'pending',
            'road_count', 0,
            'cache_version', 0,
            'corridor_build_version', 1,
            'fetched_at', NULL,
            'expires_at', NULL,
            'last_refresh_at', NULL,
            'age_days', NULL,
            'is_stale', false,
            'last_error_message', NULL,
            'source', 'mapbox'
        );
    END IF;
    
    v_age_days := NULL;
    IF v_metadata.fetched_at IS NOT NULL THEN
        v_age_days := EXTRACT(EPOCH FROM (NOW() - v_metadata.fetched_at)) / 86400;
    END IF;
    
    RETURN jsonb_build_object(
        'campaign_id', p_campaign_id,
        'roads_status', COALESCE(v_metadata.roads_status, 'pending'),
        'road_count', COALESCE(v_metadata.road_count, 0),
        'cache_version', COALESCE(v_metadata.cache_version, 0),
        'corridor_build_version', COALESCE(v_metadata.corridor_build_version, 1),
        'fetched_at', v_metadata.fetched_at,
        'expires_at', v_metadata.expires_at,
        'last_refresh_at', v_metadata.last_refresh_at,
        'age_days', v_age_days,
        'is_stale', v_age_days IS NOT NULL AND v_age_days >= 30,
        'last_error_message', v_metadata.last_error_message,
        'source', COALESCE(v_metadata.source, 'mapbox')
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_campaign_road_metadata(UUID) TO authenticated, service_role, anon;

CREATE OR REPLACE FUNCTION public.rpc_upsert_campaign_roads(
    p_campaign_id UUID,
    p_roads JSONB,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    v_road JSONB;
    v_count INTEGER := 0;
    v_cache_version INTEGER;
BEGIN
    SELECT COALESCE(MAX(cache_version), 0) + 1 INTO v_cache_version
    FROM public.campaign_roads
    WHERE campaign_id = p_campaign_id;
    
    DELETE FROM public.campaign_roads WHERE campaign_id = p_campaign_id;
    
    FOR v_road IN SELECT * FROM jsonb_array_elements(p_roads)
    LOOP
        INSERT INTO public.campaign_roads (
            campaign_id, road_id, road_name, road_class, geom,
            bbox_min_lat, bbox_min_lon, bbox_max_lat, bbox_max_lon,
            source, source_version, cache_version, properties
        ) VALUES (
            p_campaign_id,
            v_road->>'road_id',
            v_road->>'road_name',
            v_road->>'road_class',
            ST_SetSRID(ST_GeomFromGeoJSON(v_road->'geom'), 4326),
            (v_road->>'bbox_min_lat')::DOUBLE PRECISION,
            (v_road->>'bbox_min_lon')::DOUBLE PRECISION,
            (v_road->>'bbox_max_lat')::DOUBLE PRECISION,
            (v_road->>'bbox_max_lon')::DOUBLE PRECISION,
            COALESCE(v_road->>'source', 'mapbox'),
            v_road->>'source_version',
            v_cache_version,
            COALESCE(v_road->'properties', '{}'::jsonb)
        );
        v_count := v_count + 1;
    END LOOP;
    
    INSERT INTO public.campaign_road_metadata (
        campaign_id, roads_status, road_count, bounds, cache_version, corridor_build_version,
        fetched_at, expires_at, last_refresh_at, source, last_error_message, last_error_at, retry_count
    ) VALUES (
        p_campaign_id, 'ready', v_count, p_metadata->'bounds', v_cache_version,
        COALESCE((p_metadata->>'corridor_build_version')::INTEGER, 1),
        NOW(), NOW() + INTERVAL '30 days', NOW(),
        COALESCE(p_metadata->>'source', 'mapbox'), NULL, NULL, 0
    )
    ON CONFLICT (campaign_id) DO UPDATE SET
        roads_status = 'ready',
        road_count = v_count,
        bounds = EXCLUDED.bounds,
        cache_version = v_cache_version,
        corridor_build_version = EXCLUDED.corridor_build_version,
        fetched_at = NOW(),
        expires_at = NOW() + INTERVAL '30 days',
        last_refresh_at = NOW(),
        source = EXCLUDED.source,
        last_error_message = NULL,
        last_error_at = NULL,
        retry_count = 0,
        updated_at = NOW();
    
    RETURN jsonb_build_object('success', true, 'road_count', v_count, 'cache_version', v_cache_version);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_upsert_campaign_roads(UUID, JSONB, JSONB) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_road_preparation_status(
    p_campaign_id UUID,
    p_status TEXT,
    p_error_message TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.campaign_road_metadata (campaign_id, roads_status, last_error_message, last_error_at, retry_count)
    VALUES (p_campaign_id, p_status, p_error_message, CASE WHEN p_error_message IS NOT NULL THEN NOW() END, 0)
    ON CONFLICT (campaign_id) DO UPDATE SET
        roads_status = p_status,
        last_error_message = COALESCE(p_error_message, campaign_road_metadata.last_error_message),
        last_error_at = CASE WHEN p_error_message IS NOT NULL THEN NOW() ELSE campaign_road_metadata.last_error_at END,
        retry_count = CASE WHEN p_status = 'failed' THEN campaign_road_metadata.retry_count + 1 ELSE campaign_road_metadata.retry_count END,
        updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_update_road_preparation_status(UUID, TEXT, TEXT) TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_roads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_road_metadata TO authenticated;
GRANT ALL ON public.campaign_roads TO service_role;
GRANT ALL ON public.campaign_road_metadata TO service_role;

NOTIFY pgrst, 'reload schema';
