-- Persist role-specific starter demo onboarding state for iOS.

BEGIN;

CREATE TABLE IF NOT EXISTS public.onboarding_demo_states (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role_path text NOT NULL CHECK (role_path IN ('solo_owner', 'team_owner', 'member')),
    seeded_campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL,
    dismissed_at timestamptz,
    completed_checklist_items text[] NOT NULL DEFAULT ARRAY[]::text[],
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_onboarding_demo_states_workspace
    ON public.onboarding_demo_states (workspace_id);

CREATE INDEX IF NOT EXISTS idx_onboarding_demo_states_seeded_campaign
    ON public.onboarding_demo_states (seeded_campaign_id)
    WHERE seeded_campaign_id IS NOT NULL;

ALTER TABLE public.onboarding_demo_states ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "onboarding_demo_states_select_own" ON public.onboarding_demo_states;
CREATE POLICY "onboarding_demo_states_select_own"
    ON public.onboarding_demo_states
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "onboarding_demo_states_insert_own" ON public.onboarding_demo_states;
CREATE POLICY "onboarding_demo_states_insert_own"
    ON public.onboarding_demo_states
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid() AND public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "onboarding_demo_states_update_own" ON public.onboarding_demo_states;
CREATE POLICY "onboarding_demo_states_update_own"
    ON public.onboarding_demo_states
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid() AND public.is_workspace_member(workspace_id));

CREATE OR REPLACE FUNCTION public.update_onboarding_demo_states_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_onboarding_demo_states_updated_at ON public.onboarding_demo_states;
CREATE TRIGGER update_onboarding_demo_states_updated_at
    BEFORE UPDATE ON public.onboarding_demo_states
    FOR EACH ROW
    EXECUTE FUNCTION public.update_onboarding_demo_states_updated_at();

GRANT SELECT, INSERT, UPDATE ON public.onboarding_demo_states TO authenticated;
GRANT ALL ON public.onboarding_demo_states TO service_role;

COMMIT;
