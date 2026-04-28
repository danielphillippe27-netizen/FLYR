-- Migration: Fix Leaderboard Data Population Issues
-- 1. Fixes user_stats not being updated with session metrics
-- 2. Fixes name display (uses proper full_name from metadata)
-- 3. Adds proper time-based leaderboard using sessions table

-- Drop existing function to avoid conflicts
DROP FUNCTION IF EXISTS public.get_leaderboard(text, text);

-- Create improved get_leaderboard function
-- Uses sessions table for time-based filtering (correct approach)
CREATE OR REPLACE FUNCTION public.get_leaderboard(
    p_metric TEXT DEFAULT 'flyers',
    p_timeframe TEXT DEFAULT 'weekly'
)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    flyers INTEGER,
    leads INTEGER,
    conversations INTEGER,
    distance NUMERIC,
    rank INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
BEGIN
    -- Calculate date range based on timeframe
    CASE p_timeframe
        WHEN 'daily' THEN
            v_start_date := date_trunc('day', NOW());
        WHEN 'weekly' THEN
            v_start_date := date_trunc('week', NOW());
        WHEN 'monthly' THEN
            v_start_date := date_trunc('month', NOW());
        WHEN 'all', 'all_time' THEN
            v_start_date := '1970-01-01'::TIMESTAMPTZ;
        ELSE
            v_start_date := date_trunc('week', NOW());
    END CASE;
    
    RETURN QUERY
    WITH session_stats AS (
        -- Aggregate stats from sessions table (time-series data)
        SELECT 
            s.user_id,
            COALESCE(SUM(s.flyers_delivered), 0)::INTEGER as session_flyers,
            COALESCE(SUM(s.conversations), 0)::INTEGER as session_conversations,
            COALESCE(SUM(s.doors_hit), 0)::INTEGER as session_doors,
            COALESCE(SUM(s.distance_meters), 0)::NUMERIC / 1000.0 as session_distance_km
        FROM public.sessions s
        WHERE s.created_at >= v_start_date
           OR (p_timeframe IN ('all', 'all_time') AND s.created_at IS NOT NULL)
        GROUP BY s.user_id
    ),
    user_list AS (
        -- Get all users with their display names
        SELECT 
            au.id as uid,
            COALESCE(
                au.raw_user_meta_data->>'full_name',
                au.raw_user_meta_data->>'name',
                SPLIT_PART(au.email, '@', 1),
                'Agent'
            ) as display_name
        FROM auth.users au
    ),
    combined_stats AS (
        -- Combine user list with session stats
        SELECT 
            ul.uid,
            ul.display_name,
            COALESCE(ss.session_flyers, 0) as flyers,
            0::INTEGER as leads,
            COALESCE(ss.session_conversations, 0) as conversations,
            COALESCE(ss.session_distance_km, 0.0)::NUMERIC as distance
        FROM user_list ul
        LEFT JOIN session_stats ss ON ul.uid = ss.user_id
    ),
    ranked AS (
        SELECT 
            cs.*,
            CASE p_metric
                WHEN 'flyers' THEN ROW_NUMBER() OVER (ORDER BY cs.flyers DESC, cs.conversations DESC)
                WHEN 'conversations' THEN ROW_NUMBER() OVER (ORDER BY cs.conversations DESC, cs.flyers DESC)
                WHEN 'leads' THEN ROW_NUMBER() OVER (ORDER BY cs.leads DESC, cs.conversations DESC)
                WHEN 'distance' THEN ROW_NUMBER() OVER (ORDER BY cs.distance DESC, cs.flyers DESC)
                ELSE ROW_NUMBER() OVER (ORDER BY cs.flyers DESC, cs.conversations DESC)
            END::INTEGER as user_rank
        FROM combined_stats cs
        WHERE cs.flyers > 0 OR cs.conversations > 0 OR cs.distance > 0 OR p_timeframe IN ('all', 'all_time')
    )
    SELECT 
        r.uid as user_id,
        r.display_name as full_name,
        r.flyers,
        r.leads,
        r.conversations,
        r.distance,
        r.user_rank as rank
    FROM ranked r
    ORDER BY r.user_rank
    LIMIT 100;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT) TO authenticated;

-- Create function to increment user_stats safely
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
        user_id, flyers, conversations, leads_created, distance_walked, time_tracked
    )
    VALUES (p_user_id, p_flyers, p_conversations, p_leads, p_distance_km, p_time_minutes)
    ON CONFLICT (user_id)
    DO UPDATE SET
        flyers = user_stats.flyers + p_flyers,
        conversations = user_stats.conversations + p_conversations,
        leads_created = user_stats.leads_created + p_leads,
        distance_walked = user_stats.distance_walked + p_distance_km,
        time_tracked = user_stats.time_tracked + p_time_minutes,
        updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_user_stats(UUID, INTEGER, INTEGER, INTEGER, DOUBLE PRECISION, INTEGER) TO authenticated;

-- Fix RLS policies for leaderboard visibility
DROP POLICY IF EXISTS "user_stats_select_leaderboard" ON public.user_stats;
CREATE POLICY "user_stats_select_all"
    ON public.user_stats
    FOR SELECT
    TO authenticated
    USING (true);

-- Create debug view
CREATE OR REPLACE VIEW public.leaderboard_debug AS
SELECT 
    au.id as user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', au.email) as name,
    us.flyers as total_flyers,
    us.conversations as total_conversations,
    us.distance_walked as total_distance_km,
    us.updated_at as stats_updated,
    (SELECT COUNT(*) FROM public.sessions s WHERE s.user_id = au.id) as session_count,
    (SELECT COALESCE(SUM(s.flyers_delivered), 0) FROM public.sessions s WHERE s.user_id = au.id) as sessions_flyers_sum
FROM auth.users au
LEFT JOIN public.user_stats us ON au.id = us.user_id;

GRANT SELECT ON public.leaderboard_debug TO authenticated;
