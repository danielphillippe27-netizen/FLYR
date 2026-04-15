-- Link recording sessions to route assignments (optional; null = full-campaign session)
ALTER TABLE public.sessions
    ADD COLUMN IF NOT EXISTS route_assignment_id UUID;

CREATE INDEX IF NOT EXISTS idx_sessions_route_assignment_id
    ON public.sessions (route_assignment_id)
    WHERE route_assignment_id IS NOT NULL;

COMMENT ON COLUMN public.sessions.route_assignment_id IS
    'When set, session was started from a workspace route assignment (iOS Record tab / route scope).';

NOTIFY pgrst, 'reload schema';
