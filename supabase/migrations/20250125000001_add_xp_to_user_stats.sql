-- FLYR Add XP to User Stats Migration
-- Adds experience points (XP) field to user_stats table

-- 1. Add XP column to user_stats table
ALTER TABLE public.user_stats 
ADD COLUMN IF NOT EXISTS xp INTEGER NOT NULL DEFAULT 0;

-- 2. Add index for XP (useful for leaderboards)
CREATE INDEX IF NOT EXISTS idx_user_stats_xp ON public.user_stats(xp DESC);

-- 3. Add comment
COMMENT ON COLUMN public.user_stats.xp IS 'Experience points earned from completing challenges and activities';



