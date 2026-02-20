-- Workspace-scoped campaigns, sessions, field_leads, and leaderboard RPC.
-- Depends on 20250217500000_create_workspaces_schema (workspaces, workspace_members, primary_workspace_id, is_workspace_member).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1.0 field_leads: add workspace_id so app can write it (contacts already have it from 20250218000000)
-- ---------------------------------------------------------------------------
ALTER TABLE public.field_leads
    ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_field_leads_workspace_id ON public.field_leads(workspace_id);

-- Backfill from user's primary workspace
UPDATE public.field_leads fl
SET workspace_id = public.primary_workspace_id(fl.user_id)
WHERE fl.workspace_id IS NULL AND fl.user_id IS NOT NULL;

-- RLS: allow workspace members to read/write (in addition to owner)
DROP POLICY IF EXISTS "field_leads_select_own" ON public.field_leads;
CREATE POLICY "field_leads_select_own"
    ON public.field_leads FOR SELECT TO authenticated
    USING (auth.uid() = user_id OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id)));

DROP POLICY IF EXISTS "field_leads_insert_own" ON public.field_leads;
CREATE POLICY "field_leads_insert_own"
    ON public.field_leads FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id)));

DROP POLICY IF EXISTS "field_leads_update_own" ON public.field_leads;
CREATE POLICY "field_leads_update_own"
    ON public.field_leads FOR UPDATE TO authenticated
    USING (auth.uid() = user_id OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id)))
    WITH CHECK (auth.uid() = user_id OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id)));

DROP POLICY IF EXISTS "field_leads_delete_own" ON public.field_leads;
CREATE POLICY "field_leads_delete_own"
    ON public.field_leads FOR DELETE TO authenticated
    USING (auth.uid() = user_id OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id)));

-- ---------------------------------------------------------------------------
-- 1.1 Campaigns: add workspace_id, backfill, RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.campaigns
    ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_campaigns_workspace_id ON public.campaigns(workspace_id);

UPDATE public.campaigns c
SET workspace_id = public.primary_workspace_id(c.owner_id)
WHERE c.workspace_id IS NULL AND c.owner_id IS NOT NULL;

-- RLS: allow workspace members to manage campaigns in their workspace (in addition to owner)
DROP POLICY IF EXISTS "campaigns_workspace_members" ON public.campaigns;
CREATE POLICY "campaigns_workspace_members"
    ON public.campaigns
    FOR ALL
    USING (
        owner_id = auth.uid()
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    )
    WITH CHECK (
        owner_id = auth.uid()
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

-- ---------------------------------------------------------------------------
-- 1.2 Sessions: add workspace_id, backfill, RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.sessions
    ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_workspace_id ON public.sessions(workspace_id);

UPDATE public.sessions s
SET workspace_id = public.primary_workspace_id(s.user_id)
WHERE s.workspace_id IS NULL AND s.user_id IS NOT NULL;

-- Allow workspace members to read team sessions (select only); insert/update/delete stay owner-only
DROP POLICY IF EXISTS "Users can read their own sessions" ON public.sessions;
CREATE POLICY "Users can read their own sessions"
    ON public.sessions
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR (workspace_id IS NOT NULL AND public.is_workspace_member(workspace_id))
    );

-- ---------------------------------------------------------------------------
-- 1.5 Leaderboard RPC: add optional p_workspace_id
-- When p_workspace_id is not null, restrict to users in that workspace and sessions in that workspace.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_leaderboard(text, text);
DROP FUNCTION IF EXISTS public.get_leaderboard(text, text, uuid);

CREATE OR REPLACE FUNCTION public.get_leaderboard(
    p_metric TEXT DEFAULT 'flyers',
    p_timeframe TEXT DEFAULT 'weekly',
    p_workspace_id uuid DEFAULT NULL
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
SET search_path = public
AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
BEGIN
    CASE p_timeframe
        WHEN 'daily' THEN v_start_date := date_trunc('day', NOW());
        WHEN 'weekly' THEN v_start_date := date_trunc('week', NOW());
        WHEN 'monthly' THEN v_start_date := date_trunc('month', NOW());
        WHEN 'all_time' THEN v_start_date := '1970-01-01'::TIMESTAMPTZ;
        ELSE v_start_date := date_trunc('week', NOW());
    END CASE;

    IF p_workspace_id IS NOT NULL THEN
        -- Workspace-scoped: only users in this workspace, and only their sessions in this workspace
        RETURN QUERY
        WITH workspace_user_ids AS (
            SELECT wm.user_id
            FROM public.workspace_members wm
            WHERE wm.workspace_id = p_workspace_id
            UNION
            SELECT w.owner_id FROM public.workspaces w WHERE w.id = p_workspace_id
        ),
        session_stats AS (
            SELECT
                s.user_id,
                COALESCE(SUM(s.flyers_delivered), 0)::INTEGER AS session_flyers,
                COALESCE(SUM(s.conversations), 0)::INTEGER AS session_conversations,
                COALESCE(SUM(s.distance_meters), 0)::DOUBLE PRECISION / 1000.0 AS session_distance_km
            FROM public.sessions s
            WHERE s.start_time >= v_start_date
              AND (s.workspace_id = p_workspace_id OR (s.workspace_id IS NULL AND s.user_id IN (SELECT user_id FROM workspace_user_ids)))
            GROUP BY s.user_id
        ),
        ranked_users AS (
            SELECT
                au.id::TEXT AS user_id,
                COALESCE(au.raw_user_meta_data->>'full_name', SPLIT_PART(au.email, '@', 1), 'Agent') AS display_name,
                COALESCE(au.raw_user_meta_data->>'avatar_url', NULL)::TEXT AS user_avatar,
                COALESCE(ss.session_flyers, 0) AS user_flyers,
                COALESCE(ss.session_conversations, 0) AS user_conversations,
                COALESCE(ss.session_distance_km, 0.0) AS user_distance,
                jsonb_build_object(
                    'flyers', COALESCE(ss.session_flyers, 0),
                    'conversations', COALESCE(ss.session_conversations, 0),
                    'distance', COALESCE(ss.session_distance_km, 0.0),
                    'leads', 0
                ) AS snapshot
            FROM auth.users au
            INNER JOIN workspace_user_ids wu ON au.id = wu.user_id
            LEFT JOIN session_stats ss ON au.id = ss.user_id
            WHERE COALESCE(ss.session_flyers, 0) > 0 OR COALESCE(ss.session_conversations, 0) > 0
        )
        SELECT
            ru.user_id,
            ru.display_name,
            ru.user_avatar,
            (ROW_NUMBER() OVER (
                ORDER BY
                    CASE p_metric
                        WHEN 'flyers' THEN ru.user_flyers
                        WHEN 'conversations' THEN ru.user_conversations
                        WHEN 'distance' THEN ru.user_distance::INTEGER
                        ELSE ru.user_flyers
                    END DESC
            ))::INTEGER,
            ru.user_flyers,
            0::INTEGER,
            ru.user_conversations,
            ru.user_distance,
            ru.snapshot,
            ru.snapshot,
            ru.snapshot
        FROM ranked_users ru
        ORDER BY 4
        LIMIT 100;
    ELSE
        -- Global (backward compatible): all users with session activity
        RETURN QUERY
        WITH session_stats AS (
            SELECT
                s.user_id,
                COALESCE(SUM(s.flyers_delivered), 0)::INTEGER AS session_flyers,
                COALESCE(SUM(s.conversations), 0)::INTEGER AS session_conversations,
                COALESCE(SUM(s.distance_meters), 0)::DOUBLE PRECISION / 1000.0 AS session_distance_km
            FROM public.sessions s
            WHERE s.start_time >= v_start_date
            GROUP BY s.user_id
        ),
        ranked_users AS (
            SELECT
                au.id::TEXT AS user_id,
                COALESCE(au.raw_user_meta_data->>'full_name', SPLIT_PART(au.email, '@', 1), 'Agent') AS display_name,
                COALESCE(au.raw_user_meta_data->>'avatar_url', NULL)::TEXT AS user_avatar,
                COALESCE(ss.session_flyers, 0) AS user_flyers,
                COALESCE(ss.session_conversations, 0) AS user_conversations,
                COALESCE(ss.session_distance_km, 0.0) AS user_distance,
                jsonb_build_object(
                    'flyers', COALESCE(ss.session_flyers, 0),
                    'conversations', COALESCE(ss.session_conversations, 0),
                    'distance', COALESCE(ss.session_distance_km, 0.0),
                    'leads', 0
                ) AS snapshot
            FROM auth.users au
            LEFT JOIN session_stats ss ON au.id = ss.user_id
            WHERE COALESCE(ss.session_flyers, 0) > 0 OR COALESCE(ss.session_conversations, 0) > 0
        )
        SELECT
            ru.user_id,
            ru.display_name,
            ru.user_avatar,
            (ROW_NUMBER() OVER (
                ORDER BY
                    CASE p_metric
                        WHEN 'flyers' THEN ru.user_flyers
                        WHEN 'conversations' THEN ru.user_conversations
                        WHEN 'distance' THEN ru.user_distance::INTEGER
                        ELSE ru.user_flyers
                    END DESC
            ))::INTEGER,
            ru.user_flyers,
            0::INTEGER,
            ru.user_conversations,
            ru.user_distance,
            ru.snapshot,
            ru.snapshot,
            ru.snapshot
        FROM ranked_users ru
        ORDER BY 4
        LIMIT 100;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) TO authenticated;

COMMENT ON FUNCTION public.get_leaderboard(TEXT, TEXT, UUID) IS 'Leaderboard with optional workspace scope. When p_workspace_id is null, global; else restricted to workspace members and their sessions.';

COMMIT;
