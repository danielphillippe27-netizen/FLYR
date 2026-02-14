-- BACKFILL SCRIPT (Run AFTER main migration)
-- This is a ONE-TIME script to set default values for existing sessions
-- that were created before the flyers_delivered and conversations columns existed

-- NOTE: This will set existing sessions to 0 flyers and 0 conversations
-- Only NEW sessions will have accurate tracking

-- Step 1: Set defaults for existing NULL values
UPDATE public.sessions 
SET 
    flyers_delivered = 0,
    conversations = 0
WHERE flyers_delivered IS NULL OR conversations IS NULL;

-- Verification query (optional - run this to check results)
SELECT 
    COUNT(*) as total_sessions,
    COUNT(CASE WHEN flyers_delivered > 0 THEN 1 END) as sessions_with_flyers,
    COUNT(CASE WHEN conversations > 0 THEN 1 END) as sessions_with_conversations,
    SUM(flyers_delivered) as total_flyers,
    SUM(conversations) as total_conversations
FROM public.sessions;
