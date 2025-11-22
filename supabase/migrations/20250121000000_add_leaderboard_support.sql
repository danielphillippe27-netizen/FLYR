-- Migration: Add leaderboard support with time tracking and real-time updates
-- Creates indexes, RLS policies, views, and functions for global leaderboard

-- 1. Add time_tracked column to user_stats (in minutes)
ALTER TABLE public.user_stats 
ADD COLUMN IF NOT EXISTS time_tracked INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.user_stats.time_tracked IS 'Total time tracked in minutes';

-- 2. Create indexes for leaderboard queries (performance optimization)
CREATE INDEX IF NOT EXISTS idx_user_stats_flyers ON public.user_stats(flyers DESC);
CREATE INDEX IF NOT EXISTS idx_user_stats_conversations ON public.user_stats(conversations DESC);
CREATE INDEX IF NOT EXISTS idx_user_stats_leads ON public.user_stats(leads_created DESC);
CREATE INDEX IF NOT EXISTS idx_user_stats_distance ON public.user_stats(distance_walked DESC);
CREATE INDEX IF NOT EXISTS idx_user_stats_time ON public.user_stats(time_tracked DESC);

-- 3. Create composite index for multi-sort leaderboards
CREATE INDEX IF NOT EXISTS idx_user_stats_leaderboard ON public.user_stats(
    flyers DESC, 
    conversations DESC, 
    leads_created DESC, 
    distance_walked DESC, 
    time_tracked DESC
);

-- 4. Add RLS policy for public leaderboard read access
-- Users can read all stats for leaderboard purposes
DROP POLICY IF EXISTS "user_stats_select_leaderboard" ON public.user_stats;
CREATE POLICY "user_stats_select_leaderboard"
    ON public.user_stats
    FOR SELECT
    TO authenticated
    USING (true); -- Allow all authenticated users to read stats for leaderboard

-- Note: Keep existing "user_stats_select_own" for backward compatibility
-- The more permissive policy will allow leaderboard access

-- 5. Create leaderboard view with user email/display info
-- This joins with auth.users to get user metadata
CREATE OR REPLACE VIEW public.leaderboard AS
SELECT 
    us.id,
    us.user_id,
    COALESCE(au.email, 'Anonymous') as user_email,
    us.flyers,
    us.conversations,
    us.leads_created as leads,
    us.distance_walked as distance,
    us.time_tracked as time_minutes,
    us.day_streak,
    us.best_streak,
    us.updated_at,
    us.created_at,
    -- Calculate rank based on flyers (primary metric)
    ROW_NUMBER() OVER (ORDER BY us.flyers DESC, us.conversations DESC, us.leads_created DESC) as rank_by_flyers,
    ROW_NUMBER() OVER (ORDER BY us.conversations DESC, us.flyers DESC) as rank_by_conversations,
    ROW_NUMBER() OVER (ORDER BY us.leads_created DESC, us.flyers DESC) as rank_by_leads,
    ROW_NUMBER() OVER (ORDER BY us.distance_walked DESC) as rank_by_distance,
    ROW_NUMBER() OVER (ORDER BY us.time_tracked DESC) as rank_by_time
FROM public.user_stats us
LEFT JOIN auth.users au ON us.user_id = au.id
WHERE us.flyers > 0 OR us.conversations > 0 OR us.leads_created > 0; -- Only show active users

-- 6. Enable RLS on the view (inherits from base table)
ALTER VIEW public.leaderboard SET (security_invoker = true);

-- 7. Grant permissions on the view
GRANT SELECT ON public.leaderboard TO authenticated;

-- 8. Create function for efficient leaderboard queries with pagination
CREATE OR REPLACE FUNCTION public.get_leaderboard(
    sort_by TEXT DEFAULT 'flyers',
    limit_count INTEGER DEFAULT 100,
    offset_count INTEGER DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    user_email TEXT,
    flyers INTEGER,
    conversations INTEGER,
    leads INTEGER,
    distance DOUBLE PRECISION,
    time_minutes INTEGER,
    day_streak INTEGER,
    best_streak INTEGER,
    rank INTEGER,
    updated_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH ranked AS (
        SELECT 
            lb.id,
            lb.user_id,
            lb.user_email,
            lb.flyers,
            lb.conversations,
            lb.leads,
            lb.distance,
            lb.time_minutes,
            lb.day_streak,
            lb.best_streak,
            lb.updated_at,
            CASE 
                WHEN sort_by = 'flyers' THEN lb.rank_by_flyers
                WHEN sort_by = 'conversations' THEN lb.rank_by_conversations
                WHEN sort_by = 'leads' THEN lb.rank_by_leads
                WHEN sort_by = 'distance' THEN lb.rank_by_distance
                WHEN sort_by = 'time' THEN lb.rank_by_time
                ELSE lb.rank_by_flyers
            END as rank
        FROM public.leaderboard lb
    )
    SELECT 
        ranked.id,
        ranked.user_id,
        ranked.user_email,
        ranked.flyers,
        ranked.conversations,
        ranked.leads,
        ranked.distance,
        ranked.time_minutes,
        ranked.day_streak,
        ranked.best_streak,
        ranked.rank,
        ranked.updated_at
    FROM ranked
    ORDER BY 
        CASE sort_by
            WHEN 'flyers' THEN ranked.flyers
            WHEN 'conversations' THEN ranked.conversations
            WHEN 'leads' THEN ranked.leads
            WHEN 'distance' THEN ranked.distance
            WHEN 'time' THEN ranked.time_minutes
            ELSE ranked.flyers
        END DESC NULLS LAST,
        ranked.flyers DESC -- Secondary sort for consistency
    LIMIT limit_count
    OFFSET offset_count;
END;
$$;

-- 9. Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_leaderboard TO authenticated;

-- 10. Add comment
COMMENT ON FUNCTION public.get_leaderboard IS 'Get leaderboard sorted by specified metric with pagination';



