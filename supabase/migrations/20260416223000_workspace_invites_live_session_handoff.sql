BEGIN;

ALTER TABLE public.workspace_invites
    ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES public.sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_workspace_invites_session_id
    ON public.workspace_invites(session_id)
    WHERE session_id IS NOT NULL;

COMMENT ON COLUMN public.workspace_invites.session_id
    IS 'Optional source live session for invite handoff so invitees can be routed back into shared live mode.';

COMMIT;
