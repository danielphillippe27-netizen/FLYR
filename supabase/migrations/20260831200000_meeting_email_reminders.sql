CREATE TABLE IF NOT EXISTS public.meeting_email_reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    calendar_event_id UUID NOT NULL REFERENCES public.calendar_events(id) ON DELETE CASCADE,
    recipient_email TEXT NOT NULL,
    host_email TEXT,
    time_zone TEXT,
    scheduled_for TIMESTAMPTZ NOT NULL,
    sent_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (calendar_event_id, recipient_email)
);

CREATE INDEX IF NOT EXISTS idx_meeting_email_reminders_due
    ON public.meeting_email_reminders(scheduled_for)
    WHERE sent_at IS NULL;

ALTER TABLE public.meeting_email_reminders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.meeting_email_reminders FROM anon, authenticated;
GRANT ALL ON public.meeting_email_reminders TO service_role;

COMMENT ON TABLE public.meeting_email_reminders IS 'Server-only five-minute reminders for direct meeting invitations.';

NOTIFY pgrst, 'reload schema';
