-- Workspace schema for FLYR: workspaces, workspace_members, and helper functions.
-- Required by 20250218000000_phase_1_1b_consolidate_leads_into_contacts and workspace-scoped RLS.
-- Idempotent: creates only if objects do not exist.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) workspaces table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workspaces_owner_id ON public.workspaces(owner_id);

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workspace_owner_full_access" ON public.workspaces;
CREATE POLICY "workspace_owner_full_access"
    ON public.workspaces
    FOR ALL
    USING (owner_id = auth.uid())
    WITH CHECK (owner_id = auth.uid());

-- Allow members to read workspace they belong to
DROP POLICY IF EXISTS "workspace_members_can_select" ON public.workspaces;
CREATE POLICY "workspace_members_can_select"
    ON public.workspaces
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members wm
            WHERE wm.workspace_id = workspaces.id AND wm.user_id = auth.uid()
        )
    );

-- ---------------------------------------------------------------------------
-- 2) workspace_members table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.workspace_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(workspace_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_workspace_members_workspace_id ON public.workspace_members(workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_members_user_id ON public.workspace_members(user_id);

ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workspace_members_select_own" ON public.workspace_members;
CREATE POLICY "workspace_members_select_own"
    ON public.workspace_members FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id = workspace_id AND w.owner_id = auth.uid()));

DROP POLICY IF EXISTS "workspace_members_insert_owner" ON public.workspace_members;
CREATE POLICY "workspace_members_insert_owner"
    ON public.workspace_members FOR INSERT TO authenticated
    WITH CHECK (EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id = workspace_id AND w.owner_id = auth.uid()));

DROP POLICY IF EXISTS "workspace_members_update_owner" ON public.workspace_members;
CREATE POLICY "workspace_members_update_owner"
    ON public.workspace_members FOR UPDATE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id = workspace_id AND w.owner_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id = workspace_id AND w.owner_id = auth.uid()));

DROP POLICY IF EXISTS "workspace_members_delete_owner" ON public.workspace_members;
CREATE POLICY "workspace_members_delete_owner"
    ON public.workspace_members FOR DELETE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workspaces w WHERE w.id = workspace_id AND w.owner_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- 3) primary_workspace_id(p_user_id uuid) -> uuid
-- Returns the user's primary workspace: owned workspace first, else first membership.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.primary_workspace_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT id FROM public.workspaces WHERE owner_id = p_user_id ORDER BY created_at ASC LIMIT 1),
        (SELECT workspace_id FROM public.workspace_members WHERE user_id = p_user_id ORDER BY created_at ASC LIMIT 1)
    );
$$;

COMMENT ON FUNCTION public.primary_workspace_id(uuid) IS 'Returns primary workspace for user: owned workspace first, else first membership.';

-- ---------------------------------------------------------------------------
-- 4) is_workspace_member(ws_id uuid) -> boolean
-- True if current auth.uid() is a member of the workspace (owner or in workspace_members).
-- Uses ws_id so CREATE OR REPLACE works when the function already exists (policies depend on it).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_workspace_member(ws_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.workspaces w WHERE w.id = ws_id AND w.owner_id = auth.uid()
    ) OR EXISTS (
        SELECT 1 FROM public.workspace_members wm WHERE wm.workspace_id = ws_id AND wm.user_id = auth.uid()
    );
$$;

COMMENT ON FUNCTION public.is_workspace_member(uuid) IS 'True if current user is owner or member of the given workspace.';

GRANT EXECUTE ON FUNCTION public.primary_workspace_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid) TO authenticated;

COMMIT;
