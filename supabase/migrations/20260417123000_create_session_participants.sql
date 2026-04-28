BEGIN;

CREATE TABLE IF NOT EXISTS public.session_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('host', 'member')),
    joined_via_invite_id UUID NULL REFERENCES public.workspace_invites(id) ON DELETE SET NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_session_participants_session_active
    ON public.session_participants(session_id, left_at);

CREATE INDEX IF NOT EXISTS idx_session_participants_campaign_active
    ON public.session_participants(campaign_id, left_at);

CREATE INDEX IF NOT EXISTS idx_session_participants_user_active
    ON public.session_participants(user_id, left_at);

ALTER TABLE public.session_participants ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_session_participant(
    p_session_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.session_participants sp
        WHERE sp.session_id = p_session_id
          AND (sp.user_id::text) = (p_user_id::text)
          AND sp.left_at IS NULL
    );
$$;

COMMENT ON FUNCTION public.is_session_participant(uuid, uuid)
    IS 'True when the given user is an active participant in the session.';

DROP POLICY IF EXISTS "session_participants_select_member" ON public.session_participants;
CREATE POLICY "session_participants_select_member"
    ON public.session_participants
    FOR SELECT TO authenticated
    USING (public.is_campaign_member(campaign_id));

DROP POLICY IF EXISTS "session_participants_insert_self" ON public.session_participants;
CREATE POLICY "session_participants_insert_self"
    ON public.session_participants
    FOR INSERT TO authenticated
    WITH CHECK (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
        AND EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_id
              AND s.campaign_id = campaign_id
        )
    );

DROP POLICY IF EXISTS "session_participants_update_self" ON public.session_participants;
CREATE POLICY "session_participants_update_self"
    ON public.session_participants
    FOR UPDATE TO authenticated
    USING (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
    )
    WITH CHECK (
        (user_id::text) = (auth.uid()::text)
        AND public.is_campaign_member(campaign_id)
        AND EXISTS (
            SELECT 1
            FROM public.sessions s
            WHERE s.id = session_id
              AND s.campaign_id = campaign_id
        )
    );

GRANT SELECT, INSERT, UPDATE ON public.session_participants TO authenticated;
GRANT ALL ON public.session_participants TO service_role;
GRANT EXECUTE ON FUNCTION public.is_session_participant(uuid, uuid) TO authenticated, service_role;

COMMIT;
