BEGIN;

-- PostgREST cannot disambiguate overloaded functions when clients omit defaulted
-- arguments. Keep one public get_leaderboard signature and move the prior
-- 3-argument implementation behind an internal name.
DROP FUNCTION IF EXISTS public.get_leaderboard(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_leaderboard(TEXT, TEXT, UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.get_leaderboard_base(TEXT, TEXT, UUID);

ALTER FUNCTION public.get_leaderboard(TEXT, TEXT, UUID)
    RENAME TO get_leaderboard_base;

CREATE OR REPLACE FUNCTION public.get_leaderboard(
    p_metric TEXT DEFAULT 'doorknocks',
    p_timeframe TEXT DEFAULT 'weekly',
    p_workspace_id UUID DEFAULT NULL,
    p_limit INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id TEXT,
    name TEXT,
    avatar_url TEXT,
    country_code TEXT,
    brokerage TEXT,
    rank INTEGER,
    doorknocks INTEGER,
    leads INTEGER,
    conversations INTEGER,
    distance DOUBLE PRECISION,
    daily JSONB,
    weekly JSONB,
    monthly JSONB,
    all_time JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM public.get_leaderboard_base(p_metric, p_timeframe, p_workspace_id)
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

REVOKE ALL ON FUNCTION public.get_leaderboard_base(TEXT, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_leaderboard_base(TEXT, TEXT, UUID) FROM anon;
REVOKE ALL ON FUNCTION public.get_leaderboard_base(TEXT, TEXT, UUID) FROM authenticated;

GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID, INTEGER, INTEGER) TO service_role;

COMMENT ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID, INTEGER, INTEGER) IS
    'Canonical leaderboard RPC signature for PostgREST; include p_workspace_id, p_limit, and p_offset to avoid overload ambiguity.';

NOTIFY pgrst, 'reload schema';

COMMIT;
