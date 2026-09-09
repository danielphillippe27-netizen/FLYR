-- Google Meet conference records used by the salesperson performance dashboard.
-- A calendar event represents a booking; only a completed qualifying conference
-- from the Google Meet REST API represents a held meeting.

CREATE TABLE IF NOT EXISTS public.salesperson_meeting_conferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    salesperson_id UUID NOT NULL REFERENCES public.salespeople(id) ON DELETE CASCADE,
    calendar_event_id UUID REFERENCES public.calendar_events(id) ON DELETE SET NULL,
    google_conference_record_name TEXT NOT NULL,
    google_space_name TEXT,
    google_meeting_code TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_seconds INTEGER NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
    participant_count INTEGER NOT NULL DEFAULT 0 CHECK (participant_count >= 0),
    prospect_participant_count INTEGER NOT NULL DEFAULT 0 CHECK (prospect_participant_count >= 0),
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (salesperson_id, google_conference_record_name)
);

CREATE INDEX IF NOT EXISTS idx_salesperson_meeting_conferences_held
    ON public.salesperson_meeting_conferences (salesperson_id, end_time)
    WHERE end_time IS NOT NULL
      AND prospect_participant_count > 0
      AND duration_seconds >= 300;

ALTER TABLE public.salesperson_meeting_conferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "salespeople read their meeting conferences"
    ON public.salesperson_meeting_conferences;
CREATE POLICY "salespeople read their meeting conferences"
    ON public.salesperson_meeting_conferences
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

