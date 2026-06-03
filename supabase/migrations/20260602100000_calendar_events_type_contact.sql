ALTER TABLE public.calendar_events
    ADD COLUMN IF NOT EXISTS event_type TEXT NOT NULL DEFAULT 'appointment',
    ADD COLUMN IF NOT EXISTS contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS contact_name TEXT,
    ADD COLUMN IF NOT EXISTS contact_address TEXT;

CREATE INDEX IF NOT EXISTS idx_calendar_events_contact_id
    ON public.calendar_events(contact_id)
    WHERE contact_id IS NOT NULL AND deleted_at IS NULL;

