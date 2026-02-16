-- Backfill sessions.flyers_delivered from completed_count for building sessions
-- so leaderboard (which reads sessions.flyers_delivered) matches "You" stats (user_stats).
-- Run once; safe to re-run (only updates where flyers_delivered = 0 and completed_count > 0).

UPDATE public.sessions
SET flyers_delivered = completed_count
WHERE flyers_delivered = 0
  AND completed_count > 0
  AND end_time IS NOT NULL;
