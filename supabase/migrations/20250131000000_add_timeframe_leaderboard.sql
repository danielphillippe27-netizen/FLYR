-- Migration: Add timeframe-based leaderboard RPC function
-- Creates new get_leaderboard function with metric and timeframe parameters

-- Create new function for timeframe-based leaderboard queries
-- This function returns data in the LeaderboardUser format with metric snapshots
CREATE OR REPLACE FUNCTION public.get_leaderboard(
    metric TEXT DEFAULT 'conversations',
    timeframe TEXT DEFAULT 'weekly'
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
    start_date TIMESTAMPTZ;
    end_date TIMESTAMPTZ := NOW();
BEGIN
    -- Calculate date range based on timeframe
    CASE timeframe
        WHEN 'daily' THEN
            start_date := date_trunc('day', NOW());
        WHEN 'weekly' THEN
            start_date := date_trunc('week', NOW());
        WHEN 'all_time' THEN
            start_date := '1970-01-01'::TIMESTAMPTZ;
        ELSE
            start_date := date_trunc('week', NOW());
    END CASE;
    
    RETURN QUERY
    WITH user_metrics AS (
        SELECT 
            us.user_id::TEXT as id,
            COALESCE(au.raw_user_meta_data->>'full_name', SPLIT_PART(au.email, '@', 1), 'User') as name,
            COALESCE(au.raw_user_meta_data->>'avatar_url', NULL)::TEXT as avatar_url,
            us.flyers,
            us.conversations,
            us.leads_created as leads,
            us.distance_walked as distance,
            -- For now, use all_time stats for all snapshots (can be enhanced later with actual time-based filtering)
            jsonb_build_object(
                'flyers', us.flyers,
                'leads', us.leads_created,
                'conversations', us.conversations,
                'distance', us.distance_walked
            ) as daily_snapshot,
            jsonb_build_object(
                'flyers', us.flyers,
                'leads', us.leads_created,
                'conversations', us.conversations,
                'distance', us.distance_walked
            ) as weekly_snapshot,
            jsonb_build_object(
                'flyers', us.flyers,
                'leads', us.leads_created,
                'conversations', us.conversations,
                'distance', us.distance_walked
            ) as all_time_snapshot,
            -- Calculate rank based on selected metric
            CASE metric
                WHEN 'flyers' THEN us.flyers
                WHEN 'leads' THEN us.leads_created
                WHEN 'conversations' THEN us.conversations
                WHEN 'distance' THEN us.distance_walked
                ELSE us.conversations
            END as metric_value
        FROM public.user_stats us
        LEFT JOIN auth.users au ON us.user_id = au.id
        WHERE us.updated_at >= start_date
            AND (us.flyers > 0 OR us.conversations > 0 OR us.leads_created > 0)
    ),
    ranked_users AS (
        SELECT 
            um.*,
            ROW_NUMBER() OVER (
                ORDER BY 
                    CASE metric
                        WHEN 'flyers' THEN um.flyers
                        WHEN 'leads' THEN um.leads
                        WHEN 'conversations' THEN um.conversations
                        WHEN 'distance' THEN um.distance
                        ELSE um.conversations
                    END DESC NULLS LAST,
                    um.conversations DESC,
                    um.flyers DESC
            ) as rank
        FROM user_metrics um
    )
    SELECT 
        ru.id,
        ru.name,
        ru.avatar_url,
        ru.rank,
        ru.flyers,
        ru.leads,
        ru.conversations,
        ru.distance,
        ru.daily_snapshot as daily,
        ru.weekly_snapshot as weekly,
        ru.all_time_snapshot as all_time
    FROM ranked_users ru
    ORDER BY ru.rank
    LIMIT 500; -- Reasonable limit for leaderboard
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.get_leaderboard(TEXT, TEXT) IS 'Get leaderboard with metric and timeframe filtering, returns LeaderboardUser format';


