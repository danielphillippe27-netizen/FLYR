-- =====================================================
-- Session Recording Feature
-- Date: 2025-02-08
-- Description: Adds building completion tracking to sessions:
--   - New columns on sessions for target buildings, completed count, auto-complete settings
--   - session_events table for completion/undo events
--   - RPCs for atomic completion and session replay
-- =====================================================

-- =====================================================
-- 1. Extend sessions table for building tracking
-- =====================================================

-- Allow end_time to be NULL for active (in-progress) sessions
ALTER TABLE public.sessions
ALTER COLUMN end_time DROP NOT NULL;

-- Ensure user_id exists on sessions (in case schema differs)
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Building session fields
ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS is_paused BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS active_seconds INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS target_building_ids TEXT[],
ADD COLUMN IF NOT EXISTS completed_count INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS auto_complete_enabled BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS auto_complete_threshold_m DOUBLE PRECISION NOT NULL DEFAULT 15.0,
ADD COLUMN IF NOT EXISTS auto_complete_dwell_seconds INTEGER NOT NULL DEFAULT 8,
ADD COLUMN IF NOT EXISTS notes TEXT;

COMMENT ON COLUMN public.sessions.target_building_ids IS 'Array of building gers_id (as text) for this session';
COMMENT ON COLUMN public.sessions.completed_count IS 'Number of target buildings marked completed this session';
COMMENT ON COLUMN public.sessions.auto_complete_threshold_m IS 'Meters from building centroid to trigger auto-complete';
COMMENT ON COLUMN public.sessions.auto_complete_dwell_seconds IS 'Seconds user must dwell within threshold to auto-complete';

-- Generated column for target count (null when not a building session)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'sessions' AND column_name = 'target_count'
    ) THEN
        ALTER TABLE public.sessions
        ADD COLUMN target_count INTEGER GENERATED ALWAYS AS (array_length(target_building_ids, 1)) STORED;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON public.sessions(start_time DESC);
-- idx_sessions_campaign_id already exists from add_session_routes

-- =====================================================
-- 2. Create session_events table
-- =====================================================

CREATE TABLE IF NOT EXISTS public.session_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    building_id TEXT,  -- null for session_started / session_paused / session_resumed / session_ended
    address_id UUID REFERENCES public.campaign_addresses(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'session_started',
        'session_paused',
        'session_resumed',
        'session_ended',
        'completed_manual',
        'completed_auto',
        'completion_undone'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_location GEOGRAPHY(Point, 4326),
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    metadata JSONB DEFAULT '{}',
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Ensure building_id and user_id exist (in case session_events was created earlier without them)
ALTER TABLE public.session_events ADD COLUMN IF NOT EXISTS building_id TEXT;
ALTER TABLE public.session_events ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_session_events_session_id ON public.session_events(session_id);
CREATE INDEX IF NOT EXISTS idx_session_events_building_id ON public.session_events(building_id);
CREATE INDEX IF NOT EXISTS idx_session_events_created_at ON public.session_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_session_events_event_type ON public.session_events(event_type);

COMMENT ON TABLE public.session_events IS 'Per-building and session lifecycle events for session replay and analytics';

ALTER TABLE public.session_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own session events" ON public.session_events;
CREATE POLICY "Users can view own session events"
    ON public.session_events FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own session events" ON public.session_events;
CREATE POLICY "Users can insert own session events"
    ON public.session_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- =====================================================
-- 3. RPC: get session with events (for replay)
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_get_session_with_events(p_session_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'session', to_jsonb(s),
        'events', COALESCE(
            (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at)
             FROM public.session_events e WHERE e.session_id = p_session_id),
            '[]'::jsonb
        )
    )
    FROM public.sessions s
    WHERE s.id = p_session_id AND s.user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_session_with_events(UUID) TO authenticated;

-- =====================================================
-- 4. RPC: complete building in session (atomic)
-- =====================================================

CREATE OR REPLACE FUNCTION public.rpc_complete_building_in_session(
    p_session_id UUID,
    p_building_id TEXT,
    p_event_type TEXT,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lon DOUBLE PRECISION DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_address_id UUID;
    v_campaign_id UUID;
    v_user_id UUID;
    v_event_id UUID;
    v_building_id UUID;
BEGIN
    -- Must be session owner
    SELECT campaign_id, user_id INTO v_campaign_id, v_user_id
    FROM public.sessions WHERE id = p_session_id;
    IF v_user_id IS NULL OR v_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Session not found or access denied';
    END IF;

    -- Resolve building by gers_id (p_building_id is gers_id as text)
    SELECT b.id INTO v_building_id
    FROM public.buildings b
    WHERE LOWER(b.gers_id::text) = LOWER(p_building_id)
    LIMIT 1;

    -- Find address_id for this building in this campaign
    IF v_campaign_id IS NOT NULL THEN
        SELECT bal.address_id INTO v_address_id
        FROM public.building_address_links bal
        WHERE bal.building_id = v_building_id
          AND bal.campaign_id = v_campaign_id
        LIMIT 1;
    END IF;

    -- Insert event (building_id stored as text = gers_id for replay; null for lifecycle events)
    INSERT INTO public.session_events (
        session_id, building_id, address_id, event_type,
        lat, lon, event_location, metadata, user_id
    ) VALUES (
        p_session_id,
        NULLIF(TRIM(p_building_id), ''),
        v_address_id,
        p_event_type,
        p_lat,
        p_lon,
        CASE WHEN p_lon IS NOT NULL AND p_lat IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography
             ELSE NULL END,
        p_metadata,
        v_user_id
    )
    RETURNING id INTO v_event_id;

    -- Update session completed_count
    IF p_event_type IN ('completed_manual', 'completed_auto') THEN
        UPDATE public.sessions
        SET completed_count = completed_count + 1, updated_at = now()
        WHERE id = p_session_id;
    ELSIF p_event_type = 'completion_undone' THEN
        UPDATE public.sessions
        SET completed_count = GREATEST(0, completed_count - 1), updated_at = now()
        WHERE id = p_session_id;
    END IF;

    -- Update building_stats to visited when completing (not on undo)
    -- building_stats schema: gers_id (text), campaign_id, status, scans_total, scans_today, last_scan_at (no building_id)
    IF p_event_type IN ('completed_manual', 'completed_auto') AND v_campaign_id IS NOT NULL AND NULLIF(TRIM(p_building_id), '') IS NOT NULL THEN
        UPDATE public.building_stats
        SET status = 'visited', last_scan_at = now()
        WHERE LOWER(TRIM(gers_id)) = LOWER(TRIM(p_building_id)) AND campaign_id = v_campaign_id;
        IF NOT FOUND THEN
            INSERT INTO public.building_stats (gers_id, campaign_id, status, scans_total, scans_today, last_scan_at)
            VALUES (TRIM(p_building_id), v_campaign_id, 'visited', 0, 0, now());
        END IF;
    END IF;

    RETURN jsonb_build_object('event_id', v_event_id, 'address_id', v_address_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_complete_building_in_session(UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB) TO authenticated;
