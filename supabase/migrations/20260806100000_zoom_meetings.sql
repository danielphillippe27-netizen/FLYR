-- Zoom OAuth credentials stay server-only. Calendar rows expose only the safe
-- participant join URL used by the iOS and web clients.

CREATE TABLE IF NOT EXISTS public.zoom_connections (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    expires_at BIGINT NOT NULL,
    zoom_user_id TEXT,
    zoom_email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.zoom_connections ENABLE ROW LEVEL SECURITY;

-- Intentionally no authenticated policies: OAuth credentials may only be read
-- or changed by server routes using the service role.
REVOKE ALL ON public.zoom_connections FROM anon, authenticated;
GRANT ALL ON public.zoom_connections TO service_role;

ALTER TABLE public.calendar_events
    ADD COLUMN IF NOT EXISTS conference_provider TEXT,
    ADD COLUMN IF NOT EXISTS conference_id TEXT,
    ADD COLUMN IF NOT EXISTS conference_join_url TEXT,
    ADD COLUMN IF NOT EXISTS attendee_emails TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_calendar_events_zoom_meetings
    ON public.calendar_events(user_id, start_at)
    WHERE conference_provider = 'zoom' AND deleted_at IS NULL;

COMMENT ON TABLE public.zoom_connections IS 'Server-only Zoom OAuth tokens for user-managed meeting creation.';
COMMENT ON COLUMN public.calendar_events.conference_join_url IS 'Participant-safe conference URL; never store a Zoom host start_url here.';

NOTIFY pgrst, 'reload schema';
