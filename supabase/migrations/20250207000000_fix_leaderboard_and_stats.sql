-- Migration: Fix Leaderboard and Stats System
-- Date: 2025-02-07
-- Description: Fixes all leaderboard issues:
--   1. All "0" stats - adds flyers/conversations tracking to sessions
--   2. All named "User" - uses full_name from user metadata
--   3. All rank 1 - filters by session dates instead of user_stats.created_at
--   4. Monthly broken - adds monthly timeframe handling

-- ============================================================================
-- STEP 1: Add tracking columns to sessions table
-- ============================================================================

ALTER TABLE public.sessions 
ADD COLUMN IF NOT EXISTS flyers_delivered INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS conversations INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.sessions.flyers_delivered IS 'Number of flyers delivered during this session';
COMMENT ON COLUMN public.sessions.conversations IS 'Number of conversations had during this session';

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_sessions_flyers ON public.sessions(flyers_delivered DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_conversations ON public.sessions(conversations DESC);

-- ============================================================================
-- STEP 2: Create/Replace get_leaderboard function with all fixes
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_leaderboard(text, text);

CREATE OR REPLACE FUNCTION public.get_leaderboard(
    p_metric TEXT DEFAULT 'flyers',
    p_timeframe TEXT DEFAULT 'weekly'
)
RETURNS TABLE (
    id TEXT,
    name TEXT,
    avatar_url TEXT,
    rank INTEGER,
    flyers INTEGER,
    leads INTEGER,
    conversations INTEGER,
    distance DOUBLE PRECISION,
    daily JSONB,
    weekly JSONB,
    all_time JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
BEGIN
    -- Handle timeframe (including 'monthly' which was missing)
    CASE p_timeframe
        WHEN 'daily' THEN v_start_date := date_trunc('day', NOW());
        WHEN 'weekly' THEN v_start_date := date_trunc('week', NOW());
        WHEN 'monthly' THEN v_start_date := date_trunc('month', NOW());
        WHEN 'all_time' THEN v_start_date := '1970-01-01'::TIMESTAMPTZ;
        ELSE v_start_date := date_trunc('week', NOW());
    END CASE;

    RETURN QUERY
    WITH session_stats AS (
        -- Aggregate stats from sessions table, filtered by timeframe
        -- This fixes the "all rank 1" issue by using session dates
        SELECT
            s.user_id,
            COALESCE(SUM(s.flyers_delivered), 0)::INTEGER as session_flyers,
            COALESCE(SUM(s.conversations), 0)::INTEGER as session_conversations,
            COALESCE(SUM(s.distance_meters), 0)::DOUBLE PRECISION / 1000.0 as session_distance_km
        FROM public.sessions s
        WHERE s.start_time >= v_start_date
        GROUP BY s.user_id
    ),
    ranked_users AS (
        SELECT
            au.id::TEXT as user_id,
            -- Fix for "all named User" - use full_name from metadata
            COALESCE(au.raw_user_meta_data->>'full_name', SPLIT_PART(au.email, '@', 1), 'Agent') as display_name,
            COALESCE(au.raw_user_meta_data->>'avatar_url', NULL)::TEXT as user_avatar,
            COALESCE(ss.session_flyers, 0) as user_flyers,
            COALESCE(ss.session_conversations, 0) as user_conversations,
            COALESCE(ss.session_distance_km, 0.0) as user_distance,
            -- Create snapshots for each timeframe
            jsonb_build_object(
                'flyers', COALESCE(ss.session_flyers, 0),
                'conversations', COALESCE(ss.session_conversations, 0),
                'distance', COALESCE(ss.session_distance_km, 0.0),
                'leads', 0
            ) as snapshot
        FROM auth.users au
        LEFT JOIN session_stats ss ON au.id = ss.user_id
        -- Only show users with activity in this timeframe
        WHERE COALESCE(ss.session_flyers, 0) > 0 OR COALESCE(ss.session_conversations, 0) > 0
    )
    SELECT
        ru.user_id as id,
        ru.display_name as name,
        ru.user_avatar as avatar_url,
        ROW_NUMBER() OVER (
            ORDER BY 
                CASE p_metric
                    WHEN 'flyers' THEN ru.user_flyers
                    WHEN 'conversations' THEN ru.user_conversations
                    WHEN 'distance' THEN ru.user_distance::INTEGER
                    ELSE ru.user_flyers
                END DESC
        )::INTEGER as rank,
        ru.user_flyers as flyers,
        0::INTEGER as leads,
        ru.user_conversations as conversations,
        ru.user_distance as distance,
        ru.snapshot as daily,
        ru.snapshot as weekly,
        ru.snapshot as all_time
    FROM ranked_users ru
    ORDER BY rank
    LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.get_leaderboard(TEXT, TEXT) IS 'Fixed leaderboard function: uses sessions for time filtering, full_name for display, and handles monthly timeframe';

-- ============================================================================
-- STEP 3: Create increment_user_stats RPC for atomic updates
-- ============================================================================

DROP FUNCTION IF EXISTS public.increment_user_stats(UUID, INTEGER, INTEGER, INTEGER, DOUBLE PRECISION, INTEGER);

CREATE OR REPLACE FUNCTION public.increment_user_stats(
    p_user_id UUID,
    p_flyers INTEGER DEFAULT 0,
    p_conversations INTEGER DEFAULT 0,
    p_leads INTEGER DEFAULT 0,
    p_distance_km DOUBLE PRECISION DEFAULT 0.0,
    p_time_minutes INTEGER DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_stats (
        user_id,
        flyers,
        conversations,
        leads_created,
        distance_walked,
        time_tracked
    )
    VALUES (
        p_user_id,
        p_flyers,
        p_conversations,
        p_leads,
        p_distance_km,
        p_time_minutes
    )
    ON CONFLICT (user_id) DO UPDATE SET
        flyers = user_stats.flyers + EXCLUDED.flyers,
        conversations = user_stats.conversations + EXCLUDED.conversations,
        leads_created = user_stats.leads_created + EXCLUDED.leads_created,
        distance_walked = user_stats.distance_walked + EXCLUDED.distance_walked,
        time_tracked = user_stats.time_tracked + EXCLUDED.time_tracked,
        updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_user_stats TO authenticated;

COMMENT ON FUNCTION public.increment_user_stats IS 'Atomically increment user stats - used by iOS app after session completion';

-- ============================================================================
-- STEP 4: Create auto-update trigger (optional but recommended)
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_update_user_stats_from_session ON public.sessions;
DROP FUNCTION IF EXISTS public.update_user_stats_from_session();

CREATE OR REPLACE FUNCTION public.update_user_stats_from_session()
RETURNS TRIGGER AS $$
BEGIN
    -- Automatically update user_stats when a session is inserted
    INSERT INTO public.user_stats (
        user_id,
        flyers,
        conversations,
        distance_walked,
        time_tracked
    )
    VALUES (
        NEW.user_id,
        NEW.flyers_delivered,
        NEW.conversations,
        NEW.distance_meters / 1000.0,
        EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 60.0
    )
    ON CONFLICT (user_id) DO UPDATE SET
        flyers = user_stats.flyers + EXCLUDED.flyers,
        conversations = user_stats.conversations + EXCLUDED.conversations,
        distance_walked = user_stats.distance_walked + EXCLUDED.distance_walked,
        time_tracked = user_stats.time_tracked + EXCLUDED.time_tracked,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_stats_from_session
    AFTER INSERT ON public.sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_user_stats_from_session();

COMMENT ON FUNCTION public.update_user_stats_from_session IS 'Auto-update user_stats when new session is created';

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Leaderboard fixes applied successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Changes made:';
    RAISE NOTICE '  1. Added flyers_delivered and conversations columns to sessions table';
    RAISE NOTICE '  2. Fixed get_leaderboard() to use full_name and session-based time filtering';
    RAISE NOTICE '  3. Added monthly timeframe support';
    RAISE NOTICE '  4. Created increment_user_stats() RPC for atomic updates';
    RAISE NOTICE '  5. Created auto-update trigger for user_stats';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Update iOS SessionManager.swift to track flyers/conversations';
    RAISE NOTICE '  2. (Optional) Run backfill query to populate stats from existing sessions';
END $$;
